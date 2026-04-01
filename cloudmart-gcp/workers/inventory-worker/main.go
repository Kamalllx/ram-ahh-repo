// CloudMart Inventory Worker
// Runs on Compute Engine (e2-medium). Subscribes to Pub/Sub order events
// and updates inventory levels in Cloud SQL (PostgreSQL).
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"cloud.google.com/go/pubsub"
	secretmanager "cloud.google.com/go/secretmanager/apiv1"
	"cloud.google.com/go/secretmanager/apiv1/secretmanagerpb"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

// OrderEvent matches the Avro schema published by order-service
type OrderEvent struct {
	OrderID     string  `json:"order_id"`
	UserID      string  `json:"user_id"`
	EventType   string  `json:"event_type"` // placed, confirmed, shipped, delivered, cancelled
	TotalAmount float64 `json:"total_amount"`
	ItemCount   int     `json:"item_count"`
	Timestamp   string  `json:"timestamp"`
	Metadata    string  `json:"metadata"`
}

type OrderItem struct {
	ProductID string `json:"product_id"`
	Quantity  int    `json:"quantity"`
}

type Worker struct {
	db     *pgxpool.Pool
	ps     *pubsub.Client
	logger *zap.Logger
}

func main() {
	logger, _ := zap.NewProduction()
	defer logger.Sync()

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	project := mustEnv("GCP_PROJECT")
	subName := mustEnv("PUBSUB_SUBSCRIPTION")

	// ── Fetch DB password from Secret Manager ─────────────────
	dbPass, err := fetchSecret(ctx, project, "cloudmart-db-password")
	if err != nil {
		logger.Fatal("Failed to fetch DB secret", zap.Error(err))
	}

	// ── Connect to Cloud SQL via Unix socket ──────────────────
	connStr := buildConnStr(dbPass)
	pool, err := pgxpool.New(ctx, connStr)
	if err != nil {
		logger.Fatal("Failed to connect to PostgreSQL", zap.Error(err))
	}
	defer pool.Close()

	if err := pool.Ping(ctx); err != nil {
		logger.Fatal("PostgreSQL ping failed", zap.Error(err))
	}
	logger.Info("Connected to Cloud SQL")

	// Ensure inventory table exists
	if err := initSchema(ctx, pool); err != nil {
		logger.Fatal("Schema init failed", zap.Error(err))
	}

	// ── Connect to Pub/Sub ────────────────────────────────────
	psClient, err := pubsub.NewClient(ctx, project)
	if err != nil {
		logger.Fatal("Failed to create Pub/Sub client", zap.Error(err))
	}
	defer psClient.Close()

	sub := psClient.Subscription(subName)
	sub.ReceiveSettings.MaxOutstandingMessages = 10
	sub.ReceiveSettings.NumGoroutines = 4

	w := &Worker{db: pool, ps: psClient, logger: logger}

	logger.Info("Inventory worker started", zap.String("subscription", subName))

	err = sub.Receive(ctx, func(ctx context.Context, msg *pubsub.Message) {
		if err := w.handleMessage(ctx, msg); err != nil {
			logger.Error("Failed to handle message — nacking",
				zap.Error(err),
				zap.String("msg_id", msg.ID),
			)
			msg.Nack()
			return
		}
		msg.Ack()
	})

	if err != nil && ctx.Err() == nil {
		logger.Fatal("Pub/Sub receive error", zap.Error(err))
	}
	logger.Info("Worker shut down gracefully")
}

func (w *Worker) handleMessage(ctx context.Context, msg *pubsub.Message) error {
	var event OrderEvent
	if err := json.Unmarshal(msg.Data, &event); err != nil {
		return fmt.Errorf("unmarshal: %w", err)
	}

	w.logger.Info("Received order event",
		zap.String("event_type", event.EventType),
		zap.String("order_id", event.OrderID),
	)

	switch event.EventType {
	case "placed":
		return w.reserveInventory(ctx, event)
	case "cancelled", "refunded":
		return w.releaseInventory(ctx, event)
	case "delivered":
		return w.confirmInventoryDeduction(ctx, event)
	default:
		w.logger.Debug("Ignoring event type", zap.String("type", event.EventType))
		return nil
	}
}

func (w *Worker) reserveInventory(ctx context.Context, event OrderEvent) error {
	// In a real system, we'd parse items from the metadata.
	// Here we record the reservation as an audit log entry.
	_, err := w.db.Exec(ctx, `
		INSERT INTO inventory_events (order_id, event_type, item_count, total_amount, processed_at)
		VALUES ($1, $2, $3, $4, NOW())
		ON CONFLICT (order_id, event_type) DO NOTHING
	`, event.OrderID, "reserved", event.ItemCount, event.TotalAmount)
	if err != nil {
		return fmt.Errorf("reserveInventory: %w", err)
	}
	w.logger.Info("Inventory reserved", zap.String("order_id", event.OrderID))
	return nil
}

func (w *Worker) releaseInventory(ctx context.Context, event OrderEvent) error {
	_, err := w.db.Exec(ctx, `
		INSERT INTO inventory_events (order_id, event_type, item_count, total_amount, processed_at)
		VALUES ($1, $2, $3, $4, NOW())
		ON CONFLICT (order_id, event_type) DO NOTHING
	`, event.OrderID, "released", event.ItemCount, event.TotalAmount)
	if err != nil {
		return fmt.Errorf("releaseInventory: %w", err)
	}
	w.logger.Info("Inventory released", zap.String("order_id", event.OrderID))
	return nil
}

func (w *Worker) confirmInventoryDeduction(ctx context.Context, event OrderEvent) error {
	_, err := w.db.Exec(ctx, `
		INSERT INTO inventory_events (order_id, event_type, item_count, total_amount, processed_at)
		VALUES ($1, $2, $3, $4, NOW())
		ON CONFLICT (order_id, event_type) DO NOTHING
	`, event.OrderID, "confirmed", event.ItemCount, event.TotalAmount)
	if err != nil {
		return fmt.Errorf("confirmInventoryDeduction: %w", err)
	}
	w.logger.Info("Inventory deduction confirmed", zap.String("order_id", event.OrderID))
	return nil
}

func initSchema(ctx context.Context, pool *pgxpool.Pool) error {
	_, err := pool.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS inventory_events (
			id           BIGSERIAL PRIMARY KEY,
			order_id     UUID        NOT NULL,
			event_type   VARCHAR(50) NOT NULL,
			item_count   INT         NOT NULL,
			total_amount NUMERIC     NOT NULL,
			processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			UNIQUE (order_id, event_type)
		);
		CREATE INDEX IF NOT EXISTS idx_inv_events_order ON inventory_events(order_id);
		CREATE INDEX IF NOT EXISTS idx_inv_events_ts    ON inventory_events(processed_at);
	`)
	return err
}

func fetchSecret(ctx context.Context, project, secretID string) (string, error) {
	client, err := secretmanager.NewClient(ctx)
	if err != nil {
		return "", err
	}
	defer client.Close()

	name := fmt.Sprintf("projects/%s/secrets/%s/versions/latest", project, secretID)
	result, err := client.AccessSecretVersion(ctx, &secretmanagerpb.AccessSecretVersionRequest{Name: name})
	if err != nil {
		return "", err
	}
	return string(result.Payload.Data), nil
}

func buildConnStr(password string) string {
	connName := os.Getenv("DB_CONNECTION_NAME")
	user     := os.Getenv("DB_USER")
	dbName   := os.Getenv("DB_NAME")

	if host := os.Getenv("DB_HOST"); host != "" {
		// Local / dev
		return fmt.Sprintf("host=%s user=%s password=%s dbname=%s sslmode=disable", host, user, password, dbName)
	}

	// Cloud SQL Unix socket
	socketDir := fmt.Sprintf("/cloudsql/%s", connName)
	return fmt.Sprintf("host=%s user=%s password=%s dbname=%s sslmode=disable", socketDir, user, password, dbName)
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		panic(fmt.Sprintf("required environment variable %s is not set", key))
	}
	return v
}

// Retry helper with exponential backoff
func withRetry(ctx context.Context, fn func() error, maxAttempts int) error {
	var err error
	for i := 0; i < maxAttempts; i++ {
		err = fn()
		if err == nil {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Duration(1<<i) * time.Second):
		}
	}
	return fmt.Errorf("after %d attempts: %w", maxAttempts, err)
}
