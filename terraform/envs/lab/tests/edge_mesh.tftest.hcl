# R8 full-profile edge and managed mesh. The mocked provider never contacts Google Cloud; real
# certificate issuance and Cloud Service Mesh readiness belong to a separately authorized run.
mock_provider "google" {
  source = "../../tests/mocks"
}

variables {
  github_owner           = "maringelix"
  project_id             = "tx03v2-lab-example"
  deploy_service_account = "dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
}

run "core_has_no_public_domain_or_managed_mesh" {
  command = plan

  assert {
    condition = (
      length(google_dns_managed_zone.app) == 0 &&
      length(google_certificate_manager_certificate_map.app) == 0 &&
      length(google_gke_hub_membership.lab) == 0 &&
      local.contract_keys["dns/hostname"] == "disabled" &&
      local.contract_keys["dns/certificate-map"] == "disabled" &&
      local.contract_keys["mesh/management"] == "disabled"
    )
    error_message = "Core must not allocate public DNS/certificates or the managed mesh."
  }
}

run "full_has_delegated_dns_certificate_map_and_autopilot_mesh" {
  command = plan

  variables {
    dns_zone_name       = "example.com"
    app_domain_name     = "lab.example.com"
    enable_managed_mesh = true
  }

  assert {
    condition = (
      google_dns_managed_zone.app[0].dns_name == "example.com." &&
      google_dns_record_set.app[0].name == "lab.example.com." &&
      google_dns_record_set.app[0].type == "A" &&
      google_certificate_manager_dns_authorization.app[0].domain == "lab.example.com" &&
      one(google_certificate_manager_certificate.app[0].managed[0].domains) == "lab.example.com" &&
      google_certificate_manager_certificate_map_entry.app[0].hostname == "lab.example.com" &&
      local.contract_keys["dns/hostname"] == "lab.example.com" &&
      local.contract_keys["dns/certificate-map"] == "tx03v2-lab-app"
    )
    error_message = "Full must publish A and ACME authorization records, a managed certificate and a Certificate Map for the app hostname."
  }

  assert {
    condition = (
      google_gke_hub_membership.lab[0].membership_id == "tx03v2-lab" &&
      google_gke_hub_membership.lab[0].location == "us-central1" &&
      google_gke_hub_feature.mesh[0].name == "servicemesh" &&
      google_gke_hub_feature_membership.mesh[0].mesh[0].management == "MANAGEMENT_AUTOMATIC" &&
      local.contract_keys["mesh/management"] == "managed"
    )
    error_message = "Full must register the GKE Autopilot cluster in the fleet and enable managed Cloud Service Mesh."
  }
}
