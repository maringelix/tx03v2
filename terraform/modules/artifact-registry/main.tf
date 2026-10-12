# Artifact Registry Docker repository of the dx03v2 images (contract: dx03v2 in the lab region).
# Tags are immutable (dx03v2 pushes the 40-character git SHA once). Cleanup: untagged versions
# older than 7 days are deleted, the 10 most recent versions are always kept (KEEP wins over
# DELETE). Vulnerability scanning is off: the gate is the trivy scan in the dx03v2 CI.
resource "google_artifact_registry_repository" "this" {
  location      = var.region
  repository_id = var.repository_id
  description   = "dx03v2 images (api, web) of the ${var.name} lab."
  format        = "DOCKER"
  mode          = "STANDARD_REPOSITORY"

  docker_config {
    immutable_tags = true
  }

  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "delete-untagged-after-7-days"
    action = "DELETE"

    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s"
    }
  }

  cleanup_policies {
    id     = "keep-10-most-recent"
    action = "KEEP"

    most_recent_versions {
      keep_count = 10
    }
  }

  vulnerability_scanning_config {
    enablement_config = "DISABLED"
  }
}
