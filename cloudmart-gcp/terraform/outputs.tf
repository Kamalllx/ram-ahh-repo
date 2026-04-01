output "cloudmart_url" {
  description = "Public URL of the CloudMart application"
  value       = "https://${var.domain_name}"
}

output "api_gateway_url" {
  description = "Cloud Run API Gateway URL"
  value       = module.cloud_run.api_gateway_url
}

output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = module.gke.cluster_name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "artifact_registry_url" {
  description = "Artifact Registry URL for pushing images"
  value       = "${var.artifact_registry_location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.cloudmart.repository_id}"
}

output "images_bucket" {
  description = "GCS bucket for product images"
  value       = module.storage.images_bucket_name
}

output "assets_bucket" {
  description = "GCS bucket for static assets"
  value       = module.storage.assets_bucket_name
}

output "db_connection_name" {
  description = "Cloud SQL connection name"
  value       = module.database.connection_name
}

output "redis_host" {
  description = "Memorystore Redis host"
  value       = google_redis_instance.cloudmart.host
  sensitive   = true
}

output "orders_topic" {
  description = "Pub/Sub topic for order events"
  value       = module.pubsub.orders_topic_name
}

output "bigquery_dataset" {
  description = "BigQuery analytics dataset"
  value       = google_bigquery_dataset.analytics.dataset_id
}

output "dns_nameservers" {
  description = "Nameservers to configure at your domain registrar"
  value       = google_dns_managed_zone.cloudmart.name_servers
}

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${module.gke.cluster_name} --region ${var.region} --project ${var.project_id}"
}
