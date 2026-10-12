output "parameter_id" {
  description = "Parameter ID (tx03v2-lab-contract)."
  value       = google_parameter_manager_parameter.this.parameter_id
}

output "version_id" {
  description = "ID of the live version (c-<16 hex of the sha256 of the JSON>)."
  value       = google_parameter_manager_parameter_version.this.parameter_version_id
}

output "keys" {
  description = "Every contract key published (sorted)."
  value       = sort(keys(var.values))
}

output "json" {
  description = "The published JSON (not secret)."
  value       = local.data
}
