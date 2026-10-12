# Inputs are validated by the calling root (terraform/envs/lab); this module trusts them.

variable "name" {
  description = "Name prefix of the lab (tx03v2-lab), used in the description."
  type        = string
}

variable "project_id" {
  description = "Project of the repository (part of the image path)."
  type        = string
}

variable "region" {
  description = "Region of the repository (<region>-docker.pkg.dev)."
  type        = string
}

variable "repository_id" {
  description = "Repository ID (contract: dx03v2)."
  type        = string
  default     = "dx03v2"
}
