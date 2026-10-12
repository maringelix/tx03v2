# Inputs are validated by the calling root (terraform/envs/lab); this module trusts them.

variable "name" {
  description = "Cluster name (contract: tx03v2-lab)."
  type        = string
}

variable "project_id" {
  description = "Project of the lab (workload pool <project_id>.svc.id.goog)."
  type        = string
}

variable "region" {
  description = "Region of the regional Autopilot cluster."
  type        = string
}

variable "network_id" {
  description = "VPC of the cluster."
  type        = string
}

variable "subnetwork_id" {
  description = "Nodes subnet of the cluster."
  type        = string
}

variable "pods_range_name" {
  description = "Secondary range of the nodes subnet for Pods."
  type        = string
}

variable "services_range_name" {
  description = "Secondary range of the nodes subnet for Services."
  type        = string
}

variable "node_service_account_email" {
  description = "E-mail of the node service account (tx03v2-lab-nodes)."
  type        = string
}
