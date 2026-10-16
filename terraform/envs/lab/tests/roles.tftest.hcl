# Every IAM grant of the lab: project roles only from modules/project-roles (the same list the IAM
# condition of tx03v2-gha-apply allows; terraform/bootstrap/tests/roles.tftest.hcl proves the other
# side), the deployer roles of the contract (also for app_deployer_members), the node service
# account and the ESO principal on exactly the two lab secrets.

mock_provider "google" {
  source = "../../tests/mocks"
}

variables {
  github_owner           = "maringelix"
  project_id             = "tx03v2-lab-example"
  deploy_service_account = "dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
  app_deployer_members   = ["user:you@example.com"]
}

override_resource {
  target = module.secrets.google_secret_manager_secret.db
  values = {
    id = "projects/tx03v2-lab-example/secrets/tx03v2-lab-db-app"
  }
}

override_resource {
  target = module.secrets.google_secret_manager_secret.admin_token
  values = {
    id = "projects/tx03v2-lab-example/secrets/tx03v2-lab-app-admin-token"
  }
}

run "project_grants_follow_the_contract" {
  command = apply

  assert {
    condition = { for k, g in google_project_iam_member.lab : k => "${g.role} ${g.member}" } == {
      "nodes-default-node-service-account"                   = "roles/container.defaultNodeServiceAccount serviceAccount:tx03v2-lab-nodes@tx03v2-lab-example.iam.gserviceaccount.com"
      "deploy-cluster-viewer"                                = "roles/container.clusterViewer serviceAccount:dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
      "deploy-parameter-accessor"                            = "roles/parametermanager.parameterAccessor serviceAccount:dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
      "app-deployer-user:you@example.com-cluster-viewer"     = "roles/container.clusterViewer user:you@example.com"
      "app-deployer-user:you@example.com-parameter-accessor" = "roles/parametermanager.parameterAccessor user:you@example.com"
    }
    error_message = "Project grants: the node role, and Cluster Viewer + Parameter Accessor for every deployer (nothing else)."
  }

  assert {
    condition     = alltrue([for g in google_project_iam_member.lab : g.project == "tx03v2-lab-example"])
    error_message = "Every project grant targets the lab project."
  }

  assert {
    # Both directions: every project role the lab grants is in the shared list, and every role of
    # the list is used (an unused entry would widen the IAM condition of tx03v2-gha-apply for nothing).
    condition     = toset(concat([for g in google_project_iam_member.lab : g.role], [google_project_iam_member.otel.role])) == toset(module.project_roles.lab_project_roles)
    error_message = "The project roles of the lab must equal modules/project-roles."
  }

  assert {
    condition = alltrue([
      for g in concat(values(google_project_iam_member.lab), [google_project_iam_member.otel]) :
      !contains(["roles/owner", "roles/editor", "roles/container.admin", "roles/container.developer", "roles/secretmanager.secretAccessor"], g.role)
    ])
    error_message = "No broad or secret-reading project role in the lab."
  }

  assert {
    condition = (
      google_project_iam_member.otel.project == "tx03v2-lab-example" &&
      google_project_iam_member.otel.role == "roles/cloudtrace.agent" &&
      google_project_iam_member.otel.member == "principal://iam.googleapis.com/projects/000000000000/locations/global/workloadIdentityPools/tx03v2-lab-example.svc.id.goog/subject/ns/observability/sa/opentelemetry-collector"
    )
    error_message = "Cloud Trace Agent goes to the Collector ServiceAccount observability/opentelemetry-collector only (contract v2), no Google service account."
  }
}

run "repository_and_secret_grants" {
  command = apply

  assert {
    condition = { for k, g in google_artifact_registry_repository_iam_member.dx03v2 : k => "${g.repository} ${g.role} ${g.member}" } == {
      "nodes-reader"                             = "dx03v2 roles/artifactregistry.reader serviceAccount:tx03v2-lab-nodes@tx03v2-lab-example.iam.gserviceaccount.com"
      "deploy-writer"                            = "dx03v2 roles/artifactregistry.writer serviceAccount:dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
      "app-deployer-user:you@example.com-writer" = "dx03v2 roles/artifactregistry.writer user:you@example.com"
    }
    error_message = "Nodes pull from dx03v2; every deployer pushes to dx03v2 only."
  }

  assert {
    condition     = alltrue([for g in google_artifact_registry_repository_iam_member.dx03v2 : g.location == "us-central1" && g.project == "tx03v2-lab-example"])
    error_message = "Repository grants target the dx03v2 repository of the lab region."
  }

  assert {
    condition = { for k, g in google_secret_manager_secret_iam_member.eso : k => "${g.secret_id} ${g.role}" } == {
      "eso-db"          = "projects/tx03v2-lab-example/secrets/tx03v2-lab-db-app roles/secretmanager.secretAccessor"
      "eso-admin-token" = "projects/tx03v2-lab-example/secrets/tx03v2-lab-app-admin-token roles/secretmanager.secretAccessor"
    }
    error_message = "ESO reads exactly the two lab secrets."
  }

  assert {
    condition     = alltrue([for g in google_secret_manager_secret_iam_member.eso : g.member == "principal://iam.googleapis.com/projects/000000000000/locations/global/workloadIdentityPools/tx03v2-lab-example.svc.id.goog/subject/ns/external-secrets/sa/external-secrets"])
    error_message = "The secret grants go to the ESO controller ServiceAccount only (no deployer, no Google service account)."
  }
}

run "no_extra_deployer_by_default" {
  command = apply

  variables {
    app_deployer_members = []
  }

  assert {
    condition = (
      length(google_project_iam_member.lab) == 3 &&
      length(google_artifact_registry_repository_iam_member.dx03v2) == 2 &&
      alltrue([for g in google_project_iam_member.lab : !startswith(g.member, "user:")])
    )
    error_message = "Without app_deployer_members only the node account and dx03v2-gha-deploy get roles."
  }
}
