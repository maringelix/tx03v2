# GitHub identities of the contract (docs/CONTRATO.md): the workload identity pool and its GitHub
# OIDC provider (issuer, attribute mapping, condition), the three CI service accounts and one
# roles/iam.workloadIdentityUser grant per exact subject.

mock_provider "google" {
  source = "../tests/mocks"
}

variables {
  github_owner    = "maringelix"
  project_id      = "tx03v2-lab-example"
  billing_account = "000000-000000-000000"
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
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.repository_owner == 'maringelix' && assertion.repository in ['maringelix/tx03v2', 'maringelix/dx03v2']"
    error_message = "The provider condition must admit only the two lab repositories of the owner (never the whole owner)."
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
      plan_pull_request = "projects/tx03v2-lab-example/serviceAccounts/tx03v2-gha-plan@tx03v2-lab-example.iam.gserviceaccount.com principal://iam.googleapis.com/projects/000000000000/locations/global/workloadIdentityPools/tx03v2-github/subject/repo:maringelix/tx03v2:pull_request"
      plan_main         = "projects/tx03v2-lab-example/serviceAccounts/tx03v2-gha-plan@tx03v2-lab-example.iam.gserviceaccount.com principal://iam.googleapis.com/projects/000000000000/locations/global/workloadIdentityPools/tx03v2-github/subject/repo:maringelix/tx03v2:ref:refs/heads/main"
      apply_lab         = "projects/tx03v2-lab-example/serviceAccounts/tx03v2-gha-apply@tx03v2-lab-example.iam.gserviceaccount.com principal://iam.googleapis.com/projects/000000000000/locations/global/workloadIdentityPools/tx03v2-github/subject/repo:maringelix/tx03v2:environment:lab"
      deploy_lab        = "projects/tx03v2-lab-example/serviceAccounts/dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com principal://iam.googleapis.com/projects/000000000000/locations/global/workloadIdentityPools/tx03v2-github/subject/repo:maringelix/dx03v2:environment:lab"
    }
    error_message = "Each service account may be impersonated only by its exact subjects (plan: pull requests and main; apply and deploy: environment lab of their repository)."
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
    github_owner = "example-org"
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.repository_owner == 'example-org' && assertion.repository in ['example-org/tx03v2', 'example-org/dx03v2']"
    error_message = "A fork owner must get a condition with its own repositories."
  }

  assert {
    condition     = alltrue([for g in google_service_account_iam_member.workload_identity_user : strcontains(g.member, "/subject/repo:example-org/")])
    error_message = "Every subject must use github_owner."
  }
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
