# APIs of the lab and the remote state bucket: private (uniform access, public access prevention),
# versioned, never force-destroyed and protected from destroy until the final teardown.

mock_provider "google" {
  source = "../tests/mocks"
}

variables {
  project_id      = "tx03v2-lab-example"
  billing_account = "000000-000000-000000"
}

run "apis_are_enabled_and_never_disabled" {
  command = apply

  assert {
    condition = toset(keys(google_project_service.lab)) == toset([
      "artifactregistry.googleapis.com",
      "billingbudgets.googleapis.com",
      "cloudresourcemanager.googleapis.com",
      "compute.googleapis.com",
      "container.googleapis.com",
      "dns.googleapis.com",
      "iam.googleapis.com",
      "iamcredentials.googleapis.com",
      "logging.googleapis.com",
      "monitoring.googleapis.com",
      "parametermanager.googleapis.com",
      "secretmanager.googleapis.com",
      "serviceusage.googleapis.com",
      "sqladmin.googleapis.com",
      "sts.googleapis.com",
    ])
    error_message = "The bootstrap enables exactly the APIs the lab uses (the CI identities cannot enable services)."
  }

  assert {
    condition     = alltrue([for s in google_project_service.lab : s.disable_on_destroy == false && s.project == "tx03v2-lab-example"])
    error_message = "Tearing down the bootstrap must never turn an API off."
  }
}

run "state_bucket_is_private_versioned_and_protected" {
  command = apply

  assert {
    condition = (
      google_storage_bucket.state.name == "tx03v2-tfstate-f1bea338" &&
      google_storage_bucket.state.location == "US-CENTRAL1" &&
      google_storage_bucket.state.storage_class == "STANDARD"
    )
    error_message = "State bucket tx03v2-tfstate-<substr(sha1(project_id), 0, 8)> in the lab region (contract)."
  }

  assert {
    condition = (
      google_storage_bucket.state.uniform_bucket_level_access == true &&
      google_storage_bucket.state.public_access_prevention == "enforced"
    )
    error_message = "The state bucket must use IAM only (no ACLs) and enforce public access prevention."
  }

  assert {
    condition     = google_storage_bucket.state.versioning[0].enabled == true
    error_message = "State versions must be kept (recovery from a bad apply)."
  }

  assert {
    # action and condition are sets of one element each: one(...) reads that element.
    condition = (
      length(google_storage_bucket.state.lifecycle_rule) == 1 &&
      one(google_storage_bucket.state.lifecycle_rule[0].action).type == "Delete" &&
      one(google_storage_bucket.state.lifecycle_rule[0].condition).days_since_noncurrent_time == 30 &&
      one(google_storage_bucket.state.lifecycle_rule[0].condition).with_state == "ARCHIVED"
    )
    error_message = "Only noncurrent state versions older than 30 days are deleted."
  }

  assert {
    condition     = google_storage_bucket.state.force_destroy == false && google_storage_bucket.state.deletion_policy == "PREVENT"
    error_message = "By default the bucket refuses any destroy and is never emptied by Terraform."
  }

  assert {
    condition     = output.state_bucket_name == "tx03v2-tfstate-f1bea338" && output.backend_hcl == "bucket = \"tx03v2-tfstate-f1bea338\"\nprefix = \"envs/lab\"\n"
    error_message = "backend_hcl must be the ready content of terraform/envs/lab/backend.hcl."
  }
}

run "final_teardown_lifts_the_protection" {
  command = apply

  variables {
    state_protection = false
  }

  assert {
    condition     = google_storage_bucket.state.deletion_policy == "DELETE" && google_storage_bucket.state.force_destroy == false
    error_message = "state_protection = false allows the destroy, but the bucket must still be emptied by hand (force_destroy stays false)."
  }
}

run "suffix_follows_the_project" {
  command = plan

  variables {
    project_id = "other-lab-project"
  }

  assert {
    condition     = local.suffix == "9a5296d0" && local.state_bucket_name == "tx03v2-tfstate-9a5296d0"
    error_message = "The suffix is substr(sha1(project_id), 0, 8): deterministic, no random."
  }
}

run "rejects_an_invalid_project_id" {
  command = plan

  variables {
    project_id = "Tx03v2_Lab"
  }

  expect_failures = [var.project_id]
}

run "rejects_an_invalid_region" {
  command = plan

  variables {
    region = "US Central"
  }

  expect_failures = [var.region]
}
