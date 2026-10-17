# Negative tests: unsafe or invalid inputs must be rejected before anything is planned. A few
# positive runs prove the validations do not refuse legitimate values.

mock_provider "google" {
  source = "../../tests/mocks"
}

variables {
  github_owner           = "maringelix"
  project_id             = "tx03v2-lab-example"
  deploy_service_account = "dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
}

# --- identifiers ---

run "rejects_a_hostname_without_a_zone" {
  command = plan
  variables {
    app_domain_name = "lab.example.com"
  }
  expect_failures = [var.app_domain_name]
}

run "rejects_an_unrelated_hostname" {
  command = plan
  variables {
    dns_zone_name   = "example.com"
    app_domain_name = "lab.example.org"
  }
  expect_failures = [var.app_domain_name]
}

run "rejects_a_wildcard_domain" {
  command = plan
  variables {
    dns_zone_name   = "example.com"
    app_domain_name = "*.example.com"
  }
  expect_failures = [var.app_domain_name]
}

run "rejects_an_uppercase_project_id" {
  command = plan
  variables {
    project_id = "Tx03v2-Lab-Example"
  }
  expect_failures = [var.project_id]
}

run "rejects_a_short_project_id" {
  command = plan
  variables {
    project_id = "lab"
  }
  expect_failures = [var.project_id]
}

run "rejects_an_invalid_region" {
  command = plan
  variables {
    region = "uscentral"
  }
  expect_failures = [var.region]
}

run "rejects_an_invalid_owner" {
  command = plan
  variables {
    github_owner = "not an owner"
  }
  expect_failures = [var.github_owner]
}

run "rejects_another_service_account_as_deployer" {
  command = plan
  variables {
    deploy_service_account = "tx03v2-gha-apply@tx03v2-lab-example.iam.gserviceaccount.com"
  }
  expect_failures = [var.deploy_service_account]
}

run "rejects_a_deployer_of_another_project" {
  command = plan
  variables {
    deploy_service_account = "dx03v2-gha-deploy@other-lab-project.iam.gserviceaccount.com"
  }
  expect_failures = [var.deploy_service_account]
}

run "rejects_a_member_without_prefix" {
  command = plan
  variables {
    app_deployer_members = ["you@example.com"]
  }
  expect_failures = [var.app_deployer_members]
}

run "rejects_a_group_member" {
  command = plan
  variables {
    app_deployer_members = ["group:team@example.com"]
  }
  expect_failures = [var.app_deployer_members]
}

run "rejects_an_uppercase_member" {
  command = plan
  variables {
    app_deployer_members = ["user:You@Example.com"]
  }
  expect_failures = [var.app_deployer_members]
}

run "rejects_duplicate_members" {
  command = plan
  variables {
    app_deployer_members = ["user:you@example.com", "user:you@example.com"]
  }
  expect_failures = [var.app_deployer_members]
}

run "rejects_the_deploy_account_as_extra_member" {
  command = plan
  variables {
    app_deployer_members = ["serviceAccount:dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"]
  }
  expect_failures = [var.app_deployer_members]
}

run "accepts_users_and_service_accounts" {
  command = plan
  variables {
    app_deployer_members = ["user:you@example.com", "serviceAccount:ci-deployer@tx03v2-lab-example.iam.gserviceaccount.com"]
  }
  assert {
    condition     = length(var.app_deployer_members) == 2
    error_message = "user: and serviceAccount: members are valid deployers."
  }
}

# --- network ---

run "rejects_a_non_canonical_nodes_cidr" {
  command = plan
  variables {
    nodes_subnet_cidr = "10.30.0.1/20"
  }
  expect_failures = [var.nodes_subnet_cidr]
}

run "rejects_a_too_small_nodes_subnet" {
  command = plan
  variables {
    nodes_subnet_cidr = "10.30.0.0/25"
  }
  expect_failures = [var.nodes_subnet_cidr]
}

run "rejects_a_public_nodes_subnet" {
  command = plan
  variables {
    nodes_subnet_cidr = "198.51.100.0/24"
  }
  expect_failures = [var.nodes_subnet_cidr]
}

run "rejects_pods_overlapping_the_nodes" {
  command = plan
  variables {
    pods_cidr = "10.30.0.0/16"
  }
  expect_failures = [var.pods_cidr]
}

run "rejects_a_too_small_pods_range" {
  command = plan
  variables {
    pods_cidr = "10.32.0.0/22"
  }
  expect_failures = [var.pods_cidr]
}

run "rejects_services_overlapping_the_pods" {
  command = plan
  variables {
    services_cidr = "10.32.16.0/20"
  }
  expect_failures = [var.services_cidr]
}

run "rejects_services_overlapping_the_nodes" {
  command = plan
  variables {
    services_cidr = "10.30.0.0/24"
  }
  expect_failures = [var.services_cidr]
}

run "rejects_public_services" {
  command = plan
  variables {
    services_cidr = "192.0.2.0/24"
  }
  expect_failures = [var.services_cidr]
}

run "rejects_a_control_plane_range_that_is_not_a_slash_28" {
  command = plan
  variables {
    control_plane_cidr = "172.31.255.0/24"
  }
  expect_failures = [var.control_plane_cidr]
}

run "rejects_a_public_control_plane_range" {
  command = plan
  variables {
    control_plane_cidr = "192.0.2.0/28"
  }
  expect_failures = [var.control_plane_cidr]
}

run "rejects_a_control_plane_range_inside_the_nodes_subnet" {
  command = plan
  variables {
    control_plane_cidr = "10.30.0.0/28"
  }
  expect_failures = [var.control_plane_cidr]
}

run "accepts_another_private_layout" {
  command = plan
  variables {
    nodes_subnet_cidr = "172.16.0.0/20"
    pods_cidr         = "172.20.0.0/16"
    services_cidr     = "192.168.0.0/20"
  }
  assert {
    condition     = local.contract_keys["nodes-subnet-cidr"] == "172.16.0.0/20"
    error_message = "Any non-overlapping RFC 1918 layout is valid."
  }
}

# --- data stores and secrets ---

run "rejects_db_f1_micro" {
  command = plan
  variables {
    db_tier = "db-f1-micro"
  }
  expect_failures = [var.db_tier]
}

run "rejects_an_enterprise_plus_tier" {
  command = plan
  variables {
    db_tier = "db-perf-optimized-N-2"
  }
  expect_failures = [var.db_tier]
}

run "accepts_a_custom_tier" {
  command = plan
  variables {
    db_tier = "db-custom-1-3840"
  }
  assert {
    condition     = var.db_tier == "db-custom-1-3840"
    error_message = "Custom Enterprise tiers are valid."
  }
}

run "rejects_password_version_zero" {
  command = plan
  variables {
    db_password_version = 0
  }
  expect_failures = [var.db_password_version]
}

run "rejects_a_fractional_token_version" {
  command = plan
  variables {
    admin_token_version = 1.5
  }
  expect_failures = [var.admin_token_version]
}

run "placeholder_owner_is_refused" {
  command = plan

  variables {
    github_owner = "your-github-user"
  }

  expect_failures = [var.github_owner]
}
