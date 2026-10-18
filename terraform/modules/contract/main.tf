# Parameter Manager parameter of the cross-repo contract (docs/CONTRACT.md): one global parameter
# in JSON format with one live version, read through the alias `latest` by dx03v2 and by
# platform/install.sh (gcloud parametermanager parameters versions render latest). Versions are
# immutable, so the version ID is derived from the content (c-<16 hex of sha256>): any change
# creates the new version before the old one is deleted.
locals {
  data       = jsonencode(var.values)
  version_id = "c-${substr(sha256(local.data), 0, 16)}"
}

resource "google_parameter_manager_parameter" "this" {
  parameter_id = var.name
  format       = "JSON"
}

resource "google_parameter_manager_parameter_version" "this" {
  parameter            = google_parameter_manager_parameter.this.id
  parameter_version_id = local.version_id
  parameter_data       = local.data

  lifecycle {
    create_before_destroy = true
  }
}
