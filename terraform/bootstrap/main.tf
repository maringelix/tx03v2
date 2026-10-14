# Bootstrap: applied once, locally, by a human who is Owner of a dedicated project with billing
# linked (docs/RUNBOOK.md). Creates what the CI cannot create for itself: the APIs of the lab, the
# state bucket, the GitHub Workload Identity Federation pool and provider, the three CI service
# accounts with their roles and the project budget.
data "google_project" "this" {
  project_id = var.project_id
}

locals {
  project     = "tx03v2"
  environment = "lab"
  lab_name    = "${local.project}-${local.environment}"

  project_number = data.google_project.this.number
  # Contract: deterministic suffix for globally unique names (no random).
  suffix            = substr(sha1(var.project_id), 0, 8)
  state_bucket_name = "${local.project}-tfstate-${local.suffix}"

  # APIs of the lab (verified 2026-10-11). Never disabled on destroy: other things in the project
  # (and the next round) may still need them.
  services = [
    "artifactregistry.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudtrace.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "dns.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "parametermanager.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "sqladmin.googleapis.com",
    "sts.googleapis.com",
  ]
}

module "project_roles" {
  source = "../modules/project-roles"
}
