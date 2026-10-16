output "bucket_name" {
  description = "Regional Cloud Storage bucket used by the Velero BackupStorageLocation."
  value       = google_storage_bucket.this.name
}

output "velero_principal" {
  description = "Direct GKE Workload Identity principal bound to roles/storage.objectAdmin on this bucket."
  value       = google_storage_bucket_iam_member.velero.member
}
