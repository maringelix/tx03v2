# GitHub Actions identities of the contract (docs/CONTRACT.md): a Workload Identity Federation
# pool with one OIDC provider for GitHub, three service accounts (no keys, ever) and one
# roles/iam.workloadIdentityUser grant per exact subject. The provider condition admits only
# tokens of the two lab repositories of the owner, by the numeric IDs of the owner and of the
# repositories (a deleted and re-registered account or repository name gets other IDs); the
# subjects narrow each service account further (event, branch or environment).
#
# The subject is the immutable one of GitHub, used by every repository created after 2026-07-15 and
# by the ones that opted in: repo:<owner>@<owner id>/<repository>@<repository id>:<context>. The
# name-based subject (repo:<owner>/<repository>:<context>) is not trusted: it does not match those
# repositories, and whoever registers a deleted account name again would inherit it. A repository
# that predates 2026-07-15 must opt in to immutable subject claims (docs/RUNBOOK.md, section 2);
# scripts/repo-guardrails.sh checks it. Only the apply and deploy jobs use the environment lab,
# whose deployment branches are limited to main (repo-guardrails.sh).
# Deleted pools stay soft-deleted for 30 days and their IDs cannot be reused meanwhile.
locals {
  github_issuer = "https://token.actions.githubusercontent.com"
  pool_id       = "${local.project}-github"
  pool_name     = "projects/${local.project_number}/locations/global/workloadIdentityPools/${local.pool_id}"

  tx_subject_prefix = "repo:${var.github_owner}@${var.github_owner_id}/tx03v2@${var.tx03v2_repository_id}"
  dx_subject_prefix = "repo:${var.github_owner}@${var.github_owner_id}/dx03v2@${var.dx03v2_repository_id}"

  github_subjects = {
    plan_pull_request = { account = "plan", subject = "${local.tx_subject_prefix}:pull_request" }
    plan_main         = { account = "plan", subject = "${local.tx_subject_prefix}:ref:refs/heads/main" }
    apply_lab         = { account = "apply", subject = "${local.tx_subject_prefix}:environment:lab" }
    deploy_lab        = { account = "deploy", subject = "${local.dx_subject_prefix}:environment:lab" }
  }

  service_accounts = {
    plan   = { id = "tx03v2-gha-plan", description = "tx03v2 terraform plan (pull requests and main; read-only, plans run with -lock=false)." }
    apply  = { id = "tx03v2-gha-apply", description = "tx03v2 terraform apply/destroy and platform (GitHub environment lab only)." }
    deploy = { id = "dx03v2-gha-deploy", description = "dx03v2 deploy (GitHub environment lab of dx03v2 only)." }
  }
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = local.pool_id
  display_name              = "GitHub Actions (tx03v2, dx03v2)"
  description               = "OIDC tokens of the GitHub Actions workflows of tx03v2 and dx03v2."

  depends_on = [google_project_service.lab]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub Actions OIDC"
  description                        = "token.actions.githubusercontent.com, restricted by numeric ID to ${var.github_owner}/tx03v2 and ${var.github_owner}/dx03v2."

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }
  attribute_condition = "assertion.repository_owner_id == '${var.github_owner_id}' && assertion.repository_id in ['${var.tx03v2_repository_id}', '${var.dx03v2_repository_id}']"

  oidc {
    issuer_uri = local.github_issuer
  }
}

resource "google_service_account" "github" {
  for_each = local.service_accounts

  account_id   = each.value.id
  display_name = each.value.id
  description  = each.value.description

  depends_on = [google_project_service.lab]
}

# One grant per exact subject: no attribute-wide principalSet, no wildcard.
resource "google_service_account_iam_member" "workload_identity_user" {
  for_each = local.github_subjects

  service_account_id = google_service_account.github[each.value.account].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${local.pool_name}/subject/${each.value.subject}"

  depends_on = [google_iam_workload_identity_pool_provider.github]
}
