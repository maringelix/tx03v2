# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Conventional Commits](https://www.conventionalcommits.org/).

## [Unreleased]

### Added

- R8 for the GKE `full` profile (contract version 4, coordinated with dx03v2): optional Cloud DNS zone,
  Google-managed certificate and Certificate Map for an HTTPS Gateway; managed Cloud Service Mesh with
  STRICT mTLS and per-workload plaintext exceptions; Cloud Armor with seven CRS categories, a per-IP
  limit and Adaptive Protection alerts; persistent observability with SLO alerts and a synthetic probe;
  Kyverno fail-closed admission of signed promotions; Trivy Operator and Kyverno reading Artifact
  Registry as workload identities. Three contract keys are new (`dns/hostname`,
  `dns/certificate-map`, `mesh/management`). The cloud profile remains `not run in the cloud (v2)`.

- Contract version 3 records the R4 GitOps Application and the deploy identity's restricted refresh
  permission, coordinated with the dx03v2 R4 deploy flow.
- Optional GKE Autopilot `full` profile with pinned cloud-safe charts, GitOps app-of-apps, in-cluster
  observability, Gatekeeper, Trivy Operator, Velero on Cloud Storage, and the Chaos Mesh controller.
  Istio ambient, node-exporter, the Trivy node collector, and the privileged Chaos Mesh daemon are
  excluded by design. Cloud execution is still `not run in the cloud (v2)`.
- Reproducible chart request sizing, core/full cost estimates, the fork restore drill, and checks for
  the full chart set, GitOps contract, policy cases, and runbook references.

### Security

- The control plane of the private cluster gets a fixed /28 and a firewall rule to the admission
  webhooks (8443 and 9443). Without it the R4 Gatekeeper webhook was unreachable from the API server.

- The Velero bucket has a project-scoped custom role limited to bucket metadata; only the Velero
  Workload Identity principal receives object access, scoped to that bucket. No key or Kubernetes
  Secret is used, and the bucket refuses deletion while it contains objects.

### Fixed

- The External Secrets webhook of the local lab timed out (`context deadline exceeded`) because the
  local values kept the CPU limits that Autopilot needs (50m on the webhook and the cert controller,
  100m on the controller). The local values drop the resources of the webhook and the cert controller
  with `null`, as in tx01v2 and tx02v2, and give the controller a 1-CPU ceiling: Helm keeps a nested
  `null` that the chart does not default, which would render `cpu: null` (roadmap R1.10).

### Security

- The apply identity has no Editor, no Secret Manager Admin and no Service Account User on the whole
  project any more (roadmap R3.16, Google Cloud):
  - It has the admin role of each service the lab root uses (Artifact Registry, Cloud SQL, Compute
    networking and security policies, Cloud DNS, Kubernetes Engine, Parameter Manager) plus Browser
    and Service Usage Consumer; no VMs, no buckets but the state (it no longer reaches the other
    buckets of the project, the state bucket included), no BigQuery, Pub/Sub or KMS.
  - Secret Manager comes as the custom role `tx03v2LabSecrets`: create, grant and version the lab
    secrets, never `secretmanager.versions.access` (Secret Manager Admin could read every value).
  - The node service account `tx03v2-lab-nodes` moved from the lab root to the bootstrap, so that
    `roles/iam.serviceAccountUser` is granted on that account and nowhere else; the lab root builds
    its e-mail from the contract name. Trivy finding `GCP-0011` is gone. A lab created before this
    change needs the `state rm` and `import` of `docs/RUNBOOK.md`, section 5.
  - New bootstrap variable `apply_extra_project_roles` (empty by default; Owner, Project IAM Admin
    and service account roles refused) for the case where a real apply fails with
    `PERMISSION_DENIED`: the roles come from the documentation of each service, not from an apply.
  - The roles are still project-wide, not tied to `tx03v2-lab-*` names (a role cannot be tied to a
    resource that does not exist yet): the project must be the lab's own, as `scripts/preflight.sh`
    checks. `docs/GUARDRAILS.md` (SEC-20 and "Limites") and `docs/ARQUITETURA.md` (ADR 15) say so.
    New tests in `terraform/bootstrap/tests/roles.tftest.hcl`; `leftovers.sh` lists the node account
    as a bootstrap resource that stays.
- The cloud path no longer trusts anyone who registers a deleted account name, it works for the
  repositories GitHub creates now, and the project must be the lab's own (roadmap R3.13 to R3.17):
  - The Workload Identity provider condition checks `repository_owner_id` and `repository_id`, and the
    grants pin the immutable subject, `repo:<owner>@<owner id>/<repository>@<repository id>:<context>`,
    which every repository created after 2026-07-15 (a fork too) emits; the name-based subject no
    longer matched them. New bootstrap variables `github_owner_id`, `tx03v2_repository_id` and
    `dx03v2_repository_id` (the `gh api` commands are in `docs/RUNBOOK.md`).
  - `scripts/repo-guardrails.sh` (same file in the six lab repositories) fails, instead of skipping,
    when it cannot protect the environment `lab`; it leaves only `main` in it, reads it back, fails
    when the OIDC subject of the repository is name-based and refuses an argument that is not the
    repository of the clone.
  - `scripts/preflight.sh --project <id>` refuses a project that holds a GKE cluster, a Cloud SQL
    instance or a secret that is not the lab's; `terraform-apply` runs it first (the apply identity
    has Editor on the whole project). New check `preflight-flow`. Narrowing the apply roles to
    `tx03v2-lab-*` resources was not done (it needs IAM conditions that cannot be validated without a
    cloud): `docs/GUARDRAILS.md`, "Limites".
  - `LAB_APP_DEPLOYER_MEMBERS` is a secret, masked element by element in every cloud workflow; the plan
    summary and artifact replace the members (`<MEMBER>`, `<EMAIL>`). `policy-workflows` enforces it.
  - `scripts/leftovers.sh --project <id>` names the project in every `gcloud` call and counts as
    leftover only what is the lab's (label `project=tx03v2`, name `tx03v2-lab*`, network `tx03v2-lab`,
    load balancer pieces of the namespace `dx03v2`): the same kinds of resource of other work are INFO
    "(not the lab's)". New check `leftovers-flow` runs it against a simulated project that also holds
    other work.
- Scripts act only on what the lab created, so whoever forks it can run them on a machine and a
  project that also hold other work:
  - `platform/uninstall.sh` no longer reads `CLUSTER_NAME` from the environment, and
    `scripts/lib/gcp.sh` no longer reads `LAB_PROJECT`, `LAB_NAME` or `CONTRACT_PARAMETER`: the target
    is the contract cluster `tx03v2-lab`, and the platform scripts refuse a cluster without the label
    `project=tx03v2` (`require_lab_cluster`).
  - The output `get_credentials_command` writes the kubeconfig of the lab to its own file
    (`/tmp/tx03v2-lab.kubeconfig`): `~/.kube/config` and its current context stay as they were.
  - The scripts of `platform/local` refuse any kube context but `kind-tx03v2-local`
    (`require_lab_context`), also when one of them runs on its own: `platform/local/uninstall.sh`
    deletes every Gateway and LoadBalancer Service of the cluster it reaches.
  - New static check `policy-scripts` keeps all of this from coming back.
- `github_owner` has no default any more (`terraform/bootstrap` and `terraform/envs/lab`): a fork that
  kept the default would have created CI identities that trust the workflows of another owner. The
  bootstrap refuses the placeholders of `terraform.tfvars.example` (`your-github-user` and the alert
  e-mail `you@example.com`); the workflows pass `github.repository_owner` to the lab root. New tests
  `placeholder_owner_is_refused` and `placeholder_alert_email_is_refused`.

### Changed

- Comments, script messages and docs say "the contract" or point to `docs/CONTRATO.md` instead of
  "contract v1": the contract has been at version 2 since round 1 (roadmap S.8); the README says that HTTPS on the Gateway is outside contract v2.
- The family table of both READMEs links the family hub `tx00v2` (roadmap, family guardrails,
  cross-repo checks).
- `docs/GUARDRAILS.md`, `docs/ARQUITETURA.md` and `docs/CONTRATO.md` no longer say that the
  end-to-end run of the local lab and the local deploy of dx03v2 are pending: the CI jobs `e2e` (here)
  and `e2e-platform` (dx03v2) run them on every pull request.
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

- `scripts/destroy.sh` (roadmap R3.14), run by `terraform-destroy`: when the platform uninstall fails
  the pieces of the Gateway load balancer that the controller left (forwarding rules, proxies, URL
  maps, backend services, health checks, NEGs, firewall rules of the lab, by name and network) are
  deleted through the API, `terraform destroy` still runs and the leftover check always ends the run.
  The workflow has an optional `force_unlock_id` input for the lock of an interrupted apply, and
  `docs/RUNBOOK.md` documents the recovery. New check `destroy-flow` (simulated `gcloud`,
  `terraform`, `kubectl`, `helm`).
- Pre-flight of `scripts/local-lab.sh up` (roadmap R3.18), also as `scripts/local-lab.sh preflight`:
  the Docker CLI and the Terraform provider must talk to the same daemon, the lab network must not
  overlap a Docker network or a route of the machine, the registry port must be free. `down` and `e2e`
  refuse a lab that their state directory did not create, and `e2e` refuses a lab that is already up
  (it would destroy it). `make clean` removes things only under the directory of the Makefile. New
  check `local-preflight`. The budget does not subtract credits (`EXCLUDE_ALL_CREDITS`) and
  `budget_alert_emails` is required; the runbook recommends a gcloud configuration directory of the
  lab's own (`CLOUDSDK_CONFIG`).
- `LOCAL_SIZE=small` for the local platform (roadmap R1.8, the port of tx01v2):
  `platform/local/values/small/<chart>.yaml` goes last in `helm_install`, with smaller memory limits
  and `GOMEMLIMIT` below them, 2 h of retention in Prometheus and 1 h in Tempo, no cAdvisor, kubelet
  probes or apiserver histogram series (and no default rules that read them), Grafana without unified
  alerting, fewer Argo CD workers, one Trivy scan job at a time and a lower limit for the operator,
  and the Gatekeeper audit every 5 minutes on the kinds the constraints match.
  `scripts/local/kind-cluster.sh` appends `terraform/envs/local/kind-config-small.yaml` (`GOMEMLIMIT`
  for the API server, the controller manager and etcd). The components stay the same. At the small
  size the full platform with the app of dx03v2 passes in 7 GB (18 probes in about 13 minutes, 4.40
  GiB of anonymous memory; the kernel killed the plugin copy of Velero twice during the install, an
  init container the kubelet runs again; CI job `e2e-platform-small` of dx03v2). The
  `helm-template-local` check renders every chart with an overlay a second time and fails when the
  overlay changes an image or names a chart that does not exist.
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
