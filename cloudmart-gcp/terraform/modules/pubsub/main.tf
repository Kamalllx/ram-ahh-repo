variable "project_id" {}
variable "app_name" {}
variable "order_notifier_sa" {}

# ── Topics ───────────────────────────────────────────────────

resource "google_pubsub_topic" "orders" {
  name    = "${var.app_name}-orders"
  project = var.project_id

  message_retention_duration = "86400s" # 24 hours

  schema_settings {
    schema   = google_pubsub_schema.order_event.id
    encoding = "JSON"
  }

  labels = {
    app = var.app_name
  }
}

resource "google_pubsub_schema" "order_event" {
  name    = "${var.app_name}-order-event"
  project = var.project_id
  type    = "AVRO"

  definition = jsonencode({
    type = "record"
    name = "OrderEvent"
    fields = [
      { name = "order_id",    type = "string" },
      { name = "user_id",     type = "string" },
      { name = "event_type",  type = "string" },  # placed, confirmed, shipped, delivered, cancelled
      { name = "total_amount",type = "double" },
      { name = "item_count",  type = "int" },
      { name = "timestamp",   type = "string" },
      { name = "metadata",    type = ["null", "string"], default = null },
    ]
  })
}

resource "google_pubsub_topic" "inventory" {
  name    = "${var.app_name}-inventory"
  project = var.project_id

  message_retention_duration = "3600s"

  labels = {
    app = var.app_name
  }
}

resource "google_pubsub_topic" "dlq" {
  name    = "${var.app_name}-dlq"
  project = var.project_id

  labels = {
    app  = var.app_name
    type = "dead-letter"
  }
}

# ── Subscriptions ────────────────────────────────────────────

# Order Notifier subscription (Cloud Function consumes this)
resource "google_pubsub_subscription" "orders_notifier" {
  name    = "${var.app_name}-orders-notifier"
  topic   = google_pubsub_topic.orders.name
  project = var.project_id

  ack_deadline_seconds       = 60
  message_retention_duration = "86400s"
  retain_acked_messages      = false

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }

  filter = "attributes.event_type = \"placed\" OR attributes.event_type = \"shipped\""
}

# Analytics subscription (BigQuery sink)
resource "google_pubsub_subscription" "orders_analytics" {
  name    = "${var.app_name}-orders-analytics"
  topic   = google_pubsub_topic.orders.name
  project = var.project_id

  ack_deadline_seconds       = 120
  message_retention_duration = "604800s"  # 7 days

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq.id
    max_delivery_attempts = 10
  }
}

# Inventory worker subscription
resource "google_pubsub_subscription" "inventory_worker" {
  name    = "${var.app_name}-inventory-worker"
  topic   = google_pubsub_topic.inventory.name
  project = var.project_id

  ack_deadline_seconds = 300
  enable_exactly_once_delivery = true
}

# ── IAM ──────────────────────────────────────────────────────
resource "google_pubsub_subscription_iam_member" "notifier_subscriber" {
  project      = var.project_id
  subscription = google_pubsub_subscription.orders_notifier.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.order_notifier_sa}"
}

# ── Outputs ──────────────────────────────────────────────────
output "orders_topic_name"          { value = google_pubsub_topic.orders.name }
output "orders_topic_id"            { value = google_pubsub_topic.orders.id }
output "inventory_topic_name"       { value = google_pubsub_topic.inventory.name }
output "orders_notifier_sub_id"     { value = google_pubsub_subscription.orders_notifier.id }
output "orders_analytics_sub_id"    { value = google_pubsub_subscription.orders_analytics.id }
