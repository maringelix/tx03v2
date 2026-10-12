# Cloud SQL for PostgreSQL 17 of dx03v2 (contract): edition ENTERPRISE (PostgreSQL 16+ defaults
# to Enterprise Plus, which has no shared-core tiers), zonal, 10 GB SSD without automatic growth,
# automated backups with one retained backup that do not outlive the instance.
# Access only through Private Service Connect: no public IP, no private services access (VPC
# peering has an open destroy bug, terraform-provider-google #19908). The consumer endpoint is an
# internal address in the nodes subnet plus a forwarding rule to the service attachment of the
# instance; a private Cloud DNS zone <region>.sql.goog. resolves the instance DNS name (the name
# the server certificate carries, checked by verify-full in dx03v2) to that address.
# TLS: encrypted connections only, shared regional CA (GOOGLE_MANAGED_CAS_CA: the SAN has the
# instance DNS name), automatic server certificate rotation during maintenance.

# Instance names stay reserved for up to a week after a deletion: a random suffix per instance.
resource "random_id" "instance" {
  byte_length = 2
}

resource "google_sql_database_instance" "this" {
  name                = "${var.name}-${random_id.instance.hex}"
  region              = var.region
  database_version    = "POSTGRES_17"
  deletion_protection = false

  settings {
    tier                        = var.tier
    edition                     = "ENTERPRISE"
    availability_type           = "ZONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = var.disk_size_gb
    disk_autoresize             = false
    deletion_protection_enabled = false
    retain_backups_on_delete    = false

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = false

      backup_retention_settings {
        retained_backups = 1
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled                     = false
      ssl_mode                         = "ENCRYPTED_ONLY"
      server_ca_mode                   = "GOOGLE_MANAGED_CAS_CA"
      server_certificate_rotation_mode = "AUTOMATIC_ROTATION_DURING_MAINTENANCE"

      psc_config {
        psc_enabled               = true
        allowed_consumer_projects = [var.project_id]
      }
    }
  }
}

# Deleting a PostgreSQL user that owns objects or a database with open connections fails: both go
# away with the instance (provider issue #7677).
resource "google_sql_database" "app" {
  name            = var.database_name
  instance        = google_sql_database_instance.this.name
  deletion_policy = "ABANDON"
}

resource "google_sql_user" "app" {
  name                = var.user_name
  instance            = google_sql_database_instance.this.name
  password_wo         = var.password
  password_wo_version = var.password_version
  deletion_policy     = "ABANDON"
}

# --- Private Service Connect endpoint (consumer side) ---

resource "google_compute_address" "endpoint" {
  name         = "${var.name}-db"
  region       = var.region
  subnetwork   = var.subnetwork_id
  address_type = "INTERNAL"
}

resource "google_compute_forwarding_rule" "endpoint" {
  name   = "${var.name}-db"
  region = var.region
  # An empty scheme is the documented value for a PSC endpoint to a service attachment.
  load_balancing_scheme = ""
  network               = var.network_id
  ip_address            = google_compute_address.endpoint.id
  target                = google_sql_database_instance.this.psc_service_attachment_link
}

resource "google_dns_managed_zone" "sql" {
  name        = "${var.name}-sql"
  dns_name    = "${var.region}.sql.goog."
  description = "Private Service Connect names of the ${var.name} Cloud SQL instance (VPC ${var.name} only)."
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = var.network_id
    }
  }
}

resource "google_dns_record_set" "instance" {
  managed_zone = google_dns_managed_zone.sql.name
  name         = google_sql_database_instance.this.dns_name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.endpoint.address]
}
