# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Conventional Commits](https://www.conventionalcommits.org/).

## [Unreleased]

### Added

- First version of the GCP lab (v2 of the Google Cloud infrastructure), built from scratch with the
  lessons of v1 (docs/LICOES_APRENDIDAS.md; docs/ARQUITETURA.md, "v1 → v2"):
  - `terraform/bootstrap`: the 15 APIs of the lab (never disabled on destroy), the state bucket
    `tx03v2-tfstate-<suffix>` (uniform access, public access prevention, versioning, noncurrent
    versions deleted after 30 days, deletion refused until `state_protection = false`), the Workload
    Identity Federation pool `tx03v2-github` with a GitHub provider restricted to the two lab
    repositories, the service accounts `tx03v2-gha-plan`, `tx03v2-gha-apply` and `dx03v2-gha-deploy`
    with one `roles/iam.workloadIdentityUser` grant per exact subject, least-privilege roles (plan:
    Viewer, Security Reviewer, Parameter Viewer and read-only state; apply: Editor plus the admin
    roles Editor lacks and Project IAM Admin limited by an IAM condition to the project roles of
    `modules/project-roles`) and the project budget (50/90/100 % of the current spend and 100 % of
    the forecast).
  - `terraform/envs/lab` with modules `network` (custom VPC, nodes subnet with secondary ranges,
    Private Google Access, Cloud Router + Cloud NAT, global address of the Gateway), `gke`
    (Autopilot, REGULAR channel, private nodes, no public IP endpoint, IAM-only DNS endpoint, Gateway
    API, node service account), `cloudsql` (PostgreSQL 17, edition ENTERPRISE, `db-g1-small`, Private
    Service Connect only, encrypted connections only with the shared regional CA, private DNS zone,
    write-only password), `secrets` (two regional Secret Manager secrets, write-only),
    `artifact-registry` (immutable tags, cleanup policies), `waf` (Cloud Armor with the preconfigured
    SQLi and XSS rules and 64 KB body inspection, `enable_waf` on by default), `contract` (Parameter
    Manager parameter with the 15 contract keys) and `project-roles`; every IAM grant of the lab in
    `roles.tf`, with a precondition that refuses project roles outside the shared list.
  - `app_deployer_members` (`user:` and `serviceAccount:` only) get the roles of `dx03v2-gha-deploy`
    besides the RoleBinding subject; `db_tier` refuses `db-f1-micro` and Enterprise Plus tiers.
  - Multi-platform provider lock files (linux_amd64, linux_arm64, darwin_arm64, windows_amd64).
  - `terraform test` suites with a mocked google provider for both roots and their modules (60 runs).
  - `platform/`: External Secrets Operator 2.12.0 (OCI chart pinned by manifest digest and archive
    SHA256, images by digest, resource requests for Autopilot) install and uninstall scripts, Helm
    values, namespace, deployer RBAC and ClusterSecretStore manifests rendered from the contract; the
    uninstall waits for the Gateway load balancer and its NEGs to go before any destroy.
  - Harness (`scripts/harness.sh`, `make verify`, 32 checks) with pinned, SHA256-verified tools,
    including Google Cloud policy checks (contract labels, placeholder identifiers, write-only
    secrets, private cluster and database, no `roles/owner`, no service account keys, no
    authoritative IAM).
  - GitHub workflows: `ci`, `terraform-plan`, `terraform-apply`, `platform`, `terraform-destroy`;
    ruleset and repository settings as code; Dependabot; issue and PR templates.
  - `scripts/leftovers.sh` to find billable or orphaned leftovers after a destroy.
  - Brazilian Portuguese docs: architecture, contract v1, runbook, costs (list prices read on
    2026-10-11), guardrails, harness, sustainment, publication checklist, and
    `docs/LICOES_APRENDIDAS.md` (39 sanitized lessons learned from the GCP v1 lab).
