# The two managed regions are represented by distinct mocked resources. This tests wiring only;
# no Cloud SQL promotion or regional failover runs against Google Cloud.
mock_provider "google" {
  source = "../../tests/mocks"
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
