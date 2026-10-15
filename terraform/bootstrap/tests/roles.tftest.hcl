# Roles of the GitHub service accounts: least privilege for the plan identity, the apply identity
# limited by an IAM condition to the project roles of modules/project-roles (the same list the lab
# root grants; terraform/envs/lab/tests/roles.tftest.hcl proves the other side), nothing for the
# deployer here.

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

run "plan_identity_is_read_only" {
  command = apply

  assert {
    condition = { for k, m in google_project_iam_member.plan : k => "${m.project} ${m.member}" } == {
      "roles/iam.securityReviewer"             = "tx03v2-lab-example serviceAccount:tx03v2-gha-plan@tx03v2-lab-example.iam.gserviceaccount.com"
      "roles/parametermanager.parameterViewer" = "tx03v2-lab-example serviceAccount:tx03v2-gha-plan@tx03v2-lab-example.iam.gserviceaccount.com"
      "roles/viewer"                           = "tx03v2-lab-example serviceAccount:tx03v2-gha-plan@tx03v2-lab-example.iam.gserviceaccount.com"
    }
    error_message = "tx03v2-gha-plan gets exactly Viewer, Security Reviewer and Parameter Viewer on the project (what the refresh reads)."
  }

  assert {
    condition = (
      google_storage_bucket_iam_member.plan_state.bucket == "tx03v2-tfstate-f1bea338" &&
      google_storage_bucket_iam_member.plan_state.role == "roles/storage.objectViewer" &&
      google_storage_bucket_iam_member.plan_state.member == "serviceAccount:tx03v2-gha-plan@tx03v2-lab-example.iam.gserviceaccount.com"
    )
    error_message = "tx03v2-gha-plan only reads the state bucket (plans run with -lock=false)."
  }

  assert {
    condition = alltrue([
      for m in google_project_iam_member.plan :
      !can(regex("(admin|editor|owner|Admin|User|Creator|Accessor)$", m.role))
    ])
    error_message = "The plan identity must not get any write, impersonation or secret access role."
  }
}

run "apply_identity_grants_only_the_lab_project_roles" {
  command = apply

  assert {
    condition = toset(keys(google_project_iam_member.apply)) == toset([
      "roles/artifactregistry.admin",
      "roles/container.admin",
      "roles/editor",
      "roles/iam.serviceAccountUser",
      "roles/parametermanager.admin",
      "roles/secretmanager.admin",
    ])
    error_message = "tx03v2-gha-apply gets exactly Editor plus the admin roles Editor lacks and Service Account User."
  }

  assert {
    condition     = alltrue([for m in google_project_iam_member.apply : m.member == "serviceAccount:tx03v2-gha-apply@tx03v2-lab-example.iam.gserviceaccount.com" && m.project == "tx03v2-lab-example"])
    error_message = "Apply roles must go to tx03v2-gha-apply, on the lab project."
  }

  assert {
    condition = (
      google_storage_bucket_iam_member.apply_state.bucket == "tx03v2-tfstate-f1bea338" &&
      google_storage_bucket_iam_member.apply_state.role == "roles/storage.objectUser" &&
      google_storage_bucket_iam_member.apply_state.member == "serviceAccount:tx03v2-gha-apply@tx03v2-lab-example.iam.gserviceaccount.com"
    )
    error_message = "tx03v2-gha-apply reads and writes the state objects (and the lock object), nothing else of the bucket."
  }

  assert {
    condition = (
      google_project_iam_member.apply_project_iam_admin.role == "roles/resourcemanager.projectIamAdmin" &&
      google_project_iam_member.apply_project_iam_admin.member == "serviceAccount:tx03v2-gha-apply@tx03v2-lab-example.iam.gserviceaccount.com" &&
      google_project_iam_member.apply_project_iam_admin.condition[0].expression == "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly(['roles/cloudtrace.agent', 'roles/container.clusterViewer', 'roles/container.defaultNodeServiceAccount', 'roles/parametermanager.parameterAccessor'])"
    )
    error_message = "Project IAM Admin only with the modifiedGrantsByRole condition listing the lab project roles."
  }

  assert {
    # The list inside hasOnly([...]) equals modules/project-roles, element by element.
    condition = toset([
      for m in regexall("'(roles/[A-Za-z.]+)'", regex("hasOnly\\(\\[(.*)\\]\\)", google_project_iam_member.apply_project_iam_admin.condition[0].expression)[0]) : m[0]
    ]) == toset(module.project_roles.lab_project_roles)
    error_message = "The roles in the IAM condition must equal the project roles the lab root grants."
  }

  assert {
    condition = alltrue([
      for forbidden in [
        "roles/owner",
        "roles/editor",
        "roles/resourcemanager.projectIamAdmin",
        "roles/iam.securityAdmin",
        "roles/iam.serviceAccountAdmin",
        "roles/iam.serviceAccountTokenCreator",
        "roles/iam.serviceAccountUser",
        "roles/iam.workloadIdentityUser",
        "roles/container.admin",
        "roles/secretmanager.secretAccessor",
      ] : !strcontains(google_project_iam_member.apply_project_iam_admin.condition[0].expression, "'${forbidden}'")
    ])
    error_message = "The apply identity must never be able to grant Owner, Editor, IAM administration, impersonation, cluster admin or secret access."
  }
}

run "nothing_for_the_deployer_and_no_owner" {
  command = apply

  assert {
    condition = alltrue([
      for m in concat(values(google_project_iam_member.plan), values(google_project_iam_member.apply), [google_project_iam_member.apply_project_iam_admin]) :
      m.member != "serviceAccount:dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
    ])
    error_message = "dx03v2-gha-deploy gets its roles from the lab root, on lab resources only (contract)."
  }

  assert {
    condition = alltrue([
      for m in concat(values(google_project_iam_member.plan), values(google_project_iam_member.apply), [google_project_iam_member.apply_project_iam_admin]) :
      m.role != "roles/owner"
    ])
    error_message = "No identity of the lab gets roles/owner."
  }
}
