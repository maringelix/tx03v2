# Remote state of the lab root: one bucket in the lab region with uniform bucket-level access
# (IAM only, no ACLs), public access prevention enforced and object versioning; noncurrent
# versions are kept 30 days. The GCS backend locks the state with a lock object. The bucket
# outlives every lab round: deletion_policy = PREVENT refuses any destroy until
# state_protection = false (final teardown, docs/RUNBOOK.md), and force_destroy = false refuses to
# delete it while it holds objects.
resource "google_storage_bucket" "state" {
  name                        = local.state_bucket_name
  location                    = upper(var.state_location == "" ? var.region : var.state_location)
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  deletion_policy             = var.state_protection ? "PREVENT" : "DELETE"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 30
      with_state                 = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.lab]
}
