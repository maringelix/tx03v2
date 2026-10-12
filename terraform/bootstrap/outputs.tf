# Identifiers only (no secret exists: GitHub reaches Google Cloud through Workload Identity
# Federation). They are not secret, but they identify your project: keep them out of public issues.

output "project_number" {
  description = "Number of the lab project."
  value       = local.project_number
}

output "workload_identity_provider" {
  description = "Resource name of the GitHub workload identity provider (GitHub variable GCP_WORKLOAD_IDENTITY_PROVIDER of tx03v2 and dx03v2)."
  value       = "${local.pool_name}/providers/${google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id}"
}

output "plan_service_account" {
  description = "E-mail of tx03v2-gha-plan (tx03v2 variable GCP_PLAN_SERVICE_ACCOUNT)."
  value       = google_service_account.github["plan"].email
}

output "apply_service_account" {
  description = "E-mail of tx03v2-gha-apply (tx03v2 variable GCP_APPLY_SERVICE_ACCOUNT)."
  value       = google_service_account.github["apply"].email
}

output "deploy_service_account" {
  description = "E-mail of dx03v2-gha-deploy (tx03v2 variable LAB_DEPLOY_SERVICE_ACCOUNT, dx03v2 variable GCP_DEPLOY_SERVICE_ACCOUNT)."
  value       = google_service_account.github["deploy"].email
}

output "state_bucket_name" {
  description = "Bucket of the lab state (tx03v2 variable TF_STATE_BUCKET)."
  value       = google_storage_bucket.state.name
}

output "backend_hcl" {
  description = "Ready content of terraform/envs/lab/backend.hcl (git-ignored)."
  value       = <<-EOT
    bucket = "${google_storage_bucket.state.name}"
    prefix = "envs/lab"
  EOT
}

output "budget_name" {
  description = "Display name of the Cloud Billing budget that sends the alerts."
  value       = google_billing_budget.monthly.display_name
}

output "github_variables_tx03v2" {
  description = "Repository variables of tx03v2 known after the bootstrap (docs/RUNBOOK.md lists the LAB_* ones you choose)."
  value = {
    GCP_PROJECT_ID                 = var.project_id
    GCP_REGION                     = var.region
    GCP_WORKLOAD_IDENTITY_PROVIDER = "${local.pool_name}/providers/${google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id}"
    GCP_PLAN_SERVICE_ACCOUNT       = google_service_account.github["plan"].email
    GCP_APPLY_SERVICE_ACCOUNT      = google_service_account.github["apply"].email
    TF_STATE_BUCKET                = google_storage_bucket.state.name
    LAB_DEPLOY_SERVICE_ACCOUNT     = google_service_account.github["deploy"].email
  }
}

output "github_variables_dx03v2" {
  description = "Repository variables of dx03v2 (its deploy workflow)."
  value = {
    GCP_PROJECT_ID                 = var.project_id
    GCP_WORKLOAD_IDENTITY_PROVIDER = "${local.pool_name}/providers/${google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id}"
    GCP_DEPLOY_SERVICE_ACCOUNT     = google_service_account.github["deploy"].email
  }
}
