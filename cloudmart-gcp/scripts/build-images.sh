#!/usr/bin/env bash
# Build and push all Docker images to Artifact Registry
set -euo pipefail

PROJECT_ID=${1:-$(gcloud config get-value project)}
REGION=${2:-us-central1}
TAG=${3:-latest}
REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/cloudmart-images"

echo "Building images → ${REGISTRY} (tag: ${TAG})"

SERVICES=(api-gateway product-service order-service user-service)
for svc in "${SERVICES[@]}"; do
  echo "→ Building $svc..."
  docker build \
    --platform linux/amd64 \
    --cache-from "${REGISTRY}/${svc}:latest" \
    -t "${REGISTRY}/${svc}:${TAG}" \
    -t "${REGISTRY}/${svc}:latest" \
    "services/${svc}"
  docker push "${REGISTRY}/${svc}:${TAG}"
  docker push "${REGISTRY}/${svc}:latest"
  echo "✓ ${svc} pushed"
done

# Build Go inventory worker
echo "→ Building inventory-worker..."
docker build \
  --platform linux/amd64 \
  -t "${REGISTRY}/inventory-worker:${TAG}" \
  workers/inventory-worker
docker push "${REGISTRY}/inventory-worker:${TAG}"
echo "✓ inventory-worker pushed"

echo ""
echo "All images pushed to ${REGISTRY}"
