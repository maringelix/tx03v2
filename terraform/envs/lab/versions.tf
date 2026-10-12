terraform {
  required_version = ">= 1.11"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.6"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # bucket and prefix come from -backend-config (backend.hcl, see backend.hcl.example). The GCS
  # backend locks the state with a lock object in the bucket; credentials come from the
  # environment (Application Default Credentials or google-github-actions/auth).
  backend "gcs" {}
}
