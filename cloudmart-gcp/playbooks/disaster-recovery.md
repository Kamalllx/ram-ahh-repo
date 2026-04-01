# Disaster Recovery Runbook

## RTO / RPO Targets

| Scenario | RTO | RPO |
|----------|-----|-----|
| GKE pod failure | 30s (auto) | 0 |
| Cloud Run instance failure | 10s (auto) | 0 |
| Cloud SQL primary failure | 2 min (failover) | ~5s |
| GCS bucket corruption | 4 hours | 24h (versioning) |
| Region outage | 4 hours | 15 min |

## Runbook: Cloud SQL Failover

```bash
# Trigger manual failover (if automatic failover doesn't trigger within 2 min)
gcloud sql instances failover cloudmart-postgres \
  --project=YOUR_PROJECT_ID

# Verify new primary
gcloud sql instances describe cloudmart-postgres \
  --format="value(failoverReplica.available)"
```

## Runbook: GKE Node Failure

Handled automatically by GKE's node auto-repair. Verify:

```bash
kubectl get nodes -n cloudmart
kubectl describe node <failed-node>
# If stuck:
gcloud container clusters upgrade cloudmart-cluster \
  --master --cluster-version=$(gcloud container get-server-config \
  --format="value(defaultClusterVersion)")
```

## Runbook: Pub/Sub Dead Letter Queue Drain

```bash
# Check DLQ message count
gcloud pubsub subscriptions describe cloudmart-dlq \
  --format="value(deadLetterPolicy)"

# Pull and inspect stuck messages
gcloud pubsub subscriptions pull cloudmart-dlq --limit=10

# Replay to original topic
gcloud pubsub subscriptions seek cloudmart-orders-notifier \
  --time=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
```

## Runbook: Redis Cache Flush (Corruption)

```bash
# Connect via Cloud Shell with IP allowlist
gcloud redis instances describe cloudmart-redis \
  --region=us-central1 --format="value(host,port)"

# Flush all keys (CAUTION — users must re-login)
redis-cli -h <HOST> -p 6379 FLUSHALL
```

## Backup Verification (Monthly)

```bash
# List Cloud SQL backups
gcloud sql backups list --instance=cloudmart-postgres

# Test restore to a temp instance
gcloud sql instances create cloudmart-restore-test \
  --source-instance=cloudmart-postgres \
  --backup-id=<BACKUP_ID>

# Verify data integrity
psql "host=<TEMP_IP> dbname=cloudmart user=cloudmart_admin" \
  -c "SELECT COUNT(*) FROM orders; SELECT COUNT(*) FROM users;"

# Clean up
gcloud sql instances delete cloudmart-restore-test
```
