# Inputs are validated by the calling root (terraform/envs/lab); this module trusts them.

variable "name" {
  description = "Name prefix of the lab (tx03v2-lab): the policy becomes <name>-waf."
  type        = string
}

variable "enable_waf" {
  description = "Create the Cloud Armor policy (false: the contract key waf/security-policy is none)."
  type        = bool
}
