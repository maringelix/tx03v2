# The project-level IAM roles the lab root may grant (terraform/envs/lab/roles.tf), and nothing
# else. This module is the single source of the list:
# - terraform/envs/lab grants project roles only from it (tests/roles.tftest.hcl proves every
#   google_project_iam_member of the lab uses one of them, and that every one of them is used);
# - terraform/bootstrap puts exactly these roles in the IAM condition of the
#   roles/resourcemanager.projectIamAdmin grant of tx03v2-gha-apply
#   (api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([...])), so the lab
#   root cannot grant any other project role (for example roles/owner).
# Resource-level grants (Artifact Registry repository, Secret Manager secrets) are not in the list:
# the apply identity sets them through roles/artifactregistry.admin and roles/secretmanager.admin.
locals {
  lab_project_roles = [
    # Node service account tx03v2-lab-nodes: the least-privilege role GKE documents for nodes
    # (logging, monitoring, metadata).
    "roles/container.defaultNodeServiceAccount",
    # dx03v2-gha-deploy and app_deployer_members: credentials + the DNS endpoint (GKE IAM has no
    # cluster scope) and the contract parameter (no per-parameter IAM in the google provider 8.6.0).
    "roles/container.clusterViewer",
    "roles/parametermanager.parameterAccessor",
  ]
}
