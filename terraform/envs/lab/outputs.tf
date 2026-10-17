# Non-sensitive outputs only. Secrets stay in Secret Manager (write-only), never in outputs.

output "project_id" {
  description = "Project of the lab."
  value       = var.project_id
}

output "region" {
  description = "Region of the lab."
  value       = var.region
}

output "cluster_name" {
  description = "GKE Autopilot cluster name."
  value       = module.gke.cluster_name
}

output "get_credentials_command" {
  description = "Writes the kubeconfig of the DNS-based endpoint of the cluster (IAM-authenticated; needs gke-gcloud-auth-plugin) to its own file; ~/.kube/config and its current context stay untouched. Then: export KUBECONFIG=/tmp/tx03v2-lab.kubeconfig"
  value       = "KUBECONFIG=/tmp/${module.gke.cluster_name}.kubeconfig gcloud container clusters get-credentials ${module.gke.cluster_name} --location ${var.region} --project ${var.project_id} --dns-endpoint"
}

output "contract_parameter" {
  description = "Parameter Manager parameter of the contract (read with: gcloud parametermanager parameters versions render latest --parameter=<this> --location=global)."
  value       = module.contract.parameter_id
}

output "contract_keys" {
  description = "Contract keys published in the parameter."
  value       = module.contract.keys
}

output "artifact_registry_repository" {
  description = "Image path prefix of the dx03v2 images."
  value       = module.artifact_registry.repository_path
}

output "velero_bucket_name" {
  description = "Regional Cloud Storage bucket for Velero backups (the platform installer derives the same name)."
  value       = module.velero.bucket_name
}

output "gateway_address" {
  description = "Global IPv4 of the Gateway (the app answers there once dx03v2 is deployed)."
  value       = module.network.gateway_address
}

output "dns_name_servers" {
  description = "Name servers of the public Cloud DNS zone, to delegate at the registrar (empty without dns_zone_name). The Google-managed certificate stays PROVISIONING until the delegation resolves."
  value       = local.public_edge_enabled ? google_dns_managed_zone.app[0].name_servers : []
}

output "app_hostname" {
  description = "Hostname of the HTTPS endpoint of the full profile, or disabled."
  value       = local.public_edge_enabled ? var.app_domain_name : "disabled"
}

output "waf_security_policy" {
  description = "Cloud Armor policy name, or none when enable_waf = false."
  value       = module.waf.security_policy_name
}

output "cloudsql_instance_name" {
  description = "Cloud SQL instance name (tx03v2-lab-<4 hex>)."
  value       = module.cloudsql.instance_name
}

output "db_endpoint_ip" {
  description = "Internal IP of the Private Service Connect endpoint of Cloud SQL."
  value       = module.cloudsql.endpoint_ip
}

output "db_profile" {
  description = "Selected continuity profile: core, ha, or dr."
  value       = var.db_profile
}

output "dr_region" {
  description = "Secondary region if the DR profile is enabled; empty otherwise."
  value       = var.db_profile == "dr" ? var.dr_region : ""
}

output "dr_cluster_name" {
  description = "Independent secondary GKE Autopilot cluster, or empty without DR."
  value       = var.db_profile == "dr" ? module.gke_dr[0].cluster_name : ""
}

output "dr_cloudsql_replica_name" {
  description = "Cross-region read replica to promote manually after fencing and lag review."
  value       = var.db_profile == "dr" ? google_sql_database_instance.dr[0].name : ""
}

output "dr_db_hostname" {
  description = "Verified TLS name used by the apply-only current-credential replication."
  value       = var.db_profile == "dr" ? trimsuffix(google_sql_database_instance.dr[0].dns_name, ".") : ""
}

output "dr_contract_parameter" {
  description = "Secondary contract with regional cluster, registry, secrets and PSC endpoint."
  value       = var.db_profile == "dr" ? module.contract_dr[0].parameter_id : ""
}

output "dr_velero_bucket_name" {
  description = "Regional backup bucket for the secondary cluster."
  value       = var.db_profile == "dr" ? module.velero_dr[0].bucket_name : ""
}

output "node_service_account" {
  description = "E-mail of the node service account (created by terraform/bootstrap)."
  value       = local.nodes_service_account_email
}
