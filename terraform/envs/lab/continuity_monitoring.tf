# Native replica lag remains visible even if the primary Kubernetes cluster is lost.
resource "google_monitoring_alert_policy" "replica_lag" {
  count                 = var.db_profile == "dr" ? 1 : 0
  display_name          = "tx03v2-lab-dr-replica-lag"
  combiner              = "OR"
  enabled               = true
  notification_channels = var.continuity_notification_channels
  conditions {
    display_name = "PostgreSQL replica is more than 60 seconds behind"
    condition_threshold {
      filter          = "resource.type = \"cloudsql_database\" AND metric.type = \"cloudsql.googleapis.com/database/replication/replica_lag\" AND resource.labels.database_id = \"${var.project_id}:${google_sql_database_instance.dr[0].name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 60
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
      trigger { count = 1 }
    }
  }
  alert_strategy { auto_close = "1800s" }
  documentation {
    content   = "Review lag, last durable backup and replication state before fencing/promoting. Missing telemetry never proves RPO zero. docs/CONTINUIDADE.md."
    mime_type = "text/markdown"
  }
}
