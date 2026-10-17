# Lab root: composes the modules for tx03v2-lab inside the project prepared by terraform/bootstrap
# (APIs, state bucket, CI service accounts). Names, labels and published values follow
# docs/CONTRATO.md (contract v2 with dx03v2). Nothing here talks to the Kubernetes API: ESO, the
# OpenTelemetry Collector and the manifests are installed by platform/install.sh. Every IAM grant of the lab lives in roles.tf.
data "google_project" "this" {
  project_id = var.project_id
}

locals {
  project     = "tx03v2"
  environment = "lab"
  name        = "${local.project}-${local.environment}"

  project_number = data.google_project.this.number

  # The node service account is created by terraform/bootstrap (tx03v2-gha-apply may act as this
  # account only, and it must exist before the cluster): its name follows the contract.
  nodes_service_account_email = "${local.name}-nodes@${var.project_id}.iam.gserviceaccount.com"
  nodes_member                = "serviceAccount:${local.nodes_service_account_email}"

  # Workload Identity Federation for GKE principal of the ESO controller ServiceAccount
  # (external-secrets/external-secrets): no Google service account in between.
  eso_principal = "principal://iam.googleapis.com/projects/${local.project_number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/external-secrets/sa/external-secrets"
  # The same for the OpenTelemetry Collector of the platform layer (observability/opentelemetry-collector,
  # contract v2), which writes the traces of the app to Cloud Trace.
  otel_principal = "principal://iam.googleapis.com/projects/${local.project_number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/observability/sa/opentelemetry-collector"
  # The image scanner and the image admission controller of the full profile read the dx03v2 repository
  # with their own ServiceAccounts (trivy-system/trivy-operator and kyverno/kyverno-admission-controller):
  # short-lived federated tokens, no key and no Google service account.
  trivy_principal   = "principal://iam.googleapis.com/projects/${local.project_number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/trivy-system/sa/trivy-operator"
  kyverno_principal = "principal://iam.googleapis.com/projects/${local.project_number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/kyverno/sa/kyverno-admission-controller"
}

module "project_roles" {
  source = "../../modules/project-roles"
}

module "network" {
  source = "../../modules/network"

  name              = local.name
  region            = var.region
  nodes_subnet_cidr = var.nodes_subnet_cidr
  pods_cidr         = var.pods_cidr
  services_cidr     = var.services_cidr
}

# Nodes never run as the Compute Engine default service account (it has Editor).
module "gke" {
  source = "../../modules/gke"

  name                       = local.name
  project_id                 = var.project_id
  region                     = var.region
  network_id                 = module.network.network_id
  subnetwork_id              = module.network.nodes_subnet_id
  pods_range_name            = module.network.pods_range_name
  services_range_name        = module.network.services_range_name
  node_service_account_email = local.nodes_service_account_email
  control_plane_cidr         = var.control_plane_cidr

  # Nodes need their roles before GKE creates them (logging, metrics, image pulls).
  depends_on = [google_project_iam_member.lab]
}

module "cloudsql" {
  source = "../../modules/cloudsql"

  name             = local.name
  project_id       = var.project_id
  region           = var.region
  network_id       = module.network.network_id
  subnetwork_id    = module.network.nodes_subnet_id
  tier             = var.db_tier
  password         = ephemeral.random_password.db.result
  password_version = var.db_password_version
}

module "artifact_registry" {
  source = "../../modules/artifact-registry"

  name       = local.name
  project_id = var.project_id
  region     = var.region
}

module "velero" {
  source = "../../modules/velero"

  name       = local.name
  project_id = var.project_id
  region     = var.region

  # The GKE-managed workload identity pool exists after the Autopilot cluster is created.
  depends_on = [module.gke]
}

module "secrets" {
  source = "../../modules/secrets"

  name                = local.name
  region              = var.region
  db_secret_value     = local.db_secret_value
  db_secret_version   = var.db_password_version
  admin_token         = ephemeral.random_password.admin_token.result
  admin_token_version = var.admin_token_version
}

module "waf" {
  source = "../../modules/waf"

  name       = local.name
  enable_waf = var.enable_waf
}

module "contract" {
  source = "../../modules/contract"

  name   = "${local.name}-contract"
  values = local.contract_keys
}
