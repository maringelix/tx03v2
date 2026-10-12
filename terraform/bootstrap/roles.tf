# IAM roles of the GitHub service accounts. dx03v2-gha-deploy gets its roles from the lab root, on
# the lab resources (contract): nothing here.
locals {
  # The only project roles tx03v2-gha-apply may grant or revoke: the list of modules/project-roles,
  # the same list the lab root uses (tests prove both sides). Syntax of the "modifiedGrantsByRole"
  # IAM condition (Google Cloud IAM docs, "Delegate granting access with IAM conditions",
  # verified 2026-10-11).
  apply_grantable_roles = module.project_roles.lab_project_roles
  apply_iam_condition = format(
    "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([%s])",
    join(", ", [for r in local.apply_grantable_roles : "'${r}'"]),
  )

  # tx03v2-gha-plan: read-only. Viewer reads the lab resources, Security Reviewer their IAM
  # policies (the refresh of every *_iam_member), the bucket role the state (plans run with
  # -lock=false: the lock object would need write access). Parameter Viewer: the refresh of
  # google_parameter_manager_parameter_version GETs the version with its (non-secret) payload,
  # which needs parametermanager.parameterVersions.get (google 8.6.0 source, verified 2026-10-11).
  # The secret versions use secret_data_wo_version, so their refresh never calls :access and the
  # plan identity reads no secret value.
  plan_project_roles = ["roles/iam.securityReviewer", "roles/parametermanager.parameterViewer", "roles/viewer"]

  # tx03v2-gha-apply: environment lab only (required reviewer). Editor creates the lab resources;
  # the admin roles add what Editor lacks (cluster RBAC, resource IAM of secrets, repositories and
  # parameters); Service Account User lets GKE nodes run as tx03v2-lab-nodes.
  apply_project_roles = [
    "roles/artifactregistry.admin",
    "roles/container.admin",
    "roles/editor",
    "roles/iam.serviceAccountUser",
    "roles/parametermanager.admin",
    "roles/secretmanager.admin",
  ]
}

# --- tx03v2-gha-plan ---

resource "google_project_iam_member" "plan" {
  for_each = toset(local.plan_project_roles)

  project = var.project_id
  role    = each.value
  member  = google_service_account.github["plan"].member
}

resource "google_storage_bucket_iam_member" "plan_state" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.github["plan"].member
}

# --- tx03v2-gha-apply ---

resource "google_project_iam_member" "apply" {
  for_each = toset(local.apply_project_roles)

  project = var.project_id
  role    = each.value
  member  = google_service_account.github["apply"].member
}

resource "google_storage_bucket_iam_member" "apply_state" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectUser"
  member = google_service_account.github["apply"].member
}

# Project IAM changes limited by an IAM condition to the roles of modules/project-roles (never
# roles/owner, roles/editor or any admin role).
resource "google_project_iam_member" "apply_project_iam_admin" {
  project = var.project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = google_service_account.github["apply"].member

  condition {
    title       = "tx03v2-lab-project-roles-only"
    description = "tx03v2-gha-apply may grant or revoke only the project roles of terraform/modules/project-roles."
    expression  = local.apply_iam_condition
  }
}
