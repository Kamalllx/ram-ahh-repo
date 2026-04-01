# ============================================================
# CloudMart — GCP Infrastructure Root Module
# ============================================================

# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "run.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "sqladmin.googleapis.com",
    "firestore.googleapis.com",
    "storage.googleapis.com",
    "pubsub.googleapis.com",
    "redis.googleapis.com",
    "bigquery.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudkms.googleapis.com",
    "dns.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudtrace.googleapis.com",
    "iamcredentials.googleapis.com",
    "servicenetworking.googleapis.com",
    "vpcaccess.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudarmor.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# ── Networking ───────────────────────────────────────────────
module "networking" {
  source = "./modules/networking"

  project_id          = var.project_id
  region              = var.region
  app_name            = var.app_name
  vpc_cidr            = var.vpc_cidr
  gke_subnet_cidr     = var.gke_subnet_cidr
  gke_pods_cidr       = var.gke_pods_cidr
  gke_services_cidr   = var.gke_services_cidr
  private_subnet_cidr = var.private_subnet_cidr

  depends_on = [google_project_service.apis]
}

# ── IAM ──────────────────────────────────────────────────────
module "iam" {
  source = "./modules/iam"

  project_id = var.project_id
  app_name   = var.app_name

  depends_on = [google_project_service.apis]
}

# ── Artifact Registry ────────────────────────────────────────
resource "google_artifact_registry_repository" "cloudmart" {
  project       = var.project_id
  location      = var.artifact_registry_location
  repository_id = "${var.app_name}-images"
  format        = "DOCKER"
  description   = "CloudMart container images"

  depends_on = [google_project_service.apis]
}

# ── KMS ─────────────────────────────────────────────────────
resource "google_kms_key_ring" "cloudmart" {
  name     = "${var.app_name}-keyring"
  location = var.region
  project  = var.project_id

  depends_on = [google_project_service.apis]
}

resource "google_kms_crypto_key" "db_key" {
  name            = "db-encryption-key"
  key_ring        = google_kms_key_ring.cloudmart.id
  rotation_period = "7776000s" # 90 days
}

# ── Storage ──────────────────────────────────────────────────
module "storage" {
  source = "./modules/storage"

  project_id  = var.project_id
  region      = var.region
  app_name    = var.app_name
  suffix      = random_id.suffix.hex
  kms_key_id  = google_kms_crypto_key.db_key.id

  depends_on = [google_project_service.apis]
}

# ── Database (Cloud SQL) ─────────────────────────────────────
module "database" {
  source = "./modules/database"

  project_id        = var.project_id
  region            = var.region
  app_name          = var.app_name
  db_tier           = var.db_tier
  db_name           = var.db_name
  db_user           = var.db_user
  vpc_id            = module.networking.vpc_id
  private_subnet_id = module.networking.private_subnet_id
  kms_key_id        = google_kms_crypto_key.db_key.id

  depends_on = [module.networking, google_project_service.apis]
}

# ── Pub/Sub ──────────────────────────────────────────────────
module "pubsub" {
  source = "./modules/pubsub"

  project_id          = var.project_id
  app_name            = var.app_name
  order_notifier_sa   = module.iam.functions_sa_email

  depends_on = [module.iam, google_project_service.apis]
}

# ── GKE Cluster ──────────────────────────────────────────────
module "gke" {
  source = "./modules/gke"

  project_id       = var.project_id
  region           = var.region
  app_name         = var.app_name
  vpc_id           = module.networking.vpc_id
  gke_subnet_id    = module.networking.gke_subnet_id
  gke_pods_range   = module.networking.gke_pods_range_name
  gke_services_range = module.networking.gke_services_range_name
  node_count       = var.gke_node_count
  min_nodes        = var.gke_min_nodes
  max_nodes        = var.gke_max_nodes
  machine_type     = var.gke_machine_type
  node_sa_email    = module.iam.gke_node_sa_email

  depends_on = [module.networking, module.iam, google_project_service.apis]
}

# ── Memorystore (Redis) ──────────────────────────────────────
resource "google_redis_instance" "cloudmart" {
  name           = "${var.app_name}-redis"
  tier           = "STANDARD_HA"
  memory_size_gb = 2
  region         = var.region
  project        = var.project_id

  authorized_network = module.networking.vpc_id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"
  redis_version      = "REDIS_7_0"

  redis_configs = {
    maxmemory-policy = "allkeys-lru"
  }

  depends_on = [module.networking, google_project_service.apis]
}

# ── BigQuery ─────────────────────────────────────────────────
resource "google_bigquery_dataset" "analytics" {
  dataset_id  = "${var.app_name}_analytics"
  project     = var.project_id
  location    = "US"
  description = "CloudMart analytics data"

  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }

  access {
    role          = "READER"
    user_by_email = module.iam.functions_sa_email
  }

  depends_on = [google_project_service.apis]
}

resource "google_bigquery_table" "orders" {
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  table_id   = "orders"
  project    = var.project_id

  time_partitioning {
    type  = "DAY"
    field = "created_at"
  }

  schema = jsonencode([
    { name = "order_id",    type = "STRING",    mode = "REQUIRED" },
    { name = "user_id",     type = "STRING",    mode = "REQUIRED" },
    { name = "total_amount",type = "FLOAT64",   mode = "REQUIRED" },
    { name = "status",      type = "STRING",    mode = "REQUIRED" },
    { name = "item_count",  type = "INTEGER",   mode = "REQUIRED" },
    { name = "created_at",  type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "region",      type = "STRING",    mode = "NULLABLE" },
  ])
}

resource "google_bigquery_table" "pageviews" {
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  table_id   = "pageviews"
  project    = var.project_id

  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }

  schema = jsonencode([
    { name = "session_id",  type = "STRING",    mode = "REQUIRED" },
    { name = "user_id",     type = "STRING",    mode = "NULLABLE" },
    { name = "page",        type = "STRING",    mode = "REQUIRED" },
    { name = "product_id",  type = "STRING",    mode = "NULLABLE" },
    { name = "duration_ms", type = "INTEGER",   mode = "NULLABLE" },
    { name = "timestamp",   type = "TIMESTAMP", mode = "REQUIRED" },
  ])
}

# ── Cloud Run Services ───────────────────────────────────────
module "cloud_run" {
  source = "./modules/cloud-run"

  project_id        = var.project_id
  region            = var.region
  app_name          = var.app_name
  image_tag         = var.image_tag
  registry_url      = "${var.artifact_registry_location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.cloudmart.repository_id}"
  vpc_connector_id  = module.networking.vpc_connector_id
  db_connection     = module.database.connection_name
  db_name           = var.db_name
  redis_host        = google_redis_instance.cloudmart.host
  redis_port        = google_redis_instance.cloudmart.port
  product_svc_url   = "http://product-service.cloudmart.svc.cluster.local"
  order_svc_url     = "http://order-service.cloudmart.svc.cluster.local"
  user_svc_sa_email = module.iam.user_service_sa_email
  api_gw_sa_email   = module.iam.api_gateway_sa_email
  gcs_bucket_name   = module.storage.assets_bucket_name
  pubsub_topic      = module.pubsub.orders_topic_name

  depends_on = [module.networking, module.database, module.iam, google_project_service.apis]
}

# ── Cloud Functions ──────────────────────────────────────────
module "functions" {
  source = "./modules/functions"

  project_id        = var.project_id
  region            = var.region
  app_name          = var.app_name
  functions_sa_email = module.iam.functions_sa_email
  images_bucket     = module.storage.images_bucket_name
  assets_bucket     = module.storage.assets_bucket_name
  orders_topic      = module.pubsub.orders_topic_name
  orders_sub        = module.pubsub.orders_notifier_sub_id
  bq_dataset        = google_bigquery_dataset.analytics.dataset_id
  bq_orders_table   = google_bigquery_table.orders.table_id
  notification_email = var.notification_email
  vpc_connector_id  = module.networking.vpc_connector_id

  depends_on = [module.storage, module.pubsub, module.iam, google_bigquery_dataset.analytics]
}

# ── Compute Engine (Inventory Worker) ───────────────────────
module "monitoring" {
  source = "./modules/monitoring"

  project_id = var.project_id
  app_name   = var.app_name
  region     = var.region

  depends_on = [google_project_service.apis]
}

# ── Firestore ────────────────────────────────────────────────
resource "google_firestore_database" "cloudmart" {
  project     = var.project_id
  name        = "(default)"
  location_id = "nam5"
  type        = "FIRESTORE_NATIVE"

  depends_on = [google_project_service.apis]
}

# ── Compute Engine Inventory Worker ─────────────────────────
resource "google_compute_instance" "inventory_worker" {
  name         = "${var.app_name}-inventory-worker"
  machine_type = var.worker_machine_type
  zone         = var.zone
  project      = var.project_id

  tags = ["inventory-worker", "private"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
    }
  }

  network_interface {
    network    = module.networking.vpc_id
    subnetwork = module.networking.private_subnet_id
    # No external IP — accessed via IAP
  }

  service_account {
    email  = module.iam.worker_sa_email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = <<-EOF
      #!/bin/bash
      set -e
      apt-get update -y
      apt-get install -y wget curl

      # Download inventory worker binary from GCS
      gsutil cp gs://${module.storage.assets_bucket_name}/binaries/inventory-worker /usr/local/bin/inventory-worker
      chmod +x /usr/local/bin/inventory-worker

      # Create systemd service
      cat > /etc/systemd/system/inventory-worker.service <<'UNIT'
      [Unit]
      Description=CloudMart Inventory Worker
      After=network-online.target

      [Service]
      ExecStart=/usr/local/bin/inventory-worker
      Restart=always
      RestartSec=10
      Environment=GCP_PROJECT=${var.project_id}
      Environment=PUBSUB_TOPIC=${module.pubsub.orders_topic_name}
      Environment=DB_CONNECTION=${module.database.connection_name}

      [Install]
      WantedBy=multi-user.target
      UNIT

      systemctl daemon-reload
      systemctl enable inventory-worker
      systemctl start inventory-worker
    EOF
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  depends_on = [module.networking, module.iam, module.storage]
}

# ── DNS ──────────────────────────────────────────────────────
resource "google_dns_managed_zone" "cloudmart" {
  name        = "${var.app_name}-zone"
  dns_name    = "${var.domain_name}."
  project     = var.project_id
  description = "CloudMart DNS zone"

  dnssec_config {
    state = "on"
  }

  depends_on = [google_project_service.apis]
}

resource "google_dns_record_set" "app" {
  name         = "${var.domain_name}."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.cloudmart.name
  project      = var.project_id
  rrdatas      = [module.cloud_run.api_gateway_ip]
}
