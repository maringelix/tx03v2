output "db_secret_id" {
  description = "Resource ID of the database secret."
  value       = google_secret_manager_secret.db.id
}

output "db_secret_name" {
  description = "Name of the database secret (contract: tx03v2-lab-db-app)."
  value       = google_secret_manager_secret.db.secret_id
}

output "admin_token_secret_id" {
  description = "Resource ID of the admin token secret."
  value       = google_secret_manager_secret.admin_token.id
}

output "admin_token_secret_name" {
  description = "Name of the admin token secret (contract: tx03v2-lab-app-admin-token)."
  value       = google_secret_manager_secret.admin_token.secret_id
}
output "manages_versions" {
  description = "Whether Terraform writes values (false for DR: current-primary synchronization only)."
  value       = var.manage_versions
}
