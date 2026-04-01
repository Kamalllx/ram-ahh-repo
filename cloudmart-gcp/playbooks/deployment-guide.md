# CloudMart Deployment Guide

## Prerequisites

| Tool | Minimum Version |
|------|----------------|
| gcloud CLI | 450.0.0+ |
| Terraform | 1.6.0+ |
| kubectl | 1.28+ |
| Docker | 24.0+ |
| Node.js | 20.0+ |
| Python | 3.12+ |
| Go | 1.22+ |

## First-Time Setup

### 1. Authenticate with GCP

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

### 2. Bootstrap infrastructure

```bash
cd cloudmart-gcp
chmod +x scripts/*.sh

# Creates all GCP resources via Terraform
./scripts/setup.sh YOUR_PROJECT_ID us-central1
```

This provisions:
- VPC, subnets, Cloud NAT, Firewall rules
- GKE cluster (2-node, auto-scaling 1-5)
- Cloud SQL PostgreSQL (with read replica)
- Firestore database
- Cloud Storage buckets (images, assets, functions)
- Pub/Sub topics and subscriptions
- Memorystore Redis
- BigQuery dataset and tables
- Cloud Run services (API Gateway + User Service)
- Cloud Functions (3 functions)
- Compute Engine (Inventory Worker VM)
- IAM service accounts with least-privilege roles
- Cloud DNS zone
- Cloud Armor WAF policy
- Cloud KMS keyring
- Secret Manager secrets
- Cloud Monitoring dashboards and alerts

### 3. Build and push container images

```bash
./scripts/build-images.sh YOUR_PROJECT_ID us-central1 v1.0.0
```

### 4. Deploy all services

```bash
./scripts/deploy.sh YOUR_PROJECT_ID us-central1 v1.0.0
```

### 5. Seed demo data

```bash
./scripts/seed-data.sh YOUR_PROJECT_ID us-central1
```

## Rolling Updates

For code changes, trigger Cloud Build (automatically on push to `main`), or manually:

```bash
# Build and deploy with new tag
./scripts/build-images.sh YOUR_PROJECT_ID us-central1 v1.1.0
./scripts/deploy.sh YOUR_PROJECT_ID us-central1 v1.1.0
```

GKE deployments use `RollingUpdate` with `maxUnavailable: 0` — zero-downtime deploys.
Cloud Run handles traffic splitting automatically.

## Verify Deployment

```bash
# Check all GKE pods
kubectl get pods -n cloudmart

# Check Cloud Run
gcloud run services list --region=us-central1

# Check Cloud Functions
gcloud functions list --region=us-central1

# API health
curl https://api.cloudmart.demo/health
```

## Rollback

### GKE rollback
```bash
kubectl rollout undo deployment/product-service -n cloudmart
kubectl rollout undo deployment/order-service   -n cloudmart
```

### Cloud Run rollback
```bash
# List revisions
gcloud run revisions list --service=cloudmart-api-gateway --region=us-central1

# Route 100% traffic to previous revision
gcloud run services update-traffic cloudmart-api-gateway \
  --to-revisions=REVISION_NAME=100 --region=us-central1
```

## Monitoring

- **Dashboard**: Cloud Console → Monitoring → Dashboards → CloudMart Overview
- **Alerts**: High error rate (>1%), latency (P99 >2s), DB CPU (>80%)
- **Logs**: Cloud Logging → `resource.labels.service_name="cloudmart-api-gateway"`

## Environment Variables Reference

| Variable | Service | Description |
|----------|---------|-------------|
| `GCP_PROJECT` | All | GCP project ID |
| `DB_CONNECTION_NAME` | order-service, user-service | Cloud SQL instance connection string |
| `DB_USER` / `DB_PASS` | order-service, user-service | Database credentials (from Secret Manager) |
| `DB_NAME` | order-service, user-service | Database name (`cloudmart`) |
| `REDIS_HOST` / `REDIS_PORT` | user-service | Memorystore Redis endpoint |
| `PUBSUB_TOPIC` | order-service | Pub/Sub topic name |
| `JWT_SECRET` | api-gateway, user-service | JWT signing key (from Secret Manager) |
| `GCS_BUCKET` | api-gateway | Product images bucket |
| `PRODUCT_SERVICE_URL` | api-gateway | Internal URL for product-service |
| `ORDER_SERVICE_URL` | api-gateway | Internal URL for order-service |
| `USER_SERVICE_URL` | api-gateway | Cloud Run URL for user-service |
