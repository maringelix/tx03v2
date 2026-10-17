# Dedicated Cloud Storage bucket for Velero's Kubernetes-object backups. Cloud Storage encrypts
# objects at rest by default with Google-managed keys. The bucket is regional, private, versioning is
# off, and old backups expire after 35 days. force_destroy stays false: a fork must explicitly empty
# the bucket after its restore drill before terraform destroy can remove it.
data "google_project" "this" {
  project_id = var.project_id
}

locals {
  bucket_name = "${var.name}-velero-${var.project_id}"

  # Direct Workload Identity Federation for GKE principal (no Google service account or key).
  velero_principal = "principal://iam.googleapis.com/projects/${data.google_project.this.number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/velero/sa/${var.service_account_name}"
}

resource "google_storage_bucket" "this" {
  project                     = var.project_id
  name                        = local.bucket_name
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = false
  }

  lifecycle_rule {
    condition {
      age = 35
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    project     = "tx03v2"
    environment = "lab"
    managed_by  = "terraform"
  }
}

resource "google_storage_bucket_iam_member" "velero" {
  bucket = google_storage_bucket.this.name
  role   = "roles/storage.objectAdmin"
  member = local.velero_principal
}
