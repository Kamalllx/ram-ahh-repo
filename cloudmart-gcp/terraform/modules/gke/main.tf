variable "project_id" {}
variable "region" {}
variable "app_name" {}
variable "vpc_id" {}
variable "gke_subnet_id" {}
variable "gke_pods_range" {}
variable "gke_services_range" {}
variable "node_count" {}
variable "min_nodes" {}
variable "max_nodes" {}
variable "machine_type" {}
variable "node_sa_email" {}

resource "google_container_cluster" "primary" {
  name     = "${var.app_name}-cluster"
  project  = var.project_id
  location = var.region

  # Remove default node pool — we manage it separately
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.vpc_id
  subnetwork = var.gke_subnet_id

  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = var.gke_pods_range
    services_secondary_range_name = var.gke_services_range
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All (restrict in production)"
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    gcp_filestore_csi_driver_config {
      enabled = false
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "APISERVER", "CONTROLLER_MANAGER", "SCHEDULER"]
    managed_prometheus {
      enabled = true
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T02:00:00Z"
      end_time   = "2024-01-01T06:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }
  }

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.app_name}-node-pool"
  project    = var.project_id
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = var.node_count

  autoscaling {
    min_node_count = var.min_nodes
    max_node_count = var.max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.machine_type
    service_account = var.node_sa_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = {
      app  = var.app_name
      role = "workload"
    }

    tags = ["gke-node", var.app_name]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    disk_size_gb = 50
    disk_type    = "pd-balanced"
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

output "cluster_name"           { value = google_container_cluster.primary.name }
output "cluster_endpoint"       { value = google_container_cluster.primary.endpoint }
output "cluster_ca_certificate" { value = google_container_cluster.primary.master_auth[0].cluster_ca_certificate }
