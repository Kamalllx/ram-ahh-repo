variable "project_id" {}
variable "region" {}
variable "app_name" {}
variable "image_tag" {}
variable "registry_url" {}
variable "vpc_connector_id" {}
variable "db_connection" {}
variable "db_name" {}
variable "redis_host" {}
variable "redis_port" {}
variable "product_svc_url" {}
variable "order_svc_url" {}
variable "user_svc_sa_email" {}
variable "api_gw_sa_email" {}
variable "gcs_bucket_name" {}
variable "pubsub_topic" {}

locals {
  api_gw_image   = "${var.registry_url}/api-gateway:${var.image_tag}"
  user_svc_image = "${var.registry_url}/user-service:${var.image_tag}"
}

# ── JWT Secret ───────────────────────────────────────────────
resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "google_secret_manager_secret" "jwt_secret" {
  secret_id = "${var.app_name}-jwt-secret"
  project   = var.project_id
  replication { auto {} }
}

resource "google_secret_manager_secret_version" "jwt_secret" {
  secret      = google_secret_manager_secret.jwt_secret.id
  secret_data = random_password.jwt_secret.result
}

# ── User Service (Cloud Run) ─────────────────────────────────
resource "google_cloud_run_v2_service" "user_service" {
  name     = "${var.app_name}-user-service"
  location = var.region
  project  = var.project_id

  ingress = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  template {
    service_account = var.user_svc_sa_email

    scaling {
      min_instance_count = 1
      max_instance_count = 10
    }

    vpc_access {
      connector = var.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = local.user_svc_image

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "PORT"
        value = "8080"
      }
      env {
        name  = "DB_NAME"
        value = var.db_name
      }
      env {
        name  = "REDIS_HOST"
        value = var.redis_host
      }
      env {
        name  = "REDIS_PORT"
        value = tostring(var.redis_port)
      }
      env {
        name = "JWT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.jwt_secret.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "DB_CONNECTION_NAME"
        value = var.db_connection
      }

      startup_probe {
        http_get { path = "/health" }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 10
      }

      liveness_probe {
        http_get { path = "/health" }
        period_seconds    = 30
        failure_threshold = 3
      }
    }

    # Cloud SQL sidecar
    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [var.db_connection]
      }
    }
  }
}

# ── API Gateway (Cloud Run) ──────────────────────────────────
resource "google_cloud_run_v2_service" "api_gateway" {
  name     = "${var.app_name}-api-gateway"
  location = var.region
  project  = var.project_id

  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = var.api_gw_sa_email

    scaling {
      min_instance_count = 1
      max_instance_count = 20
    }

    vpc_access {
      connector = var.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = local.api_gw_image

      resources {
        limits = {
          cpu    = "2"
          memory = "1Gi"
        }
        cpu_idle          = false
        startup_cpu_boost = true
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "PORT"
        value = "8080"
      }
      env {
        name  = "USER_SERVICE_URL"
        value = google_cloud_run_v2_service.user_service.uri
      }
      env {
        name  = "PRODUCT_SERVICE_URL"
        value = var.product_svc_url
      }
      env {
        name  = "ORDER_SERVICE_URL"
        value = var.order_svc_url
      }
      env {
        name  = "GCS_BUCKET"
        value = var.gcs_bucket_name
      }
      env {
        name  = "PUBSUB_TOPIC"
        value = var.pubsub_topic
      }
      env {
        name = "JWT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.jwt_secret.secret_id
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get { path = "/health" }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 10
      }
    }
  }
}

# Allow unauthenticated access to API Gateway
resource "google_cloud_run_v2_service_iam_member" "api_gateway_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api_gateway.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ── Static IP for Load Balancer ──────────────────────────────
resource "google_compute_global_address" "api_gw_ip" {
  name    = "${var.app_name}-api-gw-ip"
  project = var.project_id
}

# ── Cloud Armor Security Policy ──────────────────────────────
resource "google_compute_security_policy" "api_gateway" {
  name    = "${var.app_name}-api-security-policy"
  project = var.project_id

  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-stable')"
      }
    }
    description = "Block XSS attacks"
  }

  rule {
    action   = "deny(403)"
    priority = 1001
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-stable')"
      }
    }
    description = "Block SQL injection"
  }

  rule {
    action   = "rate_based_ban"
    priority = 2000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
      ban_duration_sec = 300
    }
    description = "Rate limiting — 100 req/min per IP"
  }

  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow"
  }
}

# ── Outputs ──────────────────────────────────────────────────
output "api_gateway_url"  { value = google_cloud_run_v2_service.api_gateway.uri }
output "user_service_url" { value = google_cloud_run_v2_service.user_service.uri }
output "api_gateway_ip"   { value = google_compute_global_address.api_gw_ip.address }
