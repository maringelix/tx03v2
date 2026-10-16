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

  # tx03v2-gha-apply: environment lab only (required reviewer). It has the admin role of each service
  # the lab root uses and nothing of the others (no VMs, no buckets but the state, no BigQuery, no
  # Pub/Sub, no KMS): no Editor, no Secret Manager Admin and no Service Account User on the whole
  # project (roadmap R3.16). The roles stay project-wide, because a role cannot be tied to the name of
  # a resource that does not exist yet (a name condition covers a resource that exists, not the call
  # that creates it, and the support of conditions for the network and database resources could not
  # be checked without a cloud): the project must still be the lab's own (scripts/preflight.sh,
  # docs/GUARDRAILS.md SEC-18).
  apply_project_roles = [
    # The repository dx03v2 and its IAM.
    "roles/artifactregistry.admin",
    # resourcemanager.projects.get: the lab root reads the project number.
    "roles/browser",
    "roles/cloudsql.admin",
    # VPC, subnet, router, NAT, addresses and the Private Service Connect endpoint of Cloud SQL.
    "roles/compute.networkAdmin",
    # The Cloud Armor policy.
    "roles/compute.securityAdmin",
    # The cluster and its RBAC.
    "roles/container.admin",
    # The private zone of the Cloud SQL names.
    "roles/dns.admin",
    "roles/parametermanager.admin",
    # Use the enabled APIs (Editor had it; the omission is a classic error of a narrower role).
    "roles/serviceusage.serviceUsageConsumer",
  ]

  # Secret Manager without the values: Secret Manager Admin also has secretmanager.versions.access, so
  # it could read every secret of the project. The lab secrets are written with write-only arguments
  # and read by External Secrets only.
  lab_secrets_permissions = [
    "secretmanager.locations.get",
    "secretmanager.locations.list",
    "secretmanager.secrets.create",
    "secretmanager.secrets.delete",
    "secretmanager.secrets.get",
    "secretmanager.secrets.getIamPolicy",
    "secretmanager.secrets.list",
    "secretmanager.secrets.setIamPolicy",
    "secretmanager.secrets.update",
    "secretmanager.versions.add",
    "secretmanager.versions.destroy",
    "secretmanager.versions.disable",
    "secretmanager.versions.enable",
    "secretmanager.versions.get",
    "secretmanager.versions.list",
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

resource "google_project_iam_custom_role" "lab_secrets" {
  role_id     = "tx03v2LabSecrets"
  title       = "tx03v2 lab secrets, without secret values"
  description = "Create, update, delete and grant access to secrets and manage their versions, but never read a value."
  permissions = local.lab_secrets_permissions

  depends_on = [google_project_service.lab]
}

resource "google_project_iam_member" "apply_lab_secrets" {
  project = var.project_id
  role    = google_project_iam_custom_role.lab_secrets.id
  member  = google_service_account.github["apply"].member
}

# Only when a real apply fails with PERMISSION_DENIED for a permission that none of the roles above
# has (docs/RUNBOOK.md, section 12). Empty by default.
resource "google_project_iam_member" "apply_extra" {
  for_each = toset(var.apply_extra_project_roles)

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
# Owner, Editor or any admin role).
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
