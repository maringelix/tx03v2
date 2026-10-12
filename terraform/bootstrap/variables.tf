variable "project_id" {
  description = "ID of the dedicated Google Cloud project of the lab (created by you, with billing linked; the bootstrap never guesses it)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "The project_id must be a Google Cloud project ID: 6-30 lowercase letters, digits or hyphens, starting with a letter, e.g. tx03v2-lab-example."
  }
}

variable "region" {
  description = "Region of the state bucket and of the lab (must match the region given to terraform/envs/lab)."
  type        = string
  default     = "us-central1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "The region must be a Google Cloud region name such as us-central1 or southamerica-east1."
  }
}

variable "github_owner" {
  description = "GitHub owner of the tx03v2 and dx03v2 repositories (workload identity provider condition and subjects)."
  type        = string
  default     = "maringelix"

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$", var.github_owner))
    error_message = "The github_owner must be a valid GitHub user or organization name."
  }
}

variable "billing_account" {
  description = "Billing account linked to the project (gcloud billing projects describe <project> --format='value(billingAccountName)'), without the billingAccounts/ prefix."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$", var.billing_account))
    error_message = "The billing_account must look like 000000-000000-000000 (uppercase hexadecimal, no billingAccounts/ prefix)."
  }
}

variable "budget_amount" {
  description = "Monthly budget of the project, in the currency of the billing account (whole units)."
  type        = number
  default     = 10

  validation {
    condition     = var.budget_amount >= 1 && var.budget_amount <= 1000 && floor(var.budget_amount) == var.budget_amount
    error_message = "The budget_amount must be a whole number between 1 and 1000."
  }
}

variable "budget_alert_emails" {
  description = "Extra e-mail addresses that receive the budget alerts through monitoring notification channels (0-10). The billing account administrators and users always receive them."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.budget_alert_emails) <= 10
    error_message = "Set at most 10 addresses in budget_alert_emails."
  }

  validation {
    condition     = alltrue([for e in var.budget_alert_emails : can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}$", e))])
    error_message = "Every budget_alert_emails entry must be a valid e-mail address, e.g. you@example.com."
  }
}

variable "state_protection" {
  description = "Refuse to destroy the state bucket (deletion_policy = PREVENT). Set false only for the final teardown."
  type        = bool
  default     = true
}
