# The two managed regions are represented by distinct mocked resources. This tests wiring only;
# no Cloud SQL promotion or regional failover runs against Google Cloud.
mock_provider "google" {
  source = "../../tests/mocks"
  mock_resource "google_certificate_manager_dns_authorization" {
    defaults = {
      dns_resource_record = [{ name = "_acme-challenge.lab.example.com.", type = "CNAME", data = "authorization.example.com." }]
    }
  }
}

variables {
  github_owner           = "maringelix"
  project_id             = "tx03v2-lab-example"
  deploy_service_account = "dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
}

run "core_remains_one_region" {
  command = plan

  assert {
    condition = (
      length(module.network_dr) == 0 &&
      length(module.gke_dr) == 0 &&
      length(module.artifact_registry_dr) == 0 &&
      length(google_sql_database_instance.dr) == 0 &&
      length(module.secrets_dr) == 0 &&
      length(module.contract_dr) == 0
    )
    error_message = "The cheap core profile must not create secondary-region resources."
  }
}

run "ha_is_regional_without_cross_region_replica" {
  command = apply
  variables {
    db_profile = "ha"
  }

  assert {
    condition = (
      length(google_sql_database_instance.dr) == 0 &&
      length(module.gke_dr) == 0 &&
      output.db_profile == "ha" &&
      output.dr_region == ""
    )
    error_message = "HA protects the primary region without adding a cross-region DR bill."
  }
}

run "dr_has_independent_secondary_region" {
  command = apply
  variables {
    db_profile = "dr"
  }

  assert {
    condition = (
      module.network_dr[0].network_name == "tx03v2-lab-dr" &&
      module.gke_dr[0].location == "us-east1" &&
      module.artifact_registry_dr[0].location == "us-east1" &&
      google_sql_database_instance.dr[0].region == "us-east1" &&
      google_sql_database_instance.dr[0].master_instance_name == module.cloudsql.instance_name &&
      google_sql_database_instance.dr[0].instance_type == "READ_REPLICA_INSTANCE" &&
      google_sql_database_instance.dr[0].settings[0].ip_configuration[0].ipv4_enabled == false &&
      google_compute_address.db_dr[0].region == "us-east1" &&
      google_dns_managed_zone.sql_dr[0].dns_name == "us-east1.sql.goog." &&
      output.dr_region == "us-east1" &&
      output.dr_cluster_name == "tx03v2-lab-dr"
    )
    error_message = "DR needs a second region, isolated VPC/GKE, PSC-only Cloud SQL replica and DNS."
  }

  assert {
    condition = (
      module.secrets_dr[0].db_secret_name == "tx03v2-lab-dr-db-app" &&
      module.contract_dr[0].parameter_id != module.contract.parameter_id &&
      module.velero_dr[0].bucket_name != module.velero.bucket_name &&
      length(google_artifact_registry_repository_iam_member.dr) >= 2 &&
      length(google_secret_manager_secret_iam_member.eso_dr) == 2
    )
    error_message = "Secondary secrets, registry grants, contract and Velero bucket must be independent."
  }
}

run "full_dr_mesh_backup_and_dns" {
  command = apply
  variables {
    db_profile          = "dr"
    active_region       = "secondary"
    enable_managed_mesh = true
    dns_zone_name       = "example.com"
    app_domain_name     = "lab.example.com"
  }
  assert {
    condition = (
      google_gke_hub_membership.dr[0].membership_id == "tx03v2-lab-dr" &&
      google_gke_hub_membership.dr[0].location == "us-east1" &&
      google_gke_hub_feature_membership.mesh_dr[0].mesh[0].management == "MANAGEMENT_AUTOMATIC" &&
      one(google_dns_record_set.app[0].rrdatas) == module.network_dr[0].gateway_address &&
      google_storage_bucket_iam_member.velero_dr_recovery[0].role == "roles/storage.objectViewer" &&
      module.velero.bucket_location == "US" &&
      module.velero_dr[0].bucket_location == "us-east1" &&
      endswith(google_storage_bucket_iam_member.velero_dr_recovery[0].member, "/sa/velero-dr")
    )
    error_message = "Full DR needs an independent mesh membership, explicit DNS cutover and read-only recovery identity."
  }
}

run "secondary_dns_without_dr_is_rejected" {
  command = plan
  variables {
    active_region = "secondary"
  }
  expect_failures = [var.active_region]
}

run "dr_outside_supported_backup_geography_is_rejected" {
  command = plan
  variables {
    db_profile = "dr"
    dr_region  = "europe-west1"
  }
  expect_failures = [var.dr_region]
}
