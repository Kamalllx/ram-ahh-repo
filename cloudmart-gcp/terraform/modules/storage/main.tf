variable "project_id" {}
variable "region" {}
variable "app_name" {}
variable "suffix" {}
variable "kms_key_id" {}

# Product images bucket
resource "google_storage_bucket" "images" {
  name          = "${var.app_name}-images-${var.suffix}"
  project       = var.project_id
  location      = var.region
  storage_class = "STANDARD"
  force_destroy = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition {
      age = 90
    }
  }

  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD"]
    response_header = ["Content-Type", "Cache-Control"]
    max_age_seconds = 3600
  }

  encryption {
    default_kms_key_name = var.kms_key_id
  }

  uniform_bucket_level_access = true

  labels = {
    app  = var.app_name
    type = "images"
  }
}

# Make images publicly readable
resource "google_storage_bucket_iam_member" "images_public" {
  bucket = google_storage_bucket.images.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Static assets / frontend bucket
resource "google_storage_bucket" "assets" {
  name          = "${var.app_name}-assets-${var.suffix}"
  project       = var.project_id
  location      = var.region
  storage_class = "STANDARD"
  force_destroy = false

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }

  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD"]
    response_header = ["Content-Type"]
    max_age_seconds = 3600
  }

  uniform_bucket_level_access = true

  labels = {
    app  = var.app_name
    type = "assets"
  }
}

resource "google_storage_bucket_iam_member" "assets_public" {
  bucket = google_storage_bucket.assets.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Cloud Functions source code bucket
resource "google_storage_bucket" "functions_source" {
  name          = "${var.app_name}-functions-src-${var.suffix}"
  project       = var.project_id
  location      = var.region
  storage_class = "STANDARD"
  force_destroy = true

  uniform_bucket_level_access = true

  labels = {
    app  = var.app_name
    type = "functions-source"
  }
}

output "images_bucket_name"    { value = google_storage_bucket.images.name }
output "assets_bucket_name"    { value = google_storage_bucket.assets.name }
output "functions_src_bucket"  { value = google_storage_bucket.functions_source.name }
