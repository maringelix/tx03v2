# Shared mock data for `terraform test` (mock_provider "google" { source = ".../tests/mocks" }).
# No Google Cloud API is ever contacted. Identifiers use the placeholder project tx03v2-lab-example,
# project number 000000000000 and documentation addresses. Computed values the configuration feeds
# back into validated arguments (service account names, network and subnet IDs, DNS names) are well
# formed here; everything else gets the random strings of the mock provider (unique per instance).
# Every instance of a type gets the same default: tests that compare instances use
# override_resource to give the instances under test distinct values.

mock_data "google_project" {
  defaults = {
    project_id = "tx03v2-lab-example"
    number     = "000000000000"
    name       = "tx03v2-lab-example"
  }
}

# Account IDs have 6-30 characters: the provider validates the name of every service account a
# grant points to.
mock_resource "google_service_account" {
  defaults = {
    name      = "projects/tx03v2-lab-example/serviceAccounts/mock-sa@tx03v2-lab-example.iam.gserviceaccount.com"
    email     = "mock-sa@tx03v2-lab-example.iam.gserviceaccount.com"
    member    = "serviceAccount:mock-sa@tx03v2-lab-example.iam.gserviceaccount.com"
    unique_id = "100000000000000000001"
  }
}

mock_resource "google_iam_workload_identity_pool" {
  defaults = {
    name = "projects/000000000000/locations/global/workloadIdentityPools/tx03v2-github"
  }
}

mock_resource "google_iam_workload_identity_pool_provider" {
  defaults = {
    name = "projects/000000000000/locations/global/workloadIdentityPools/tx03v2-github/providers/github"
  }
}

mock_resource "google_storage_bucket" {
  defaults = {
    url       = "gs://tx03v2-tfstate-f1bea338"
    self_link = "https://www.googleapis.com/storage/v1/b/tx03v2-tfstate-f1bea338"
  }
}

mock_resource "google_monitoring_notification_channel" {
  defaults = {
    id   = "projects/tx03v2-lab-example/notificationChannels/1000000000000000001"
    name = "projects/tx03v2-lab-example/notificationChannels/1000000000000000001"
  }
}

mock_resource "google_billing_budget" {
  defaults = {
    name = "billingAccounts/000000-000000-000000/budgets/00000000-0000-0000-0000-000000000000"
  }
}

mock_resource "google_compute_network" {
  defaults = {
    id        = "projects/tx03v2-lab-example/global/networks/tx03v2-lab"
    self_link = "https://www.googleapis.com/compute/v1/projects/tx03v2-lab-example/global/networks/tx03v2-lab"
  }
}

mock_resource "google_compute_subnetwork" {
  defaults = {
    id        = "projects/tx03v2-lab-example/regions/us-central1/subnetworks/tx03v2-lab-nodes"
    self_link = "https://www.googleapis.com/compute/v1/projects/tx03v2-lab-example/regions/us-central1/subnetworks/tx03v2-lab-nodes"
  }
}

mock_resource "google_compute_router" {
  defaults = {
    id = "projects/tx03v2-lab-example/regions/us-central1/routers/tx03v2-lab"
  }
}

mock_resource "google_compute_global_address" {
  defaults = {
    id      = "projects/tx03v2-lab-example/global/addresses/tx03v2-lab-gateway"
    address = "203.0.113.10"
  }
}

mock_resource "google_compute_address" {
  defaults = {
    id      = "projects/tx03v2-lab-example/regions/us-central1/addresses/tx03v2-lab-db"
    address = "10.30.0.5"
  }
}

mock_resource "google_sql_database_instance" {
  defaults = {
    dns_name                    = "0a1b2c3d4e5f.example.us-central1.sql.goog."
    psc_service_attachment_link = "projects/example-tenant-project/regions/us-central1/serviceAttachments/a-000000000000-psc-service-attachment-0000000000000000"
    connection_name             = "tx03v2-lab-example:us-central1:tx03v2-lab-0000"
    self_link                   = "https://sqladmin.googleapis.com/sql/v1beta4/projects/tx03v2-lab-example/instances/tx03v2-lab-0000"
  }
}

mock_resource "google_dns_managed_zone" {
  defaults = {
    id = "projects/tx03v2-lab-example/managedZones/tx03v2-lab-sql"
  }
}

mock_resource "google_container_cluster" {
  defaults = {
    id       = "projects/tx03v2-lab-example/locations/us-central1/clusters/tx03v2-lab"
    endpoint = "10.30.0.2"
  }
}

mock_resource "google_artifact_registry_repository" {
  defaults = {
    id   = "projects/tx03v2-lab-example/locations/us-central1/repositories/dx03v2"
    name = "dx03v2"
  }
}

mock_resource "google_secret_manager_secret" {
  defaults = {
    id   = "projects/tx03v2-lab-example/secrets/mock"
    name = "projects/000000000000/secrets/mock"
  }
}

mock_resource "google_parameter_manager_parameter" {
  defaults = {
    id   = "projects/tx03v2-lab-example/locations/global/parameters/tx03v2-lab-contract"
    name = "projects/tx03v2-lab-example/locations/global/parameters/tx03v2-lab-contract"
  }
}

mock_resource "google_compute_security_policy" {
  defaults = {
    id        = "projects/tx03v2-lab-example/global/securityPolicies/tx03v2-lab-waf"
    self_link = "https://www.googleapis.com/compute/v1/projects/tx03v2-lab-example/global/securityPolicies/tx03v2-lab-waf"
  }
}
