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
  description = "GitHub owner of the tx03v2 and dx03v2 repositories (workload identity provider condition and subjects). No default: the service accounts trust only the repositories of this owner, so a fork must name its own."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$", var.github_owner))
    error_message = "The github_owner must be a valid GitHub user or organization name."
  }

  validation {
    condition     = lower(var.github_owner) != "your-github-user"
    error_message = "Set github_owner to the GitHub user that owns your forks (terraform.tfvars.example holds a placeholder)."
  }
}

variable "github_owner_id" {
  description = "Numeric GitHub ID of github_owner (gh api users/<owner> --jq .id; it works for organizations too). GitHub writes it, and the ID of the repository, into the OIDC subject of every repository created after 2026-07-15 (immutable subject claims). The provider condition and the subjects pin both, so a deleted and re-registered account name does not inherit the lab."
  type        = string

  validation {
    condition     = can(regex("^[1-9][0-9]{0,15}$", var.github_owner_id))
    error_message = "The github_owner_id must be the numeric GitHub ID of the owner: gh api users/<owner> --jq .id"
  }
}

variable "tx03v2_repository_id" {
  description = "Numeric GitHub ID of your tx03v2 repository (gh api repos/<owner>/tx03v2 --jq .id)."
  type        = string

  validation {
    condition     = can(regex("^[1-9][0-9]{0,15}$", var.tx03v2_repository_id))
    error_message = "The tx03v2_repository_id must be the numeric ID of the repository: gh api repos/<owner>/tx03v2 --jq .id"
  }
}

variable "dx03v2_repository_id" {
  description = "Numeric GitHub ID of your dx03v2 repository (gh api repos/<owner>/dx03v2 --jq .id)."
  type        = string

  validation {
    condition     = can(regex("^[1-9][0-9]{0,15}$", var.dx03v2_repository_id))
    error_message = "The dx03v2_repository_id must be the numeric ID of the repository: gh api repos/<owner>/dx03v2 --jq .id"
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
  default     = 5

  validation {
    condition     = var.budget_amount >= 1 && var.budget_amount <= 1000 && floor(var.budget_amount) == var.budget_amount
    error_message = "The budget_amount must be a whole number between 1 and 1000."
  }
}

variable "budget_alert_emails" {
  description = "E-mail addresses that receive the budget alerts through monitoring notification channels (1-10), named explicitly: a budget never stops spending, so someone you name must read the alert. The billing account administrators and users receive them as well."
  type        = list(string)

  validation {
    condition     = length(var.budget_alert_emails) >= 1 && length(var.budget_alert_emails) <= 10
    error_message = "Set between 1 and 10 addresses in budget_alert_emails: the alert of a budget must reach someone you name."
  }

  validation {
    condition     = alltrue([for e in var.budget_alert_emails : can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}$", e))])
    error_message = "Every budget_alert_emails entry must be a valid e-mail address, e.g. you@example.com."
  }

  validation {
    condition     = !contains([for e in var.budget_alert_emails : lower(e)], "you@example.com")
    error_message = "Replace the placeholder you@example.com of terraform.tfvars.example with an address you read."
  }
}

variable "apply_extra_project_roles" {
  description = "Extra project roles for tx03v2-gha-apply, only for the case where a real apply fails with PERMISSION_DENIED for a permission that none of the lab roles has (docs/RUNBOOK.md, section 12; the error names the permission). Empty by default. Owner, Project IAM Admin and Service Account roles are refused: the node service account has its own grant, and Editor, the broad role the apply had before the narrowing, stays possible but is a decision you take on purpose."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for r in var.apply_extra_project_roles : can(regex("^roles/[A-Za-z0-9._]+$", r))])
    error_message = "Every apply_extra_project_roles entry must be a predefined role such as roles/compute.admin."
  }

  validation {
    condition     = !anytrue([for r in var.apply_extra_project_roles : can(regex("^roles/(owner|resourcemanager\\.projectIamAdmin|iam\\.service[A-Za-z]*)$", r))])
    error_message = "Owner, Project IAM Admin and the service account roles cannot be added to the apply identity."
  }

  validation {
    condition     = length(distinct(var.apply_extra_project_roles)) == length(var.apply_extra_project_roles)
    error_message = "The apply_extra_project_roles entries must be unique."
  }
}

variable "state_location" {
  description = "Empty keeps the regional default; US/EU/ASIA makes a new state bucket multiregion. Choose at bootstrap, before applying the lab."
  type        = string
  default     = ""
  validation {
    condition     = contains(["", "US", "EU", "ASIA"], var.state_location)
    error_message = "state_location must be empty, US, EU or ASIA. Existing buckets cannot change location in place."
  }
}

variable "state_protection" {
  description = "Refuse to destroy the state bucket (deletion_policy = PREVENT). Set false only for the final teardown."
  type        = bool
  default     = true
}
