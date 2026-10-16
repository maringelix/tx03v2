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
  description = "Regional Cloud Storage location for the Velero bucket."
  type        = string
}
