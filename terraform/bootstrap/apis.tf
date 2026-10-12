# The APIs the lab needs, enabled once by the project Owner (the CI identities cannot enable
# services). disable_on_destroy = false: tearing down the bootstrap never turns an API off.
resource "google_project_service" "lab" {
  for_each = toset(local.services)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
