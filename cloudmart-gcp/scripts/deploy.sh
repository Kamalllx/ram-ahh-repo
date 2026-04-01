#!/usr/bin/env bash
# Deploy all CloudMart services
set -euo pipefail

PROJECT_ID=${1:-$(gcloud config get-value project)}
REGION=${2:-us-central1}
TAG=${3:-latest}
CLUSTER="cloudmart-cluster"
REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/cloudmart-images"

echo "Deploying CloudMart to project: $PROJECT_ID"

# ── GKE Workloads ─────────────────────────────────────────────
echo "→ Configuring kubectl..."
gcloud container clusters get-credentials "$CLUSTER" \
  --region "$REGION" --project "$PROJECT_ID"

echo "→ Deploying Kubernetes resources..."
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/configmaps/

# Substitute image tags in manifests
TMP=$(mktemp -d)
for f in kubernetes/deployments/*.yaml; do
  sed "s|REGISTRY_URL|${REGISTRY}|g; s|IMAGE_TAG|${TAG}|g; s|YOUR_PROJECT_ID|${PROJECT_ID}|g" \
    "$f" > "$TMP/$(basename "$f")"
done
kubectl apply -f "$TMP/"
kubectl apply -f kubernetes/services/
kubectl apply -f kubernetes/hpa/
rm -rf "$TMP"

echo "→ Waiting for rollouts..."
kubectl rollout status deployment/product-service -n cloudmart --timeout=300s
kubectl rollout status deployment/order-service   -n cloudmart --timeout=300s

# ── Cloud Run ─────────────────────────────────────────────────
echo "→ Deploying Cloud Run services..."

gcloud run services update cloudmart-api-gateway \
  --image="${REGISTRY}/api-gateway:${TAG}" \
  --region="$REGION" --project="$PROJECT_ID"

gcloud run services update cloudmart-user-service \
  --image="${REGISTRY}/user-service:${TAG}" \
  --region="$REGION" --project="$PROJECT_ID"

# ── Cloud Functions ───────────────────────────────────────────
echo "→ Uploading Cloud Functions..."
FUNCTIONS_BUCKET=$(gcloud storage buckets list \
  --project="$PROJECT_ID" \
  --format="value(name)" | grep functions-src | head -1)

for fn in image-processor order-notifier analytics-ingester; do
  (
    cd "functions/$fn"
    zip -r "/tmp/${fn}.zip" . -x "*.pyc" -x "__pycache__/*"
    gcloud storage cp "/tmp/${fn}.zip" "gs://${FUNCTIONS_BUCKET}/functions/${fn}.zip"
    echo "  ✓ $fn uploaded"
  )
done

# ── Inventory Worker binary ───────────────────────────────────
echo "→ Building and uploading inventory worker binary..."
ASSETS_BUCKET=$(gcloud storage buckets list \
  --project="$PROJECT_ID" \
  --format="value(name)" | grep assets | head -1)

(
  cd workers/inventory-worker
  docker build --platform linux/amd64 -t cloudmart-worker-build .
  docker create --name extract cloudmart-worker-build
  docker cp extract:/inventory-worker /tmp/inventory-worker
  docker rm extract
  gcloud storage cp /tmp/inventory-worker "gs://${ASSETS_BUCKET}/binaries/inventory-worker"
)

# Restart the worker VM to pick up new binary
WORKER_VM="cloudmart-inventory-worker"
ZONE=$(gcloud compute instances list \
  --filter="name=$WORKER_VM" \
  --format="value(zone)" | head -1)
if [[ -n "$ZONE" ]]; then
  echo "→ Restarting inventory worker VM..."
  gcloud compute instances reset "$WORKER_VM" --zone="$ZONE" --project="$PROJECT_ID"
fi

# ── Smoke test ────────────────────────────────────────────────
echo "→ Running smoke test..."
API_URL=$(gcloud run services describe cloudmart-api-gateway \
  --region="$REGION" --project="$PROJECT_ID" \
  --format="value(status.url)")

sleep 5
HTTP_STATUS=$(curl -so /dev/null -w "%{http_code}" "${API_URL}/health")
if [[ "$HTTP_STATUS" == "200" ]]; then
  echo "✓ API Gateway health check passed ($API_URL)"
else
  echo "✗ API Gateway health check failed (HTTP $HTTP_STATUS)"
  exit 1
fi

echo ""
echo "Deployment complete!"
echo "App URL: https://cloudmart.demo"
echo "API:     $API_URL"
