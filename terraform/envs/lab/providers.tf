# Credentials come from the environment: google-github-actions/auth (Workload Identity Federation)
# in the workflows, Application Default Credentials (gcloud auth application-default login) locally.
provider "google" {
  project = var.project_id
  region  = var.region

  # Contract labels on every resource that takes labels. Label values cannot contain "/", hence
  # <owner>_tx03v2 for the repository.
  default_labels = {
    "project"     = local.project
    "environment" = local.environment
    "managed-by"  = "terraform"
    "repository"  = "${lower(var.github_owner)}_${local.project}"
  }
  # Exactly the four contract labels (no goog-terraform-provisioned label).
  add_terraform_attribution_label = false
}
