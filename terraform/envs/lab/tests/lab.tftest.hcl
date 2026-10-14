# Root-level wiring of the lab: lab-friendly defaults, contract names, the contract keys published
# in the Parameter Manager parameter and the outputs dx03v2 and platform/install.sh consume.

mock_provider "google" {
  source = "../../tests/mocks"
}

variables {
  github_owner           = "maringelix"
  project_id             = "tx03v2-lab-example"
  deploy_service_account = "dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
}

run "defaults_are_lab_friendly" {
  command = plan

  assert {
    condition     = var.region == "us-central1" && var.enable_waf
    error_message = "Defaults: us-central1 and WAF on (parity with tx01v2 and tx02v2). github_owner has no default: the workflows pass github.repository_owner."
  }

  assert {
    condition     = var.db_tier == "db-g1-small" && var.db_password_version == 1 && var.admin_token_version == 1
    error_message = "Cloud SQL defaults to db-g1-small (50 connections); secrets start at version 1."
  }

  assert {
    condition     = var.nodes_subnet_cidr == "10.30.0.0/20" && var.pods_cidr == "10.32.0.0/16" && var.services_cidr == "10.33.0.0/20"
    error_message = "Network defaults changed: update docs/CONTRATO.md and dx03v2 together."
  }

  assert {
    condition     = length(var.app_deployer_members) == 0
    error_message = "No extra deployer by default."
  }

  assert {
    condition     = local.name == "tx03v2-lab" && local.project_number == "000000000000"
    error_message = "Prefix tx03v2-lab (contract); the project number comes from the project data source."
  }

  assert {
    condition     = local.eso_principal == "principal://iam.googleapis.com/projects/000000000000/locations/global/workloadIdentityPools/tx03v2-lab-example.svc.id.goog/subject/ns/external-secrets/sa/external-secrets"
    error_message = "The ESO principal is the ServiceAccount external-secrets/external-secrets of the cluster workload pool (contract)."
  }
}

run "contract_keys_in_the_parameter" {
  command = apply

  assert {
    condition = module.contract.keys == sort([
      "project-id",
      "region",
      "cluster-name",
      "network-name",
      "nodes-subnet-cidr",
      "db/endpoint-ip",
      "lb-source-ranges",
      "artifact-registry/repository",
      "db/secret-name",
      "app/admin-token-secret-name",
      "eso/cluster-secret-store",
      "gateway/address-name",
      "gateway/address",
      "waf/security-policy",
      "deploy/service-account",
    ])
    error_message = "The lab must publish exactly the fifteen contract keys."
  }

  assert {
    condition = local.contract_keys == {
      "project-id"                   = "tx03v2-lab-example"
      "region"                       = "us-central1"
      "cluster-name"                 = "tx03v2-lab"
      "network-name"                 = "tx03v2-lab"
      "nodes-subnet-cidr"            = "10.30.0.0/20"
      "db/endpoint-ip"               = "10.30.0.5"
      "lb-source-ranges"             = "35.191.0.0/16,130.211.0.0/22"
      "artifact-registry/repository" = "us-central1-docker.pkg.dev/tx03v2-lab-example/dx03v2"
      "db/secret-name"               = "tx03v2-lab-db-app"
      "app/admin-token-secret-name"  = "tx03v2-lab-app-admin-token"
      "eso/cluster-secret-store"     = "gcp-secret-manager"
      "gateway/address-name"         = "tx03v2-lab-gateway"
      "gateway/address"              = "203.0.113.10"
      "waf/security-policy"          = "tx03v2-lab-waf"
      "deploy/service-account"       = "dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
    }
    error_message = "Contract values must come from the modules and match docs/CONTRATO.md."
  }

  assert {
    condition     = module.contract.parameter_id == "tx03v2-lab-contract" && output.contract_parameter == "tx03v2-lab-contract"
    error_message = "The contract parameter is tx03v2-lab-contract (dx03v2 renders its latest version)."
  }

  assert {
    condition = (
      module.contract.json == jsonencode(local.contract_keys) &&
      module.contract.version_id == "c-${substr(sha256(jsonencode(local.contract_keys)), 0, 16)}" &&
      can(regex("^c-[0-9a-f]{16}$", module.contract.version_id))
    )
    error_message = "The live version holds the contract JSON and its ID is derived from the content."
  }

  assert {
    condition     = alltrue([for v in values(local.contract_keys) : v != "" && !strcontains(v, "\n")])
    error_message = "Every contract value is a non-empty single-line string."
  }

  assert {
    condition     = output.get_credentials_command == "gcloud container clusters get-credentials tx03v2-lab --location us-central1 --project tx03v2-lab-example --dns-endpoint"
    error_message = "get_credentials_command must use the DNS-based endpoint (the IP endpoint is private)."
  }

  assert {
    condition = (
      output.artifact_registry_repository == "us-central1-docker.pkg.dev/tx03v2-lab-example/dx03v2" &&
      output.gateway_address == "203.0.113.10" &&
      output.waf_security_policy == "tx03v2-lab-waf" &&
      output.db_endpoint_ip == "10.30.0.5" &&
      can(regex("^tx03v2-lab-[0-9a-f]{4}$", output.cloudsql_instance_name))
    )
    error_message = "The outputs must repeat the contract values the operator needs."
  }
}

# modules/contract tested directly: a global JSON parameter whose single version holds the JSON.
run "contract_module_publishes_one_json_version" {
  command = apply

  module {
    source = "../../modules/contract"
  }

  variables {
    name   = "tx03v2-lab-contract"
    values = { "a" = "1", "b/c" = "two" }
  }

  assert {
    condition     = google_parameter_manager_parameter.this.parameter_id == "tx03v2-lab-contract" && google_parameter_manager_parameter.this.format == "JSON"
    error_message = "The contract parameter is global and typed JSON (gcloud render validates it)."
  }

  assert {
    condition = (
      google_parameter_manager_parameter_version.this.parameter == google_parameter_manager_parameter.this.id &&
      google_parameter_manager_parameter_version.this.parameter_data == "{\"a\":\"1\",\"b/c\":\"two\"}" &&
      google_parameter_manager_parameter_version.this.parameter_version_id == "c-${substr(sha256("{\"a\":\"1\",\"b/c\":\"two\"}"), 0, 16)}"
    )
    error_message = "One version with the JSON of the values and a content-derived ID."
  }

  assert {
    condition     = output.keys == tolist(["a", "b/c"])
    error_message = "keys lists the published keys, sorted."
  }
}
