output "lab_project_roles" {
  description = "Every project-level IAM role the lab root may grant (sorted)."
  value       = sort(local.lab_project_roles)
}
