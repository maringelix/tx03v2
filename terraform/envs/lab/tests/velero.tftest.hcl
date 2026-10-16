# Dedicated regional backup bucket and direct Workload Identity Federation for Velero; no key,
# Google service account, or project-level object role.

mock_provider "google" {
  source = "../../tests/mocks"
}

run "velero_bucket_is_private_regional_and_expires_backups" {
  command = apply

  module {
    source = "../../modules/velero"
  }

  variables {
    name       = "tx03v2-lab"
    project_id = "tx03v2-lab-example"
    region     = "us-central1"
  }

  assert {
    condition = (
      google_storage_bucket.this.name == "tx03v2-lab-velero-tx03v2-lab-example" &&
      google_storage_bucket.this.location == "us-central1" &&
      google_storage_bucket.this.project == "tx03v2-lab-example" &&
      google_storage_bucket.this.force_destroy == false &&
      google_storage_bucket.this.uniform_bucket_level_access == true &&
      google_storage_bucket.this.public_access_prevention == "enforced"
    )
    error_message = "Velero's regional bucket is private and cannot be force-deleted while backups remain."
  }

  assert {
    condition = (
      one(google_storage_bucket.this.versioning).enabled == false &&
      one(one(google_storage_bucket.this.lifecycle_rule).condition).age == 35 &&
      one(one(google_storage_bucket.this.lifecycle_rule).action).type == "Delete"
    )
    error_message = "Object versioning is off and backup objects expire after 35 days."
  }

  assert {
    condition = (
      google_storage_bucket_iam_member.velero.role == "roles/storage.objectAdmin" &&
      google_storage_bucket_iam_member.velero.bucket == google_storage_bucket.this.name &&
      google_storage_bucket_iam_member.velero.member == "principal://iam.googleapis.com/projects/000000000000/locations/global/workloadIdentityPools/tx03v2-lab-example.svc.id.goog/subject/ns/velero/sa/velero" &&
      output.bucket_name == google_storage_bucket.this.name &&
      output.velero_principal == google_storage_bucket_iam_member.velero.member
    )
    error_message = "Only the velero/velero GKE principal gets object access, scoped to this bucket."
  }
}
