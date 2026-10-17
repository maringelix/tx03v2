# Opt-in pilot-light region. A dedicated VPC, regional Autopilot cluster, registry, secrets, Velero
# bucket and Cloud SQL cross-region read replica are created only for db_profile=dr. Promotion is a
# manual, fenced operation: Terraform must not automatically turn a lagging replica into a writer.
module "network_dr" {
  count  = var.db_profile == "dr" ? 1 : 0
  source = "../../modules/network"

  name              = "${local.name}-dr"
  region            = var.dr_region
  nodes_subnet_cidr = var.dr_nodes_subnet_cidr
  pods_cidr         = var.dr_pods_cidr
  services_cidr     = var.dr_services_cidr
}

module "gke_dr" {
  count  = var.db_profile == "dr" ? 1 : 0
  source = "../../modules/gke"

  name                       = "${local.name}-dr"
  project_id                 = var.project_id
  region                     = var.dr_region
  network_id                 = module.network_dr[0].network_id
  subnetwork_id              = module.network_dr[0].nodes_subnet_id
  pods_range_name            = module.network_dr[0].pods_range_name
  services_range_name        = module.network_dr[0].services_range_name
  node_service_account_email = local.nodes_service_account_email
  control_plane_cidr         = var.dr_control_plane_cidr

  depends_on = [google_project_iam_member.lab]
}

module "artifact_registry_dr" {
  count  = var.db_profile == "dr" ? 1 : 0
  source = "../../modules/artifact-registry"

  name       = "${local.name}-dr"
  project_id = var.project_id
  region     = var.dr_region
}

resource "random_id" "db_dr" {
  count       = var.db_profile == "dr" ? 1 : 0
  byte_length = 2
}

resource "google_sql_database_instance" "dr" {
  count                = var.db_profile == "dr" ? 1 : 0
  name                 = "${local.name}-dr-${random_id.db_dr[0].hex}"
  project              = var.project_id
  region               = var.dr_region
  database_version     = "POSTGRES_17"
  master_instance_name = module.cloudsql.instance_name
  instance_type        = "READ_REPLICA_INSTANCE"
  deletion_protection  = var.db_deletion_protection

  settings {
    tier                        = var.ha_db_tier
    edition                     = "ENTERPRISE"
    availability_type           = "ZONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = 10
    disk_autoresize             = false
    deletion_protection_enabled = var.db_deletion_protection

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

# The replica needs its own PSC endpoint and regional DNS zone. The old primary endpoint is never
# re-pointed by Terraform during an outage; the DR contract publishes the separate endpoint.
resource "google_compute_address" "db_dr" {
  count        = var.db_profile == "dr" ? 1 : 0
  name         = "${local.name}-dr-db"
  region       = var.dr_region
  subnetwork   = module.network_dr[0].nodes_subnet_id
  address_type = "INTERNAL"
}

resource "google_compute_forwarding_rule" "db_dr" {
  count                 = var.db_profile == "dr" ? 1 : 0
  name                  = "${local.name}-dr-db"
  region                = var.dr_region
  load_balancing_scheme = ""
  network               = module.network_dr[0].network_id
  ip_address            = google_compute_address.db_dr[0].id
  target                = google_sql_database_instance.dr[0].psc_service_attachment_link
}

resource "google_dns_managed_zone" "sql_dr" {
  count       = var.db_profile == "dr" ? 1 : 0
  name        = "${local.name}-dr-sql"
  dns_name    = "${var.dr_region}.sql.goog."
  description = "Private SQL DNS in the isolated ${local.name}-dr VPC."
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = module.network_dr[0].network_id
    }
  }
}

resource "google_dns_record_set" "sql_dr" {
  count        = var.db_profile == "dr" ? 1 : 0
  managed_zone = google_dns_managed_zone.sql_dr[0].name
  name         = google_sql_database_instance.dr[0].dns_name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.db_dr[0].address]
}

locals {
  dr_db_secret_value = var.db_profile == "dr" ? jsonencode({
    username = module.cloudsql.user_name
    password = ephemeral.random_password.db.result
    host     = trimsuffix(google_sql_database_instance.dr[0].dns_name, ".")
    port     = "5432"
    dbname   = module.cloudsql.database_name
  }) : ""
}

module "secrets_dr" {
  count  = var.db_profile == "dr" ? 1 : 0
  source = "../../modules/secrets"

  name                = "${local.name}-dr"
  region              = var.dr_region
  db_secret_value     = local.dr_db_secret_value
  db_secret_version   = var.db_password_version
  admin_token         = ephemeral.random_password.admin_token.result
  admin_token_version = var.admin_token_version
}

module "velero_dr" {
  count  = var.db_profile == "dr" ? 1 : 0
  source = "../../modules/velero"

  name                 = "${local.name}-dr"
  project_id           = var.project_id
  region               = var.dr_region
  service_account_name = "velero-dr"

  depends_on = [module.gke_dr]
}

module "contract_dr" {
  count  = var.db_profile == "dr" ? 1 : 0
  source = "../../modules/contract"

  name = "${local.name}-dr-contract"
  values = merge(local.contract_keys, {
    "region"                       = var.dr_region
    "cluster-name"                 = module.gke_dr[0].cluster_name
    "network-name"                 = module.network_dr[0].network_name
    "nodes-subnet-cidr"            = module.network_dr[0].nodes_subnet_cidr
    "db/endpoint-ip"               = google_compute_address.db_dr[0].address
    "artifact-registry/repository" = module.artifact_registry_dr[0].repository_path
    "db/secret-name"               = module.secrets_dr[0].db_secret_name
    "app/admin-token-secret-name"  = module.secrets_dr[0].admin_token_secret_name
    "gateway/address-name"         = module.network_dr[0].gateway_address_name
    "gateway/address"              = module.network_dr[0].gateway_address
  })
}

# Recovery reads the surviving multiregion backup; the secondary can write only its own bucket.
resource "google_storage_bucket_iam_member" "velero_dr_recovery" {
  count  = var.db_profile == "dr" ? 1 : 0
  bucket = module.velero.bucket_name
  role   = "roles/storage.objectViewer"
  member = module.velero_dr[0].velero_principal
}

resource "google_gke_hub_membership" "dr" {
  count         = var.db_profile == "dr" && var.enable_managed_mesh ? 1 : 0
  membership_id = "${local.name}-dr"
  location      = var.dr_region
  endpoint {
    gke_cluster {
      resource_link = "//container.googleapis.com/${module.gke_dr[0].cluster_id}"
    }
  }
}

resource "google_gke_hub_feature_membership" "mesh_dr" {
  count               = var.db_profile == "dr" && var.enable_managed_mesh ? 1 : 0
  location            = google_gke_hub_feature.mesh[0].location
  feature             = google_gke_hub_feature.mesh[0].name
  membership          = google_gke_hub_membership.dr[0].membership_id
  membership_location = google_gke_hub_membership.dr[0].location
  mesh {
    management = "MANAGEMENT_AUTOMATIC"
  }
}
