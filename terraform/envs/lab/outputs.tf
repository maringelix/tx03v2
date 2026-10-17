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

output "node_service_account" {
  description = "E-mail of the node service account (created by terraform/bootstrap)."
  value       = local.nodes_service_account_email
}
