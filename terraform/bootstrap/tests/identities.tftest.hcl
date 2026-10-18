# GitHub identities of the contract (docs/CONTRACT.md): the workload identity pool and its GitHub
# OIDC provider (issuer, attribute mapping, condition), the three CI service accounts and one
# roles/iam.workloadIdentityUser grant per exact subject.

mock_provider "google" {
  source = "../tests/mocks"
}

variables {
  github_owner         = "maringelix"
  github_owner_id      = "1000000"
  tx03v2_repository_id = "2000000"
  dx03v2_repository_id = "3000000"
  project_id           = "tx03v2-lab-example"
  billing_account      = "000000-000000-000000"
  budget_alert_emails  = ["lab-alerts@example.org"]
}

# override_resource replaces the mock defaults of the target: each service account gets its own
# name, e-mail and member, so the tests can tell the grants apart.
override_resource {
  target = google_service_account.github["plan"]
  values = {
    name   = "projects/tx03v2-lab-example/serviceAccounts/tx03v2-gha-plan@tx03v2-lab-example.iam.gserviceaccount.com"
    email  = "tx03v2-gha-plan@tx03v2-lab-example.iam.gserviceaccount.com"
    member = "serviceAccount:tx03v2-gha-plan@tx03v2-lab-example.iam.gserviceaccount.com"
  }
}

override_resource {
  target = google_service_account.github["apply"]
  values = {
    name   = "projects/tx03v2-lab-example/serviceAccounts/tx03v2-gha-apply@tx03v2-lab-example.iam.gserviceaccount.com"
    email  = "tx03v2-gha-apply@tx03v2-lab-example.iam.gserviceaccount.com"
    member = "serviceAccount:tx03v2-gha-apply@tx03v2-lab-example.iam.gserviceaccount.com"
  }
}

override_resource {
  target = google_service_account.github["deploy"]
  values = {
    name   = "projects/tx03v2-lab-example/serviceAccounts/dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
    email  = "dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
    member = "serviceAccount:dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
  }
}

run "pool_and_provider_follow_the_contract" {
  command = apply

  assert {
    condition     = google_iam_workload_identity_pool.github.workload_identity_pool_id == "tx03v2-github"
    error_message = "The workload identity pool must be tx03v2-github (contract)."
  }

  assert {
    condition = (
      google_iam_workload_identity_pool_provider.github.workload_identity_pool_id == "tx03v2-github" &&
      google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id == "github" &&
      google_iam_workload_identity_pool_provider.github.oidc[0].issuer_uri == "https://token.actions.githubusercontent.com"
    )
    error_message = "The provider must be tx03v2-github/github with the GitHub Actions issuer."
  }

  assert {
    condition = google_iam_workload_identity_pool_provider.github.attribute_mapping == tomap({
      "google.subject"             = "assertion.sub"
      "attribute.repository"       = "assertion.repository"
      "attribute.repository_owner" = "assertion.repository_owner"
    })
    error_message = "The attribute mapping must be exactly google.subject, repository and repository_owner."
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.repository_owner_id == '1000000' && assertion.repository_id in ['2000000', '3000000']"
    error_message = "The provider condition must admit only the two lab repositories of the owner, by the numeric IDs (a re-registered account or repository name gets other IDs), never the whole owner."
  }

  assert {
    condition     = output.workload_identity_provider == "projects/000000000000/locations/global/workloadIdentityPools/tx03v2-github/providers/github"
    error_message = "workload_identity_provider becomes the GitHub variable GCP_WORKLOAD_IDENTITY_PROVIDER: projects/<number>/locations/global/workloadIdentityPools/tx03v2-github/providers/github."
  }
}

run "one_grant_per_exact_subject" {
  command = apply

  assert {
    condition = { for k, s in google_service_account.github : k => s.account_id } == {
      plan   = "tx03v2-gha-plan"
      apply  = "tx03v2-gha-apply"
      deploy = "dx03v2-gha-deploy"
    }
    error_message = "The three CI service accounts of the contract: tx03v2-gha-plan, tx03v2-gha-apply, dx03v2-gha-deploy."
  }

  assert {
    condition = { for k, g in google_service_account_iam_member.workload_identity_user : k => "${g.service_account_id} ${g.member}" } == {
      plan_pull_request = "projects/tx03v2-lab-example/serviceAccounts/tx03v2-gha-plan@tx03v2-lab-example.iam.gserviceaccount.com principal://iam.googleapis.com/projects/000000000000/locations/global/workloadIdentityPools/tx03v2-github/subject/repo:maringelix@1000000/tx03v2@2000000:pull_request"
      plan_main         = "projects/tx03v2-lab-example/serviceAccounts/tx03v2-gha-plan@tx03v2-lab-example.iam.gserviceaccount.com principal://iam.googleapis.com/projects/000000000000/locations/global/workloadIdentityPools/tx03v2-github/subject/repo:maringelix@1000000/tx03v2@2000000:ref:refs/heads/main"
      apply_lab         = "projects/tx03v2-lab-example/serviceAccounts/tx03v2-gha-apply@tx03v2-lab-example.iam.gserviceaccount.com principal://iam.googleapis.com/projects/000000000000/locations/global/workloadIdentityPools/tx03v2-github/subject/repo:maringelix@1000000/tx03v2@2000000:environment:lab"
      deploy_lab        = "projects/tx03v2-lab-example/serviceAccounts/dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com principal://iam.googleapis.com/projects/000000000000/locations/global/workloadIdentityPools/tx03v2-github/subject/repo:maringelix@1000000/dx03v2@3000000:environment:lab"
    }
    error_message = "Each service account may be impersonated only by its exact subjects, in the immutable format with the owner and repository IDs (plan: pull requests and main; apply and deploy: environment lab of their repository)."
  }

  assert {
    condition     = alltrue([for g in google_service_account_iam_member.workload_identity_user : g.role == "roles/iam.workloadIdentityUser" && !strcontains(g.member, "principalSet") && !strcontains(g.member, "*")])
    error_message = "Only roles/iam.workloadIdentityUser, only principal:// subjects (no principalSet, no wildcard)."
  }

  assert {
    condition = (
      output.plan_service_account == "tx03v2-gha-plan@tx03v2-lab-example.iam.gserviceaccount.com" &&
      output.apply_service_account == "tx03v2-gha-apply@tx03v2-lab-example.iam.gserviceaccount.com" &&
      output.deploy_service_account == "dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com" &&
      output.github_variables_dx03v2 == {
        GCP_PROJECT_ID                 = "tx03v2-lab-example"
        GCP_WORKLOAD_IDENTITY_PROVIDER = "projects/000000000000/locations/global/workloadIdentityPools/tx03v2-github/providers/github"
        GCP_DEPLOY_SERVICE_ACCOUNT     = "dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
      }
    )
    error_message = "The outputs must give the GitHub variables of tx03v2 and dx03v2."
  }
}

run "owner_is_configurable" {
  command = apply

  variables {
    github_owner         = "example-org"
    github_owner_id      = "42"
    tx03v2_repository_id = "4300"
    dx03v2_repository_id = "4400"
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.repository_owner_id == '42' && assertion.repository_id in ['4300', '4400']"
    error_message = "A fork owner must get a condition with its own IDs."
  }

  assert {
    condition = alltrue([
      for g in google_service_account_iam_member.workload_identity_user :
      strcontains(g.member, "/subject/repo:example-org@42/tx03v2@4300:") || strcontains(g.member, "/subject/repo:example-org@42/dx03v2@4400:")
    ])
    error_message = "Every subject must use github_owner, github_owner_id and the repository IDs."
  }
}

run "the_ids_are_numeric" {
  command = plan

  variables {
    dx03v2_repository_id = "dx03v2"
  }

  expect_failures = [var.dx03v2_repository_id]
}

run "rejects_an_invalid_owner" {
  command = plan

  variables {
    github_owner = "bad owner"
  }

  expect_failures = [var.github_owner]
}

run "placeholder_owner_is_refused" {
  command = plan

  variables {
    github_owner = "your-github-user"
  }

  expect_failures = [var.github_owner]
}
