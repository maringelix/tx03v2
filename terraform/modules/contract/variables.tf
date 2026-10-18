# Inputs are validated by the calling root (terraform/envs/lab); this module trusts them.

variable "name" {
  description = "Parameter ID (contract: tx03v2-lab-contract)."
  type        = string
}

variable "values" {
  description = "Contract key => string value (docs/CONTRACT.md). None of them is a secret."
  type        = map(string)
}
