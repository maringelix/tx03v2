# Applied by a human who is Owner of the dedicated lab project, with Application Default
# Credentials (gcloud auth application-default login).
provider "google" {
  # Explicit on purpose: the bootstrap refuses to guess which project it changes.
  project = var.project_id
  region  = var.region
  # With user credentials the Billing Budget API needs a quota project: the lab project itself.
  user_project_override = true
  billing_project       = var.project_id

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
