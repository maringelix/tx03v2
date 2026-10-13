# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Conventional Commits](https://www.conventionalcommits.org/).

## [Unreleased]

### Changed

- The CI (`static`, `test`) ran green on GitHub: the README status matrix now says `verified in CI`
  for the harness rows (AGENTS.md, docs/SUSTENTACAO.md and docs/LICOES_APRENDIDAS.md follow).
- `dx03v2` exists and is public (CI green there): the README family tables link it, and AGENTS.md,
  docs/RUNBOOK.md (section 6 points to its `deploy-gcp` workflow and runbook), docs/SUSTENTACAO.md,
  docs/ARQUITETURA.md and docs/LICOES_APRENDIDAS.md stop calling it `planned`; its deploy stays
  `not run in the cloud (v2)`.

### Added

- The local lab (docs/LAB_LOCAL.md), ported from tx01v2: the whole v1 platform on Docker, with no
  cloud account. `make e2e` verified locally (26 probes, destroy with no leftovers).
  - `terraform/envs/local` (providers docker 4.6.0, tls 4.4.1, random 3.9.1): network
    `tx03v2-local` (`10.252.0.0/24`), kind 1.36 cluster (the GKE Autopilot twin), emulated Artifact
    Registry (registry 3.1.2, push to `localhost:5003`), Cloud SQL (PostgreSQL 17, TLS only, lab CA),
    Cloud Storage (Versity S3 Gateway 1.8.0, S3 API), load balancer (cloud-provider-kind 0.12.0, the
    GKE Gateway twin) and git server (Soft Serve 0.12.3); 10 `terraform test` runs (plan only, mocked
    providers). Network and registry port differ from tx01v2 (`10.250.0.0/24`, `5001`) and tx02v2
    (`10.251.0.0/24`, `5002`) so the labs never collide.
  - `platform/local`: Gateway API 1.6.3, Istio 1.31.1 ambient, cert-manager 1.21.2 (`lab-ca`),
    External Secrets 2.12.0 (`local-secrets`, on top of `platform/values/external-secrets.yaml`; the
    same archive SHA256 as the OCI chart of the cloud platform), metrics-server,
    kube-prometheus-stack 92.3.0 with an in-cluster alert sink, Loki 7.3.0 + Alloy 1.13.1, Argo CD
    10.10.3, Gatekeeper 3.23.1 with six policies from v1 in `deny`, Trivy Operator 0.37.0, Velero
    12.2.1 (AWS/S3 plugin against the emulator only), Chaos Mesh 2.8.4; charts pinned by version and
    SHA256, images by digest (same pins as tx01v2); profiles `core`, `observability`, `operations`,
    `full`.
  - The edge keeps an external `X-Request-Id` (EnvoyFilter `gateway-preserve-request-id`), as the
    dx03v2 smoke on kind expects (`SMOKE_EDGE=nginx`); what the global external Application Load
    Balancer of the GKE Gateway does with the header is not documented (dx03v2 `SMOKE_EDGE=gke` checks
    only the safety property). Trivy Operator in ClientServer mode with the built-in Trivy server.
  - The dx03v2 local deploy targets: AppProject `dx03v2`, Secrets `lab-secrets/tx03v2-lab-db-app`,
    `lab-secrets/tx03v2-lab-app-admin-token` (the Secret Manager secret names of contract v1) and
    `lab-secrets/gitops-push-key`, namespace `monitoring` in the ambient mesh.
  - `platform/local/check.sh`: 26 probes with real traffic or API calls (mTLS and authorization,
    HTTPS through the emulated load balancer, X-Request-Id pass-through, alert delivery, logs, GitOps
    sync and self-heal, policy denials, vulnerability reports, backup/restore drill, chaos experiment
    with a hypothesis). `platform/local/uninstall.sh` stops the Argo CD application controller before
    deleting Gateways and Services of type LoadBalancer.
  - `scripts/local-lab.sh` (up, down, check, e2e, kubeconfig, status) and
    `scripts/leftovers-local.sh`; local contract `lab-system/lab-contract` (docs/CONTRATO.md), with
    the same keys as tx01v2.
  - Harness: checks `local-versions` (the kind node minor equals `GKE_KUBERNETES_MINOR`, the local
    ESO archive SHA256 equals `ESO_CHART_SHA256`), `helm-template-local`, `kubeconform-local`,
    `policy-gator`, `terraform-validate:envs/local`, `terraform-test:envs/local`; stage `e2e`
    (`local-lab-e2e`, `make e2e`) and the CI job `e2e` (diagnostics and the full e2e log uploaded on
    failure); tools kind 0.33.0 and gator 3.23.1. `policy-terraform` allows `random_password` and
    the `local` backend only in `terraform/envs/local`, keeps the `0.0.0.0/0` rule on the cloud roots
    and modules (the local `pg_hba.conf` is inside a private Docker network) and forbids cloud
    providers, remote backends, `0.0.0.0` ports and privileged containers in the local root;
    `trivy-config` skips the gator fixtures. Dependabot watches `terraform/envs/local`.
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
