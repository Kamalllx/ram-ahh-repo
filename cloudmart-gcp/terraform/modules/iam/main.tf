variable "project_id" {}
variable "app_name" {}

# ── Service Accounts ─────────────────────────────────────────

resource "google_service_account" "gke_node" {
  account_id   = "${var.app_name}-gke-node"
  display_name = "CloudMart GKE Node SA"
  project      = var.project_id
}

resource "google_service_account" "api_gateway" {
  account_id   = "${var.app_name}-api-gateway"
  display_name = "CloudMart API Gateway SA"
  project      = var.project_id
}

resource "google_service_account" "user_service" {
  account_id   = "${var.app_name}-user-service"
  display_name = "CloudMart User Service SA"
  project      = var.project_id
}

resource "google_service_account" "functions" {
  account_id   = "${var.app_name}-functions"
  display_name = "CloudMart Cloud Functions SA"
  project      = var.project_id
}

resource "google_service_account" "inventory_worker" {
  account_id   = "${var.app_name}-inventory-worker"
  display_name = "CloudMart Inventory Worker SA"
  project      = var.project_id
}

resource "google_service_account" "cloud_build" {
  account_id   = "${var.app_name}-cloud-build"
  display_name = "CloudMart Cloud Build SA"
  project      = var.project_id
}

# ── IAM Bindings ─────────────────────────────────────────────

# GKE node SA — minimal permissions
resource "google_project_iam_member" "gke_node_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

resource "google_project_iam_member" "gke_node_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

resource "google_project_iam_member" "gke_node_artifact_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

resource "google_project_iam_member" "gke_node_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

resource "google_project_iam_member" "gke_node_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

resource "google_project_iam_member" "gke_node_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

resource "google_project_iam_member" "gke_node_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

# API Gateway SA
resource "google_project_iam_member" "api_gw_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.api_gateway.email}"
}

resource "google_project_iam_member" "api_gw_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.api_gateway.email}"
}

resource "google_project_iam_member" "api_gw_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.api_gateway.email}"
}

# User Service SA
resource "google_project_iam_member" "user_svc_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.user_service.email}"
}

resource "google_project_iam_member" "user_svc_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.user_service.email}"
}

resource "google_project_iam_member" "user_svc_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.user_service.email}"
}

# Functions SA
resource "google_project_iam_member" "functions_gcs" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.functions.email}"
}

resource "google_project_iam_member" "functions_pubsub_sub" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.functions.email}"
}

resource "google_project_iam_member" "functions_bq" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.functions.email}"
}

resource "google_project_iam_member" "functions_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.functions.email}"
}

resource "google_project_iam_member" "functions_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.functions.email}"
}

# Inventory Worker SA
resource "google_project_iam_member" "worker_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.inventory_worker.email}"
}

resource "google_project_iam_member" "worker_pubsub_pub" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.inventory_worker.email}"
}

resource "google_project_iam_member" "worker_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.inventory_worker.email}"
}

resource "google_project_iam_member" "worker_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.inventory_worker.email}"
}

resource "google_project_iam_member" "worker_gcs" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.inventory_worker.email}"
}

# Cloud Build SA
resource "google_project_iam_member" "build_editor" {
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

# ── Outputs ──────────────────────────────────────────────────
output "gke_node_sa_email"    { value = google_service_account.gke_node.email }
output "api_gateway_sa_email" { value = google_service_account.api_gateway.email }
output "user_service_sa_email"{ value = google_service_account.user_service.email }
output "functions_sa_email"   { value = google_service_account.functions.email }
output "worker_sa_email"      { value = google_service_account.inventory_worker.email }
output "cloud_build_sa_email" { value = google_service_account.cloud_build.email }
