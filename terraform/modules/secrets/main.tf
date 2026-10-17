# The two Secret Manager secrets of the contract, replicated only in the lab region (user-managed
# replication). Values arrive as ephemeral values and are written only through the write-only
# argument secret_data_wo: they never reach the plan or state. secret_data_wo_version decides when
# a new version is sent. The apply identity writes them through roles/secretmanager.admin.

# Contract: JSON with string values username, password, host, port, dbname.
resource "google_secret_manager_secret" "db" {
  secret_id = "${var.name}-db-app"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "db" {
  count                  = var.manage_versions ? 1 : 0
  secret                 = google_secret_manager_secret.db.id
  secret_data_wo         = var.db_secret_value
  secret_data_wo_version = var.db_secret_version
}

# Contract: plain string, 48 random alphanumeric characters.
resource "google_secret_manager_secret" "admin_token" {
  secret_id = "${var.name}-app-admin-token"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "admin_token" {
  count                  = var.manage_versions ? 1 : 0
  secret                 = google_secret_manager_secret.admin_token.id
  secret_data_wo         = var.admin_token
  secret_data_wo_version = var.admin_token_version
}

moved {
  from = google_secret_manager_secret_version.db
  to   = google_secret_manager_secret_version.db[0]
}

moved {
  from = google_secret_manager_secret_version.admin_token
  to   = google_secret_manager_secret_version.admin_token[0]
}
