output "cluster_name" {
  description = "Cluster name (contract key cluster-name)."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Cluster ID."
  value       = google_container_cluster.this.id
}

output "location" {
  description = "Region of the cluster."
  value       = google_container_cluster.this.location
}

output "workload_pool" {
  description = "Workload Identity Federation for GKE pool (<project_id>.svc.id.goog)."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "dns_endpoint" {
  description = "DNS-based endpoint of the control plane (IAM-authenticated)."
  value       = google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint
}
