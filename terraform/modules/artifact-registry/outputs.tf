output "id" {
  description = "Repository resource ID."
  value       = google_artifact_registry_repository.this.id
}

output "repository_id" {
  description = "Repository ID (dx03v2)."
  value       = google_artifact_registry_repository.this.repository_id
}

output "location" {
  description = "Region of the repository."
  value       = google_artifact_registry_repository.this.location
}

output "repository_path" {
  description = "Image path prefix <region>-docker.pkg.dev/<project_id>/dx03v2 (contract key artifact-registry/repository)."
  value       = "${google_artifact_registry_repository.this.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.this.repository_id}"
}
