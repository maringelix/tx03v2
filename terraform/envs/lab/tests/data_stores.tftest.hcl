# Data stores of the contract: Cloud SQL for PostgreSQL 17 (edition ENTERPRISE, Private Service
# Connect only, TLS with the shared regional CA), its PSC endpoint and private DNS name, the two
# Secret Manager secrets (write-only values) and the Artifact Registry repository dx03v2. Modules
# tested directly; write-only arguments are always null in plan and state, so the tests check that
# their versions are set.

mock_provider "google" {
  source = "../../tests/mocks"
}

run "cloudsql_postgres_17_enterprise_psc_only" {
  command = apply

  module {
    source = "../../modules/cloudsql"
  }

  variables {
    name             = "tx03v2-lab"
    project_id       = "tx03v2-lab-example"
    region           = "us-central1"
    network_id       = "projects/tx03v2-lab-example/global/networks/tx03v2-lab"
    subnetwork_id    = "projects/tx03v2-lab-example/regions/us-central1/subnetworks/tx03v2-lab-nodes"
    tier             = "db-g1-small"
    password         = "placeholder-password-not-a-secret-0000000"
    password_version = 1
  }

  assert {
    condition = (
      can(regex("^tx03v2-lab-[0-9a-f]{4}$", google_sql_database_instance.this.name)) &&
      google_sql_database_instance.this.region == "us-central1" &&
      google_sql_database_instance.this.database_version == "POSTGRES_17" &&
      google_sql_database_instance.this.deletion_protection == false
    )
    error_message = "PostgreSQL 17 instance tx03v2-lab-<4 hex> (names of deleted instances stay reserved for a week)."
  }

  assert {
    condition = (
      google_sql_database_instance.this.settings[0].edition == "ENTERPRISE" &&
      google_sql_database_instance.this.settings[0].tier == "db-g1-small" &&
      google_sql_database_instance.this.settings[0].availability_type == "ZONAL"
    )
    error_message = "Edition ENTERPRISE explicitly (PostgreSQL 16+ defaults to Enterprise Plus, which refuses shared-core tiers), zonal."
  }

  assert {
    condition = (
      google_sql_database_instance.this.settings[0].disk_type == "PD_SSD" &&
      google_sql_database_instance.this.settings[0].disk_size == 10 &&
      google_sql_database_instance.this.settings[0].disk_autoresize == false &&
      google_sql_database_instance.this.settings[0].deletion_protection_enabled == false &&
      google_sql_database_instance.this.settings[0].retain_backups_on_delete == false
    )
    error_message = "10 GB SSD without automatic growth; backups do not outlive the instance (lab)."
  }

  assert {
    condition = (
      google_sql_database_instance.this.settings[0].backup_configuration[0].enabled == true &&
      google_sql_database_instance.this.settings[0].backup_configuration[0].point_in_time_recovery_enabled == false &&
      google_sql_database_instance.this.settings[0].backup_configuration[0].backup_retention_settings[0].retained_backups == 1 &&
      google_sql_database_instance.this.settings[0].backup_configuration[0].backup_retention_settings[0].retention_unit == "COUNT"
    )
    error_message = "Automated backups on, one retained backup, no PITR (cost)."
  }

  assert {
    condition = (
      google_sql_database_instance.this.settings[0].ip_configuration[0].ipv4_enabled == false &&
      one(google_sql_database_instance.this.settings[0].ip_configuration[0].psc_config).psc_enabled == true &&
      one(google_sql_database_instance.this.settings[0].ip_configuration[0].psc_config).allowed_consumer_projects == toset(["tx03v2-lab-example"]) &&
      google_sql_database_instance.this.settings[0].ip_configuration[0].private_network == null
    )
    error_message = "No public IP and no private services access: Private Service Connect only, for the lab project only."
  }

  assert {
    condition = (
      google_sql_database_instance.this.settings[0].ip_configuration[0].ssl_mode == "ENCRYPTED_ONLY" &&
      google_sql_database_instance.this.settings[0].ip_configuration[0].server_ca_mode == "GOOGLE_MANAGED_CAS_CA" &&
      google_sql_database_instance.this.settings[0].ip_configuration[0].server_certificate_rotation_mode == "AUTOMATIC_ROTATION_DURING_MAINTENANCE"
    )
    error_message = "TLS only, shared regional CA (the SAN has the instance DNS name), automatic server certificate rotation."
  }

  assert {
    condition = (
      google_sql_database.app.name == "app" && google_sql_database.app.deletion_policy == "ABANDON" &&
      google_sql_user.app.name == "app" && google_sql_user.app.deletion_policy == "ABANDON" &&
      google_sql_user.app.password_wo == null && google_sql_user.app.password_wo_version == 1
    )
    error_message = "Database and user app (abandoned on destroy, they go with the instance); the password is write-only."
  }

  assert {
    condition = (
      google_compute_address.endpoint.name == "tx03v2-lab-db" &&
      google_compute_address.endpoint.address_type == "INTERNAL" &&
      google_compute_address.endpoint.subnetwork == "projects/tx03v2-lab-example/regions/us-central1/subnetworks/tx03v2-lab-nodes" &&
      google_compute_forwarding_rule.endpoint.name == "tx03v2-lab-db" &&
      google_compute_forwarding_rule.endpoint.load_balancing_scheme == "" &&
      google_compute_forwarding_rule.endpoint.target == google_sql_database_instance.this.psc_service_attachment_link &&
      google_compute_forwarding_rule.endpoint.ip_address == google_compute_address.endpoint.id
    )
    error_message = "PSC endpoint tx03v2-lab-db: an internal address of the nodes subnet forwarded to the service attachment of the instance."
  }

  assert {
    condition = (
      google_dns_managed_zone.sql.name == "tx03v2-lab-sql" &&
      google_dns_managed_zone.sql.dns_name == "us-central1.sql.goog." &&
      google_dns_managed_zone.sql.visibility == "private" &&
      [for n in google_dns_managed_zone.sql.private_visibility_config[0].networks : n.network_url] == ["projects/tx03v2-lab-example/global/networks/tx03v2-lab"]
    )
    error_message = "Private zone <region>.sql.goog. visible only in the lab VPC."
  }

  assert {
    condition = (
      google_dns_record_set.instance.name == "0a1b2c3d4e5f.example.us-central1.sql.goog." &&
      google_dns_record_set.instance.type == "A" &&
      google_dns_record_set.instance.rrdatas == tolist(["10.30.0.5"])
    )
    error_message = "The instance DNS name resolves to the PSC endpoint inside the VPC."
  }

  assert {
    condition     = output.dns_name == "0a1b2c3d4e5f.example.us-central1.sql.goog" && output.endpoint_ip == "10.30.0.5" && output.port == 5432
    error_message = "The secret host is the DNS name without the final dot (the name verify-full checks)."
  }
}

run "secrets_are_regional_and_write_only" {
  command = apply

  module {
    source = "../../modules/secrets"
  }

  variables {
    name                = "tx03v2-lab"
    region              = "us-central1"
    db_secret_value     = "{\"username\":\"app\",\"password\":\"placeholder\",\"host\":\"db.example\",\"port\":\"5432\",\"dbname\":\"app\"}"
    db_secret_version   = 1
    admin_token         = "placeholder-token-placeholder-token-placeholder0"
    admin_token_version = 3
  }

  assert {
    condition     = google_secret_manager_secret.db.secret_id == "tx03v2-lab-db-app" && google_secret_manager_secret.admin_token.secret_id == "tx03v2-lab-app-admin-token"
    error_message = "Secret names of the contract: tx03v2-lab-db-app and tx03v2-lab-app-admin-token."
  }

  assert {
    condition = alltrue([
      for s in [google_secret_manager_secret.db, google_secret_manager_secret.admin_token] :
      [for r in s.replication[0].user_managed[0].replicas : r.location] == ["us-central1"]
    ])
    error_message = "Both secrets are replicated only in the lab region."
  }

  assert {
    # secret_data_wo_version is a string attribute in the google provider 8.6.0 schema.
    condition = (
      google_secret_manager_secret_version.db.secret_data_wo_version == "1" &&
      google_secret_manager_secret_version.admin_token.secret_data_wo_version == "3"
    )
    error_message = "The version inputs drive new secret versions."
  }

  assert {
    condition     = google_secret_manager_secret_version.db.secret_data == null && google_secret_manager_secret_version.admin_token.secret_data == null
    error_message = "Values go only through secret_data_wo: the stored secret_data attribute stays empty (never in plan or state)."
  }

  assert {
    condition     = google_secret_manager_secret_version.db.secret_data_wo == null && google_secret_manager_secret_version.admin_token.secret_data_wo == null
    error_message = "Write-only arguments are never persisted."
  }
}

run "artifact_registry_has_immutable_tags" {
  command = apply

  module {
    source = "../../modules/artifact-registry"
  }

  variables {
    name       = "tx03v2-lab"
    project_id = "tx03v2-lab-example"
    region     = "us-central1"
  }

  assert {
    condition = (
      google_artifact_registry_repository.this.repository_id == "dx03v2" &&
      google_artifact_registry_repository.this.location == "us-central1" &&
      google_artifact_registry_repository.this.format == "DOCKER" &&
      google_artifact_registry_repository.this.docker_config[0].immutable_tags == true
    )
    error_message = "Docker repository dx03v2 in the lab region with immutable tags (contract)."
  }

  assert {
    condition     = google_artifact_registry_repository.this.vulnerability_scanning_config[0].enablement_config == "DISABLED"
    error_message = "Scanning is the trivy gate of the dx03v2 CI (Artifact Analysis bills per image)."
  }

  assert {
    condition = (
      google_artifact_registry_repository.this.cleanup_policy_dry_run == false &&
      { for p in google_artifact_registry_repository.this.cleanup_policies : p.id => p.action } == {
        "delete-untagged-after-7-days" = "DELETE"
        "keep-10-most-recent"          = "KEEP"
      }
    )
    error_message = "Cleanup: untagged versions older than 7 days go, the 10 most recent stay."
  }

  assert {
    condition     = output.repository_path == "us-central1-docker.pkg.dev/tx03v2-lab-example/dx03v2"
    error_message = "Image path prefix of the contract key artifact-registry/repository."
  }
}
