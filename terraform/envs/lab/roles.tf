# Every IAM grant of the lab, in one place. Project-level roles come only from
# modules/project-roles, which is also the list the IAM condition of tx03v2-gha-apply allows
# (terraform/bootstrap/roles.tf): tests/roles.tftest.hcl proves both sides match, and a
# precondition refuses any other project role at plan time. The other grants are on single
# resources (the dx03v2 repository, the two secrets). Nothing ever goes to roles/owner or editor.
locals {
  # Contract: dx03v2-gha-deploy and every app_deployer_members entry (people deploying dx03v2 from
  # a laptop) get the same roles: push images, get cluster credentials through the DNS endpoint,
  # read the contract parameter. Nothing on Secret Manager; Kubernetes access comes only from the
  # dx03v2-deployers RoleBinding (platform/manifests).
  deployers = merge(
    { "deploy" = "serviceAccount:${var.deploy_service_account}" },
    { for m in var.app_deployer_members : "app-deployer-${m}" => m },
  )
  deployer_project_roles = {
    "cluster-viewer"     = "roles/container.clusterViewer"
    "parameter-accessor" = "roles/parametermanager.parameterAccessor"
  }

  project_grants = merge(
    {
      # Logs, metrics and metadata of the Autopilot nodes.
      "nodes-default-node-service-account" = {
        role   = "roles/container.defaultNodeServiceAccount"
        member = google_service_account.nodes.member
      }
    },
    {
      for pair in setproduct(keys(local.deployers), keys(local.deployer_project_roles)) : "${pair[0]}-${pair[1]}" => {
        role   = local.deployer_project_roles[pair[1]]
        member = local.deployers[pair[0]]
      }
    },
  )

  repository_grants = merge(
    # Nodes pull the dx03v2 images.
    { "nodes-reader" = { role = "roles/artifactregistry.reader", member = google_service_account.nodes.member } },
    { for k, m in local.deployers : "${k}-writer" => { role = "roles/artifactregistry.writer", member = m } },
  )

  # External Secrets Operator reads the two lab secrets (and nothing else).
  secret_grants = {
    "eso-db"          = module.secrets.db_secret_id
    "eso-admin-token" = module.secrets.admin_token_secret_id
  }
}

resource "google_project_iam_member" "lab" {
  for_each = local.project_grants

  project = var.project_id
  role    = each.value.role
  member  = each.value.member

  lifecycle {
    precondition {
      condition     = contains(module.project_roles.lab_project_roles, each.value.role)
      error_message = "Project role ${each.value.role} is not in modules/project-roles: the IAM condition of tx03v2-gha-apply would refuse it (add it there and re-apply the bootstrap)."
    }
  }
}

resource "google_artifact_registry_repository_iam_member" "dx03v2" {
  for_each = local.repository_grants

  project    = var.project_id
  location   = module.artifact_registry.location
  repository = module.artifact_registry.repository_id
  role       = each.value.role
  member     = each.value.member
}

resource "google_secret_manager_secret_iam_member" "eso" {
  for_each = local.secret_grants

  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = local.eso_principal

  # The workload identity pool <project_id>.svc.id.goog exists once the cluster does.
  depends_on = [module.gke]
}
