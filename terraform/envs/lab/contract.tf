# Cross-repo contract (docs/CONTRATO.md): the values dx03v2 and platform/install.sh read from the
# Parameter Manager parameter tx03v2-lab-contract (JSON, alias latest). None of them is a secret.
locals {
  contract_keys = {
    "project-id"                   = var.project_id
    "region"                       = var.region
    "cluster-name"                 = module.gke.cluster_name
    "network-name"                 = module.network.network_name
    "nodes-subnet-cidr"            = module.network.nodes_subnet_cidr
    "db/endpoint-ip"               = module.cloudsql.endpoint_ip
    "lb-source-ranges"             = "35.191.0.0/16,130.211.0.0/22"
    "artifact-registry/repository" = module.artifact_registry.repository_path
    "db/secret-name"               = module.secrets.db_secret_name
    "app/admin-token-secret-name"  = module.secrets.admin_token_secret_name
    "eso/cluster-secret-store"     = "gcp-secret-manager"
    "gateway/address-name"         = module.network.gateway_address_name
    "gateway/address"              = module.network.gateway_address
    "waf/security-policy"          = module.waf.security_policy_name
    "deploy/service-account"       = var.deploy_service_account
    "dns/hostname"                 = local.public_edge_enabled ? var.app_domain_name : "disabled"
    "dns/certificate-map"          = local.public_edge_enabled ? google_certificate_manager_certificate_map.app[0].name : "disabled"
    "mesh/management"              = var.enable_managed_mesh ? "managed" : "disabled"
  }
}
