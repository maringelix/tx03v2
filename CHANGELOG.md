# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Conventional Commits](https://www.conventionalcommits.org/).

## [Unreleased]

### Security

- `github_owner` has no default any more (`terraform/bootstrap` and `terraform/envs/lab`): a fork that
  kept the default would have created CI identities that trust the workflows of another owner. The
  bootstrap refuses the placeholders of `terraform.tfvars.example` (`your-github-user` and the alert
  e-mail `you@example.com`); the workflows pass `github.repository_owner` to the lab root. New tests
  `placeholder_owner_is_refused` and `placeholder_alert_email_is_refused`.

### Changed

- The family table of both READMEs links the family hub `tx00v2` (roadmap, family guardrails,
  cross-repo checks).
- `scripts/repo-guardrails.sh` also turns issues on (the issue forms) and requires approval for
  workflow runs from forks of external contributors; the reviewer of the `lab` environment is the gh
  user that runs it. It fails while the workflows of a fork are still disabled and notes a renamed
  repository or a CODEOWNERS that names someone else (tested against a stub gh, then applied to the
  original repository and read back with `gh api` on 2026-10-14).
- The ruleset requires the CI job `e2e` too (`.github/rulesets/main.json`, applied with
  `scripts/repo-guardrails.sh`): the local lab is a merge gate, not only maintainer discipline.
- README status matrix: repository settings as code are applied (read back with `gh api` on
  2026-10-13), no longer `planned`.
- The CI (`static`, `test`) ran green on GitHub: the README status matrix now says `verified in CI`
  for the harness rows (AGENTS.md, docs/SUSTENTACAO.md and docs/LICOES_APRENDIDAS.md follow).
- `dx03v2` exists and is public (CI green there): the README family tables link it, and AGENTS.md,
  docs/RUNBOOK.md (section 6 points to its `deploy-gcp` workflow and runbook), docs/SUSTENTACAO.md,
  docs/ARQUITETURA.md and docs/LICOES_APRENDIDAS.md stop calling it `planned`; its deploy stays
  `not run in the cloud (v2)`.

### Added

- Local lab, "Observability 2.0" (ported from tx01v2; the last step of the v1 roadmap, never started
  there): Tempo 3.1.0 (grafana-community chart 3.1.0) and the OpenTelemetry Collector contrib 0.162.0
  (chart 0.176.0) in the observability layer; every Istio Gateway reports its spans (Telemetry
  `mesh-default`); spanmetrics with exemplars (scraped every 10 s: an exemplar lives one flush);
  Grafana links logs, metrics and traces. Alertmanager also posts warning and critical alerts to Slack
  (Secret `monitoring/alertmanager-slack`, `LOCAL_SLACK_WEBHOOK_URL`; without it the sink gets the Slack
  message and a probe checks it). Chaos with hypotheses: NetworkChaos (100 ms) and StressChaos (CPU +
  memory) next to the pod kill. The edge keeps a UUID-shaped `X-Request-Id` as sent. A failed install
  dumps diagnostics for the CI artifact. Local contract version 2 (`tracing.otlp-endpoint`). 34 probes
  (was 26).
- Contract version 2 (`not run in the cloud (v2)`): the cloud platform layer installs the same
  Collector (chart pinned by version and archive SHA256, `OTEL_COLLECTOR_CHART_*` of
  `platform/versions.env`, shared with the local lab) in the namespace `observability`, exporting to
  Cloud Trace. Its Kubernetes ServiceAccount is the IAM principal itself (no Google service account,
  no key) with `roles/cloudtrace.agent` on the project: an IAM widening of `modules/project-roles`
  that also changes the IAM condition of `tx03v2-gha-apply`, and the API `cloudtrace.googleapis.com`
  joins the bootstrap list (re-apply the bootstrap). `platform/uninstall.sh` removes the release;
  tests and the `contract-platform`/`helm-template` checks cover the grant, the API, the namespace,
  the service account, the exporter, the requests and the digest.
- `FORK.md`: forking the lab step by step (what GitHub does not copy to a fork, the repository
  settings, the local lab, your own cloud account, troubleshooting), linked from both READMEs and
  CONTRIBUTING.md; the harness requires it.
- The devcontainer has Docker-in-Docker, so `make e2e` runs inside it (verified locally with
  `LOCAL_PROFILE=core`), and declares 4 CPUs and 8 GB; the harness checks that devcontainer features
  are pinned by digest.
- The local lab (docs/LAB_LOCAL.md), ported from tx01v2: the whole v1 platform on Docker, with no
  cloud account. `make e2e` verified locally and in CI (26 probes, destroy with no leftovers).
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
