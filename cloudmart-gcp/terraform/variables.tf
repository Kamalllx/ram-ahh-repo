variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "Primary GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Primary GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "app_name" {
  description = "Application name prefix for all resources"
  type        = string
  default     = "cloudmart"
}

# Networking
variable "vpc_cidr" {
  description = "Primary VPC CIDR range"
  type        = string
  default     = "10.0.0.0/16"
}

variable "gke_subnet_cidr" {
  description = "Subnet CIDR for GKE nodes"
  type        = string
  default     = "10.0.1.0/24"
}

variable "gke_pods_cidr" {
  description = "Secondary CIDR range for GKE Pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "gke_services_cidr" {
  description = "Secondary CIDR range for GKE Services"
  type        = string
  default     = "10.2.0.0/20"
}

variable "private_subnet_cidr" {
  description = "Subnet CIDR for private resources (Cloud SQL, Memorystore)"
  type        = string
  default     = "10.0.2.0/24"
}

# GKE
variable "gke_node_count" {
  description = "Initial node count per zone"
  type        = number
  default     = 2
}

variable "gke_min_nodes" {
  description = "Minimum nodes for autoscaling"
  type        = number
  default     = 1
}

variable "gke_max_nodes" {
  description = "Maximum nodes for autoscaling"
  type        = number
  default     = 5
}

variable "gke_machine_type" {
  description = "GKE node machine type"
  type        = string
  default     = "e2-standard-4"
}

# Database
variable "db_tier" {
  description = "Cloud SQL instance tier"
  type        = string
  default     = "db-g1-small"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "cloudmart"
}

variable "db_user" {
  description = "PostgreSQL admin user"
  type        = string
  default     = "cloudmart_admin"
}

# Compute Engine (Inventory Worker)
variable "worker_machine_type" {
  description = "Machine type for inventory worker"
  type        = string
  default     = "e2-medium"
}

# DNS
variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "cloudmart.demo"
}

# Notification
variable "notification_email" {
  description = "Email address for order notifications"
  type        = string
  default     = "orders@cloudmart.demo"
}

# Container images
variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "artifact_registry_location" {
  description = "Artifact Registry location"
  type        = string
  default     = "us-central1"
}
