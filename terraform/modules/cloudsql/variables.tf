# Inputs are validated by the calling root (terraform/envs/lab); this module trusts them.

variable "name" {
  description = "Name prefix of the lab (tx03v2-lab): instance <name>-<4 hex>, endpoint <name>-db, DNS zone <name>-sql."
  type        = string
}

variable "project_id" {
  description = "Project of the lab (the only allowed Private Service Connect consumer project)."
  type        = string
}

variable "region" {
  description = "Region of the instance and of the Private Service Connect endpoint."
  type        = string
}

variable "network_id" {
  description = "VPC of the Private Service Connect endpoint and of the private DNS zone."
  type        = string
}

variable "subnetwork_id" {
  description = "Subnet of the endpoint address (the nodes subnet)."
  type        = string
}

variable "tier" {
  description = "Machine tier (shared-core tiers need edition ENTERPRISE)."
  type        = string
}

variable "continuity_profile" {
  description = "core uses zonal/one backup; ha and dr use regional availability, PITR and longer retention."
  type        = string
  default     = "core"
}

variable "backup_count" {
  description = "Number of automated backups retained."
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "Protect the instance in both Terraform and Cloud SQL until explicitly disabled for teardown."
  type        = bool
  default     = false
}

variable "retain_backups_on_delete" {
  description = "Keep automated backups after instance deletion; opt-in because they keep billing."
  type        = bool
  default     = false
}

variable "disk_size_gb" {
  description = "SSD data disk in GB (no automatic growth)."
  type        = number
  default     = 10
}

variable "database_name" {
  description = "Database of the app (contract: app)."
  type        = string
  default     = "app"
}

variable "user_name" {
  description = "Database user of the app (contract: app)."
  type        = string
  default     = "app"
}

variable "password" {
  description = "Ephemeral password of the app user, sent only through password_wo."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "password_version" {
  description = "Increment to send a new password (drives password_wo_version)."
  type        = number
}
