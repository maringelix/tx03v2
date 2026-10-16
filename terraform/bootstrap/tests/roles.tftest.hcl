# Roles of the GitHub service accounts: least privilege for the plan identity; the apply identity with
# the admin role of each service the lab uses (no Editor, no Secret Manager Admin, no Service Account
# User on the project: roadmap R3.16), a Secret Manager role that cannot read a value, Service Account
# User on the node account only, and project IAM limited by an IAM condition to the project roles of
# modules/project-roles (the same list the lab root grants; terraform/envs/lab/tests/roles.tftest.hcl
# proves the other side); nothing for the deployer here.

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

override_resource {
  target = google_service_account.nodes
  values = {
    name   = "projects/tx03v2-lab-example/serviceAccounts/tx03v2-lab-nodes@tx03v2-lab-example.iam.gserviceaccount.com"
    email  = "tx03v2-lab-nodes@tx03v2-lab-example.iam.gserviceaccount.com"
    member = "serviceAccount:tx03v2-lab-nodes@tx03v2-lab-example.iam.gserviceaccount.com"
  }
}

override_resource {
  target = google_project_iam_custom_role.lab_secrets
  values = {
    id = "projects/tx03v2-lab-example/roles/tx03v2LabSecrets"
  }
}

override_resource {
  target = google_project_iam_custom_role.velero_bucket
  values = {
    id = "projects/tx03v2-lab-example/roles/tx03v2VeleroBucket"
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

run "apply_identity_has_the_service_roles_of_the_lab_and_no_editor" {
  command = apply

  assert {
    condition = toset(keys(google_project_iam_member.apply)) == toset([
      "roles/artifactregistry.admin",
      "roles/browser",
      "roles/cloudsql.admin",
      "roles/compute.networkAdmin",
      "roles/compute.securityAdmin",
      "roles/container.admin",
      "roles/dns.admin",
      "roles/parametermanager.admin",
      "roles/serviceusage.serviceUsageConsumer",
    ])
    error_message = "tx03v2-gha-apply gets the admin role of each service of the lab root (network, security policy, Cloud SQL, DNS, GKE, Artifact Registry, Parameter Manager) and nothing of the services it does not use."
  }

  assert {
    condition = alltrue([
      for forbidden in ["roles/editor", "roles/secretmanager.admin", "roles/iam.serviceAccountUser", "roles/owner", "roles/viewer"] :
      !contains(keys(google_project_iam_member.apply), forbidden)
    ])
    error_message = "tx03v2-gha-apply must not have Editor, Secret Manager Admin or Service Account User on the project (roadmap R3.16), nor Owner."
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
    error_message = "tx03v2-gha-apply reads and writes the state objects (and the lock object), nothing else of the bucket: without Editor it no longer reaches the other buckets of the project."
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

run "secrets_can_be_managed_but_not_read" {
  command = apply

  assert {
    condition = toset(google_project_iam_custom_role.lab_secrets.permissions) == toset([
      "secretmanager.locations.get",
      "secretmanager.locations.list",
      "secretmanager.secrets.create",
      "secretmanager.secrets.delete",
      "secretmanager.secrets.get",
      "secretmanager.secrets.getIamPolicy",
      "secretmanager.secrets.list",
      "secretmanager.secrets.setIamPolicy",
      "secretmanager.secrets.update",
      "secretmanager.versions.add",
      "secretmanager.versions.destroy",
      "secretmanager.versions.disable",
      "secretmanager.versions.enable",
      "secretmanager.versions.get",
      "secretmanager.versions.list",
    ])
    error_message = "The Secret Manager role of the apply identity is exactly the permissions the lab root needs to create, grant and version the two secrets."
  }

  assert {
    condition = (
      !contains(google_project_iam_custom_role.lab_secrets.permissions, "secretmanager.versions.access") &&
      alltrue([for p in google_project_iam_custom_role.lab_secrets.permissions : startswith(p, "secretmanager.")])
    )
    error_message = "The apply identity must never read a secret value (no secretmanager.versions.access: that is what Secret Manager Admin had), and the role holds nothing outside Secret Manager."
  }

  assert {
    # The role ID is written through a for expression: gitleaks reads "secrets...role_id == <name>"
    # as the assignment of a credential (generic-api-key), and this is the ID of a role.
    condition = (
      alltrue([for r in [google_project_iam_custom_role.lab_secrets] : r.role_id == "tx03v2LabSecrets"]) &&
      google_project_iam_member.apply_lab_secrets.role == "projects/tx03v2-lab-example/roles/tx03v2LabSecrets" &&
      google_project_iam_member.apply_lab_secrets.member == "serviceAccount:tx03v2-gha-apply@tx03v2-lab-example.iam.gserviceaccount.com" &&
      google_project_iam_member.apply_lab_secrets.project == "tx03v2-lab-example"
    )
    error_message = "The custom role goes to tx03v2-gha-apply on the lab project."
  }
}

run "apply_manages_velero_bucket_metadata_but_not_backup_objects" {
  command = apply

  assert {
    condition = toset(google_project_iam_custom_role.velero_bucket.permissions) == toset([
      "storage.buckets.create",
      "storage.buckets.delete",
      "storage.buckets.get",
      "storage.buckets.getIamPolicy",
      "storage.buckets.setIamPolicy",
      "storage.buckets.update",
    ])
    error_message = "The apply identity may manage only the dedicated backup bucket and its IAM policy."
  }

  assert {
    condition = (
      !contains(google_project_iam_custom_role.velero_bucket.permissions, "storage.objects.get") &&
      !contains(google_project_iam_custom_role.velero_bucket.permissions, "storage.objects.list") &&
      !contains(google_project_iam_custom_role.velero_bucket.permissions, "storage.objects.delete") &&
      google_project_iam_member.apply_velero_bucket.role == "projects/tx03v2-lab-example/roles/tx03v2VeleroBucket" &&
      google_project_iam_member.apply_velero_bucket.member == "serviceAccount:tx03v2-gha-apply@tx03v2-lab-example.iam.gserviceaccount.com" &&
      google_project_iam_member.apply_velero_bucket.condition[0].title == "velero-bucket-only" &&
      google_project_iam_member.apply_velero_bucket.condition[0].expression == "resource.type == 'storage.googleapis.com/Bucket' && resource.name == 'projects/_/buckets/tx03v2-lab-velero-tx03v2-lab-example'"
    )
    error_message = "Terraform can manage metadata only on the exact Velero bucket, cannot read backup contents, and cannot affect other buckets."
  }
}

run "apply_acts_as_the_node_account_only" {
  command = apply

  assert {
    condition     = google_service_account.nodes.account_id == "tx03v2-lab-nodes"
    error_message = "The bootstrap creates the node service account of the contract, tx03v2-lab-nodes."
  }

  assert {
    condition = (
      google_service_account_iam_member.apply_acts_as_nodes.service_account_id == "projects/tx03v2-lab-example/serviceAccounts/tx03v2-lab-nodes@tx03v2-lab-example.iam.gserviceaccount.com" &&
      google_service_account_iam_member.apply_acts_as_nodes.role == "roles/iam.serviceAccountUser" &&
      google_service_account_iam_member.apply_acts_as_nodes.member == "serviceAccount:tx03v2-gha-apply@tx03v2-lab-example.iam.gserviceaccount.com"
    )
    error_message = "tx03v2-gha-apply may act as tx03v2-lab-nodes (roles/iam.serviceAccountUser on that account, for GKE to run the nodes as it)."
  }

  assert {
    condition = alltrue([
      for m in concat(values(google_project_iam_member.apply), values(google_project_iam_member.apply_extra)) :
      !startswith(m.role, "roles/iam.service")
    ])
    error_message = "No service account role on the project for the apply identity: it cannot act as, create or impersonate any other account."
  }
}

run "extra_roles_are_empty_by_default" {
  command = apply

  assert {
    condition     = length(google_project_iam_member.apply_extra) == 0
    error_message = "apply_extra_project_roles is empty by default: nothing beyond the lab roles."
  }
}

run "extra_roles_go_to_the_apply_identity_only" {
  command = apply

  variables {
    apply_extra_project_roles = ["roles/compute.admin", "roles/editor"]
  }

  assert {
    condition = (
      toset(keys(google_project_iam_member.apply_extra)) == toset(["roles/compute.admin", "roles/editor"]) &&
      alltrue([for m in google_project_iam_member.apply_extra : m.member == "serviceAccount:tx03v2-gha-apply@tx03v2-lab-example.iam.gserviceaccount.com" && m.project == "tx03v2-lab-example"])
    )
    error_message = "An extra role (a decision of the person who applies the bootstrap) goes to tx03v2-gha-apply on the lab project, nowhere else."
  }
}

run "extra_roles_refuse_owner_and_identity_roles" {
  command = plan

  variables {
    apply_extra_project_roles = ["roles/owner"]
  }

  expect_failures = [var.apply_extra_project_roles]
}

run "extra_roles_refuse_project_iam_admin" {
  command = plan

  variables {
    apply_extra_project_roles = ["roles/resourcemanager.projectIamAdmin"]
  }

  expect_failures = [var.apply_extra_project_roles]
}

run "extra_roles_refuse_service_account_roles" {
  command = plan

  variables {
    apply_extra_project_roles = ["roles/iam.serviceAccountUser"]
  }

  expect_failures = [var.apply_extra_project_roles]
}

run "extra_roles_must_be_predefined_roles" {
  command = plan

  variables {
    apply_extra_project_roles = ["compute.admin"]
  }

  expect_failures = [var.apply_extra_project_roles]
}

run "extra_roles_must_be_unique" {
  command = plan

  variables {
    apply_extra_project_roles = ["roles/compute.admin", "roles/compute.admin"]
  }

  expect_failures = [var.apply_extra_project_roles]
}

run "nothing_for_the_deployer_and_no_owner" {
  command = apply

  assert {
    condition = alltrue([
      for m in concat(values(google_project_iam_member.plan), values(google_project_iam_member.apply), [google_project_iam_member.apply_project_iam_admin, google_project_iam_member.apply_lab_secrets, google_project_iam_member.apply_velero_bucket]) :
      m.member != "serviceAccount:dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
    ])
    error_message = "dx03v2-gha-deploy gets its roles from the lab root, on lab resources only (contract)."
  }

  assert {
    condition = alltrue([
      for m in concat(values(google_project_iam_member.plan), values(google_project_iam_member.apply), [google_project_iam_member.apply_project_iam_admin, google_project_iam_member.apply_lab_secrets, google_project_iam_member.apply_velero_bucket]) :
      m.role != "roles/owner"
    ])
    error_message = "No identity of the lab gets roles/owner."
  }
}
