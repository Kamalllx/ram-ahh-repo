variable "project_id" {}
variable "region" {}
variable "app_name" {}
variable "functions_sa_email" {}
variable "images_bucket" {}
variable "assets_bucket" {}
variable "orders_topic" {}
variable "orders_sub" {}
variable "bq_dataset" {}
variable "bq_orders_table" {}
variable "notification_email" {}
variable "vpc_connector_id" {}

# ── Function: Image Processor ────────────────────────────────
# Triggered on GCS object creation in the images bucket
# Resizes images to multiple sizes (thumb, medium, large)

resource "google_storage_bucket_object" "image_processor_src" {
  name   = "functions/image-processor.zip"
  bucket = "${var.app_name}-functions-src-*"  # handled by setup script
  source = "${path.module}/../../../../functions/image-processor/function.zip"
}

resource "google_cloudfunctions2_function" "image_processor" {
  name     = "${var.app_name}-image-processor"
  project  = var.project_id
  location = var.region

  build_config {
    runtime     = "python312"
    entry_point = "process_image"

    source {
      storage_source {
        bucket = "${var.app_name}-functions-src-*"
        object = "functions/image-processor.zip"
      }
    }
  }

  service_config {
    max_instance_count             = 20
    min_instance_count             = 0
    available_memory               = "512M"
    timeout_seconds                = 120
    service_account_email          = var.functions_sa_email
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true

    environment_variables = {
      IMAGES_BUCKET = var.images_bucket
      GCP_PROJECT   = var.project_id
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"

    event_filters {
      attribute = "bucket"
      value     = var.images_bucket
    }
  }
}

# ── Function: Order Notifier ─────────────────────────────────
# Triggered by Pub/Sub order events — sends email/push notifications

resource "google_cloudfunctions2_function" "order_notifier" {
  name     = "${var.app_name}-order-notifier"
  project  = var.project_id
  location = var.region

  build_config {
    runtime     = "python312"
    entry_point = "notify_order"

    source {
      storage_source {
        bucket = "${var.app_name}-functions-src-*"
        object = "functions/order-notifier.zip"
      }
    }
  }

  service_config {
    max_instance_count             = 10
    min_instance_count             = 0
    available_memory               = "256M"
    timeout_seconds                = 60
    service_account_email          = var.functions_sa_email
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true

    vpc_connector                  = var.vpc_connector_id
    vpc_connector_egress_settings  = "PRIVATE_RANGES_ONLY"

    environment_variables = {
      NOTIFICATION_EMAIL = var.notification_email
      GCP_PROJECT        = var.project_id
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = "projects/${var.project_id}/topics/${var.orders_topic}"
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = var.functions_sa_email
  }
}

# ── Function: Analytics Ingester ─────────────────────────────
# Scheduled nightly — syncs order data from Cloud SQL to BigQuery

resource "google_cloudfunctions2_function" "analytics_ingester" {
  name     = "${var.app_name}-analytics-ingester"
  project  = var.project_id
  location = var.region

  build_config {
    runtime     = "python312"
    entry_point = "ingest_analytics"

    source {
      storage_source {
        bucket = "${var.app_name}-functions-src-*"
        object = "functions/analytics-ingester.zip"
      }
    }
  }

  service_config {
    max_instance_count             = 1
    min_instance_count             = 0
    available_memory               = "512M"
    timeout_seconds                = 540  # 9 min
    service_account_email          = var.functions_sa_email
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true

    vpc_connector                  = var.vpc_connector_id
    vpc_connector_egress_settings  = "PRIVATE_RANGES_ONLY"

    environment_variables = {
      GCP_PROJECT     = var.project_id
      BQ_DATASET      = var.bq_dataset
      BQ_TABLE        = var.bq_orders_table
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = "projects/${var.project_id}/topics/${var.app_name}-analytics-trigger"
    retry_policy          = "RETRY_POLICY_DO_NOT_RETRY"
    service_account_email = var.functions_sa_email
  }
}

# Cloud Scheduler to trigger analytics ingester nightly
resource "google_pubsub_topic" "analytics_trigger" {
  name    = "${var.app_name}-analytics-trigger"
  project = var.project_id
}

resource "google_cloud_scheduler_job" "analytics_ingester" {
  name      = "${var.app_name}-analytics-nightly"
  project   = var.project_id
  region    = var.region
  schedule  = "0 2 * * *"  # 2 AM daily
  time_zone = "America/New_York"

  pubsub_target {
    topic_name = google_pubsub_topic.analytics_trigger.id
    data       = base64encode(jsonencode({ trigger = "scheduled" }))
  }
}

output "image_processor_url"   { value = google_cloudfunctions2_function.image_processor.service_config[0].uri }
output "order_notifier_url"    { value = google_cloudfunctions2_function.order_notifier.service_config[0].uri }
output "analytics_ingester_url"{ value = google_cloudfunctions2_function.analytics_ingester.service_config[0].uri }
