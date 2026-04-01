variable "project_id" {}
variable "region" {}
variable "app_name" {}
variable "db_tier" {}
variable "db_name" {}
variable "db_user" {}
variable "vpc_id" {}
variable "private_subnet_id" {}
variable "kms_key_id" {}

resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.app_name}-db-password"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

resource "google_sql_database_instance" "primary" {
  name             = "${var.app_name}-postgres"
  project          = var.project_id
  region           = var.region
  database_version = "POSTGRES_15"

  encryption_key_name = var.kms_key_id

  settings {
    tier              = var.db_tier
    availability_type = "REGIONAL"
    disk_autoresize   = true
    disk_size         = 20
    disk_type         = "PD_SSD"

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.vpc_id
      require_ssl     = true
    }

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_disconnections"
      value = "on"
    }

    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }

    maintenance_window {
      day          = 7  # Sunday
      hour         = 4
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = false
    }
  }

  deletion_protection = true
}

# Read replica for analytics queries
resource "google_sql_database_instance" "replica" {
  name                 = "${var.app_name}-postgres-replica"
  project              = var.project_id
  region               = var.region
  database_version     = "POSTGRES_15"
  master_instance_name = google_sql_database_instance.primary.name

  settings {
    tier              = var.db_tier
    availability_type = "ZONAL"

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.vpc_id
    }
  }

  deletion_protection = false
}

resource "google_sql_database" "cloudmart" {
  name     = var.db_name
  instance = google_sql_database_instance.primary.name
  project  = var.project_id
}

resource "google_sql_user" "admin" {
  name     = var.db_user
  instance = google_sql_database_instance.primary.name
  password = random_password.db_password.result
  project  = var.project_id
}

output "connection_name"   { value = google_sql_database_instance.primary.connection_name }
output "private_ip"        { value = google_sql_database_instance.primary.private_ip_address }
output "db_password_secret"{ value = google_secret_manager_secret.db_password.secret_id }
