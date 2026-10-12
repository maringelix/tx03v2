terraform {
  required_version = ">= 1.11"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.6"
    }
  }
  # Local state on purpose: this root creates the state bucket itself. Keep terraform.tfstate
  # (git-ignored) safe, or migrate it into the bucket afterwards (docs/RUNBOOK.md).
}
