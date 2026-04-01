#!/usr/bin/env bash
# CloudMart GCP Setup Script
# Run once before the first deployment to bootstrap the project
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Validate prerequisites ────────────────────────────────────
command -v gcloud   >/dev/null || error "gcloud CLI not found"
command -v terraform>/dev/null || error "terraform not found"
command -v kubectl  >/dev/null || error "kubectl not found"
command -v docker   >/dev/null || error "docker not found"

PROJECT_ID=${1:-$(gcloud config get-value project)}
REGION=${2:-us-central1}
[[ -z "$PROJECT_ID" ]] && error "Usage: ./setup.sh <PROJECT_ID> [REGION]"

info "Setting up CloudMart on project: $PROJECT_ID (region: $REGION)"

# ── Authenticate ──────────────────────────────────────────────
gcloud config set project "$PROJECT_ID"

# ── Create Terraform state bucket ────────────────────────────
STATE_BUCKET="cloudmart-terraform-state"
if ! gcloud storage buckets describe "gs://$STATE_BUCKET" &>/dev/null; then
  info "Creating Terraform state bucket..."
  gcloud storage buckets create "gs://$STATE_BUCKET" \
    --location="$REGION" \
    --uniform-bucket-level-access
  gcloud storage buckets update "gs://$STATE_BUCKET" --versioning
else
  info "Terraform state bucket already exists"
fi

# ── Initialize and apply Terraform ───────────────────────────
info "Initializing Terraform..."
cd "$(dirname "$0")/../terraform"
terraform init -backend-config="bucket=$STATE_BUCKET"

info "Planning infrastructure..."
terraform plan \
  -var="project_id=$PROJECT_ID" \
  -var="region=$REGION" \
  -out=tfplan

read -rp "Apply Terraform plan? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { warn "Aborted."; exit 0; }

info "Applying infrastructure..."
terraform apply tfplan

# ── Configure kubectl ─────────────────────────────────────────
CLUSTER_NAME=$(terraform output -raw gke_cluster_name)
info "Configuring kubectl for cluster: $CLUSTER_NAME"
gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --region "$REGION" --project "$PROJECT_ID"

# ── Configure Docker for Artifact Registry ────────────────────
REGISTRY=$(terraform output -raw artifact_registry_url)
info "Configuring Docker for Artifact Registry: $REGISTRY"
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# ── Create Kubernetes secrets ─────────────────────────────────
info "Creating Kubernetes secrets from Secret Manager..."
DB_PASS=$(gcloud secrets versions access latest --secret="cloudmart-db-password")
kubectl create namespace cloudmart --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic cloudmart-secrets \
  --from-literal=db-password="$DB_PASS" \
  --namespace=cloudmart \
  --dry-run=client -o yaml | kubectl apply -f -

cd - >/dev/null

info "Setup complete!"
info ""
info "Next steps:"
info "  1. Build and push images: ./scripts/build-images.sh $PROJECT_ID $REGION"
info "  2. Deploy services:       ./scripts/deploy.sh $PROJECT_ID $REGION"
info "  3. Seed demo data:        ./scripts/seed-data.sh $PROJECT_ID"
