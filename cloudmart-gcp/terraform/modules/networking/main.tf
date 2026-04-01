variable "project_id" {}
variable "region" {}
variable "app_name" {}
variable "vpc_cidr" {}
variable "gke_subnet_cidr" {}
variable "gke_pods_cidr" {}
variable "gke_services_cidr" {}
variable "private_subnet_cidr" {}

# ── VPC ──────────────────────────────────────────────────────
resource "google_compute_network" "vpc" {
  name                    = "${var.app_name}-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

# GKE subnet with secondary ranges for pods and services
resource "google_compute_subnetwork" "gke" {
  name          = "${var.app_name}-gke-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.gke_subnet_cidr

  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "${var.app_name}-pods"
    ip_cidr_range = var.gke_pods_cidr
  }

  secondary_ip_range {
    range_name    = "${var.app_name}-services"
    ip_cidr_range = var.gke_services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Private subnet for databases and Redis
resource "google_compute_subnetwork" "private" {
  name                     = "${var.app_name}-private-subnet"
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.private_subnet_cidr
  private_ip_google_access = true
}

# ── Cloud NAT + Router (outbound internet for private nodes) ─
resource "google_compute_router" "router" {
  name    = "${var.app_name}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.app_name}-nat"
  project                            = var.project_id
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ── Firewall Rules ───────────────────────────────────────────
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.app_name}-allow-internal"
  project = var.project_id
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.vpc_cidr, var.gke_pods_cidr]
}

resource "google_compute_firewall" "allow_health_check" {
  name    = "${var.app_name}-allow-health-check"
  project = var.project_id
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["8080", "80", "443"]
  }

  # GCP health check source ranges
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["gke-node", "cloudrun"]
}

resource "google_compute_firewall" "allow_iap" {
  name    = "${var.app_name}-allow-iap"
  project = var.project_id
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP tunnel source range
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["inventory-worker", "private"]
}

resource "google_compute_firewall" "deny_all_ingress" {
  name     = "${var.app_name}-deny-all-ingress"
  project  = var.project_id
  network  = google_compute_network.vpc.id
  priority = 65534

  deny {
    protocol = "all"
  }

  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
}

# ── Private Services Access (for Cloud SQL, Memorystore) ─────
resource "google_compute_global_address" "private_ip_range" {
  name          = "${var.app_name}-private-ip-range"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

# ── Serverless VPC Access Connector (Cloud Run → VPC) ───────
resource "google_vpc_access_connector" "connector" {
  name          = "${var.app_name}-connector"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.8.0.0/28"
  min_instances = 2
  max_instances = 10
}

# ── Outputs ──────────────────────────────────────────────────
output "vpc_id"                   { value = google_compute_network.vpc.id }
output "vpc_name"                 { value = google_compute_network.vpc.name }
output "gke_subnet_id"            { value = google_compute_subnetwork.gke.id }
output "private_subnet_id"        { value = google_compute_subnetwork.private.id }
output "gke_pods_range_name"      { value = "${var.app_name}-pods" }
output "gke_services_range_name"  { value = "${var.app_name}-services" }
output "vpc_connector_id"         { value = google_vpc_access_connector.connector.id }
