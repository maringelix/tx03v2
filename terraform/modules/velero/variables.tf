# Inputs are validated by the calling root (terraform/envs/lab); this module trusts them.

variable "name" {
  description = "Name prefix of the lab (tx03v2-lab)."
  type        = string
}

variable "project_id" {
  description = "Dedicated lab project; also makes the globally unique backup bucket name."
  type        = string
}

variable "region" {
  description = "Cloud Storage location: a region, or US for the opt-in multiregion DR backup."
  type        = string
}

variable "service_account_name" {
  description = "Exact namespace-local Kubernetes ServiceAccount granted access to this bucket."
  type        = string
  default     = "velero"
}
