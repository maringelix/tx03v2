# Inputs are validated by the calling root (terraform/envs/lab); this module trusts them.

variable "name" {
  description = "Prefix of the secret names (tx03v2-lab)."
  type        = string
}

variable "region" {
  description = "The only replica location of the secrets."
  type        = string
}

variable "db_secret_value" {
  description = "Ephemeral JSON of the database credentials (username, password, host, port, dbname)."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "db_secret_version" {
  description = "Write-only version of the database secret (bumped together with the user password)."
  type        = number
}

variable "admin_token" {
  description = "Ephemeral admin token of dx03v2."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "admin_token_version" {
  description = "Write-only version of the admin token secret."
  type        = number
}
