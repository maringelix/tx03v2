# The node service account of the lab cluster (contract: tx03v2-lab-nodes). It is created here, once,
# and not by the lab root: tx03v2-gha-apply may then act as THIS account (roles/iam.serviceAccountUser,
# granted on the account and nowhere else) instead of as every service account of the project, which
# is what a project-level grant allows. The lab root only grants the account its roles
# (container.defaultNodeServiceAccount, artifactregistry.reader) and hands its e-mail to the cluster.
# The account stays between rounds, like the CI identities; the bootstrap teardown deletes it.
resource "google_service_account" "nodes" {
  account_id   = "${local.lab_name}-nodes"
  display_name = "${local.lab_name} GKE nodes"
  description  = "Node service account of the ${local.lab_name} Autopilot cluster (logs, metrics, image pulls from dx03v2)."

  depends_on = [google_project_service.lab]
}

resource "google_service_account_iam_member" "apply_acts_as_nodes" {
  service_account_id = google_service_account.nodes.name
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.github["apply"].member
}
