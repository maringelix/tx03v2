# Maintaining tx03v2

Keep the repository healthy without a cloud account: routines, support calendar and procedures.
Version/support entries preserve the 2026-10-16 review baseline; recheck official sources before
upgrades. Current executable pins remain in tools/platform version files.

## 1. Purpose and scope

Covers Terraform, scripts/workflows, harness tools, GKE, Cloud SQL PostgreSQL, ESO, gcloud,
Gateway API and optional cloud runs. App maintenance belongs in DX03; coordinated changes are
identified below.

## 2. Current state

- Main CI covers the construction through R7–R10 and later audit corrections. New changes must
  pass applicable CI before merge. Cloud remains `not run in the cloud (v2)`.
- Local platform: make e2e/full is `verified in CI`. Historical local evidence: 2026-10-13 full
  (then 26 probes, no leftovers) and 2026-10-14 observability with traces/Slack. Probe counts
  expanded later; use LOCAL_LAB and harness list for current coverage.
- Bootstrap, cloud apply/plan/platform/destroy have not run in a real v2 cloud.
- Current DX03 cloud contract is v5 with 18 keys; CONTRACT is authoritative. The earlier v2
  contract added the OTLP endpoint on 2026-10-14. DX checks consumption in its own harness.
- No Trivy exceptions at this baseline; .trivyignore.yaml is empty.

## 3. Routines

| When | Work | Method |
|---|---|---|
| Weekly, automatic | Monday 06:00 UTC complete CI | section 6; likely causes include chart/URL drift, new Trivy findings or network failure |
| Monthly | grouped Dependabot actions/providers/pre-commit PRs | AGENTS Dependency updater; green harness before merge |
| Quarterly | harness/gcloud/ESO/platform versions, schemas, costs, Autopilot/free-tier terms, SQL editions/tiers/CA root, GKE DNS/authorized-network behavior, expiring ignores/Dependabot rules | sections 4/5; record CHANGELOG |
| Before a cloud run | COSTS, budget, green source revision, GitHub configuration and project quotas | RUNBOOK section 1 and central getting-started guide |
| During | record timing/problems; do not leave the lab running overnight | RUNBOOK |
| After | destroy; leftovers locally as project Owner; sanitized cloud_run_report; evidence-backed status | RUNBOOK sections 8–11 |

## 4. Support calendar

Dates are the recorded baseline, not a fresh guarantee. Confirm upstream schedules during review.

| Component | Recorded version | Support horizon | Source | Action |
|---|---|---|---|---|
| GKE Kubernetes | 1.36, REGULAR default 1.36.4-gke.1391002 in 2026-10-08 notes | around 2027-06-30 standard support; confirm GKE schedule | [GKE schedule](https://cloud.google.com/kubernetes-engine/docs/release-schedule), [endoflife.date](https://endoflife.date/google-kubernetes-engine) | REGULAR auto-upgrades; align schema/contract minor, 5.4 |
| GKE Gateway API | 1.5.0, GKE >=1.35.2-gke.1842000, default Autopilot | follows GKE | GKE GatewayClass capabilities documentation | coordinate DX schemas |
| Cloud SQL PostgreSQL | 17 ENTERPRISE | community EOL 2029-11-08 | [PostgreSQL policy](https://www.postgresql.org/support/versioning/) | major upgrade/contract/DX PR before EOL; check Cloud SQL extended support |
| Terraform | 1.16.5, minimum >=1.11 | no fixed date | [releases](https://releases.hashicorp.com/terraform/) | quarterly, 5.2 |
| google provider | 8.6.0, ~>8.6 | no fixed date; usually annual major, ignored by Dependabot | registry.terraform.io | monthly, 5.3; reassess plan roles, 5.10 |
| random provider | 3.9.1, ~>3.9 | no fixed date | registry.terraform.io | monthly |
| tflint-ruleset-google | 0.40.0, 2026-09-23 | no published date | [releases](https://github.com/terraform-linters/tflint-ruleset-google/releases) | quarterly, 5.1 |
| ESO | v2.12.0/chart OCI 2.12.0, external-secrets.io/v1 | recent releases maintained | [releases](https://github.com/external-secrets/external-secrets/releases) | quarterly with TX01/TX02, 5.5 |
| gcloud/plugin | 588.0.0, 2026-10-02 | weekly releases, no per-version policy | [notes](https://cloud.google.com/sdk/docs/release-notes) | quarterly, 5.6 |
| auth/setup-gcloud actions | v3.0.0/v3.0.1 | no published deadline | upstream releases | Dependabot, 5.8 |
| kubectl/Helm | 1.37.1/4.3.0 | kubectl ±1 API minor, 1.36–1.38 | kubernetes.io/helm.sh | follow cluster; Helm 4 uses rollback-on-failure instead of atomic |
| SQL CA root | CN=Google Cloud SQL Root Server CA 0b29df, ECDSA P-384 | valid through 2049-06-27 | regional Cloud SQL CA bundles | root change is a contract change; subordinate CAs rotate, 5.12 |
| Runner/devcontainer | Ubuntu 24.04 LTS | standard support through 2029-04 | ubuntu.com | replace before EOL |
| kubeconform schemas | Kubernetes 5f1fa4f/1.36.0; CRDs f3e4382/2026-06-02 | — | HARNESS | quarterly, 5.7 |
| Trivy ignores | none | — | .trivyignore.yaml | new entries need statement/expired_at, 5.9 |
| Local Istio | 1.31.1 | estimated 2027-02, six weeks after 1.33 | [supported releases](https://istio.io/latest/docs/releases/supported-releases/) | quarterly with TX01, 5.14 |
| Other local charts | platform/local/versions.env: cert-manager 1.21.2, kube-prometheus-stack 92.3.0, Loki 7.3.0, Alloy 1.13.1, Tempo 3.1.0, Argo CD 10.10.3, Gatekeeper 3.23.1, Trivy Operator 0.37.0, Velero 12.2.1, Chaos Mesh 2.8.4, metrics-server 3.14.0; Collector 0.176.0/chart SHA256 in platform/versions.env | recent releases maintained | each upstream | quarterly with TX01, 5.14 |
| Emulated services | registry 3.1.2, Versity 1.8.0, Soft Serve 0.12.3, cloud-provider-kind 0.12.0, PostgreSQL 17 | no fixed deadline | terraform/envs/local/images.tf | quarterly, 5.14 |
| kind/gator | 0.33.0, kindest/node:v1.36.4 / 3.23.1 | no published policy | kind/Gatekeeper releases | quarterly, 5.14; node matches lab GKE minor |

## 5. Procedures

### 5.1 Harness tools

Applies to Terraform, tflint/Google ruleset, Trivy, actionlint, shellcheck, kubeconform, gitleaks,
kubectl, Helm, kind and gator.

```bash
scripts/update-tool-checksums.sh trivy 0.76.0
make tools && HARNESS_STRICT=1 make verify
git diff tools/ .tflint.hcl
```

Read release notes first. The updater uses exact release checksums for linux_amd64/linux_arm64/
darwin_arm64. Shellcheck publishes no checksum file, so all three archives are downloaded/hashed.

- gitleaks: also update pre-commit rev to the tag's commit SHA plus frozen version comment;
  version-consistency compares both.
- Google tflint ruleset: updater also changes .tflint.hcl version; confirm Google 8.x compatibility
  with zero tflint issues.
- Trivy: new binary includes new rules; harness uses skip-check-update.
- kubectl: stay within one minor of the cluster.

### 5.2 Terraform CLI

Use scripts/update-tool-checksums.sh terraform <version>. Raise required_version only when the
minimum must increase; version-consistency requires equal versions.tf constraints.

### 5.3 Providers and four-platform lockfiles

1. Read changelog/major-upgrade guide.
2. Align constraints in every versions.tf, including modules; Dependabot updates roots only.
3. In bootstrap and lab roots:

```bash
terraform init -backend=false -upgrade
terraform providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64 -platform=windows_amd64
```

4. Run strict verify. terraform-lockfiles requires four h1 hashes/provider; roots lock the same
   Google version and validate against its schema. Inspect providers schema -json for
   control_plane_endpoints_config, psc_config, server_ca_mode, secret_data_wo/password_wo.
   Check whether parameter-level google_parameter_manager_parameter_iam_member becomes
   available; replacing project parameterAccessor is a coordinated contract change.
5. Review plan permissions using 5.10.

### 5.4 Kubernetes

GKE follows REGULAR without min_master_version (policy-terraform forbids it). When REGULAR's
default minor changes:

1. Align GKE_KUBERNETES_MINOR/K8S_SCHEMA_KUBERNETES_VERSION and possibly K8S_SCHEMA_REF in harness.
2. Update CONTRACT minor/version with DX PR; version-consistency checks exact minor.
3. Keep kubectl within one minor.
4. Coordinate DX schemas/kind/kubectl.
5. Update local kind node image; local-versions checks the GKE minor.

### 5.5 External Secrets Operator, coordinated with TX01/TX02

1. Read CRD/chart/Kubernetes compatibility notes.
2. Pull OCI external-secrets chart at the chosen version. helm pull prints manifest
   ESO_CHART_DIGEST; hash the archive for ESO_CHART_SHA256. Update ESO_CHART_VERSION and local
   ESO_SHA256, which must match the HTTP archive.
3. Inspect ghcr.io/external-secrets/external-secrets:v<version> for the index digest. Update all
   three controller/webhook/cert-controller tags in platform/values/external-secrets.yaml;
   version-consistency expects three matching v<version>@sha256 pins across TX.
4. Strict verify: helm-template verifies digest/archive SHA256, images, three resource requests
   and unannotated external-secrets ServiceAccount; contract-platform checks values/pins.
5. CRD API changes are contract changes and require ClusterSecretStore schema updates, 5.7.

Installation rejects mismatched OCI digests or archive checksums.

### 5.5.1 OpenTelemetry Collector

Cloud/local share OTEL_COLLECTOR_CHART_VERSION/CHART_SHA256 in platform/versions.env and the
contrib image digest. helm-template rejects differing digests. Review renamed components such
as otlp_grpc/k8s_attributes and googlecloud exporter; update both values and chart pins.
Run verify/e2e: local exercises prove the pipeline, not actual Cloud Trace ingestion.

### 5.6 Google Cloud CLI

1. Review changes to get-credentials, parametermanager, NEGs, SQL backups and leftovers list calls.
2. Update tools/versions.env GCLOUD_VERSION and every setup-gcloud version, including platform/
   destroy workflows; version-consistency checks equality.
3. Keep install_components gke-gcloud-auth-plugin from the same setup step.

### 5.7 kubeconform schemas

Pin K8S_SCHEMA_REF (yannh) and CRD_SCHEMA_REF (datreeio) in harness; coordinate with TX01/TX02.

```bash
gh api 'repos/datreeio/CRDs-catalog/commits?path=external-secrets.io/clustersecretstore_v1.json&per_page=3'
```

See HARNESS's documented ESO schema incompatibility.

### 5.8 Image/action digests

Inspect the devcontainer image index with docker buildx imagetools inspect.
For actions, query the tag ref; dereference annotated tag objects to a commit and verify it
exists, then pin the full SHA with version comment. version-consistency requires one pin per
action. Never use aquasecurity/trivy-action or setup-trivy; workflow policy rejects them.

### 5.9 Trivy exceptions

No exceptions at baseline. Any future ignore needs the GUARDRAILS exception process.
Before expired_at, fix/remove or renew with current justification for at most about seven months.
trivyignore-policy rejects expired/overlong entries.

### 5.10 Plan roles after Google provider bumps

Refresh must fit tx03v2-gha-plan permissions: viewer, iam.securityReviewer,
parametermanager.parameterViewer and state-bucket objectViewer (architecture ADR 16).
Inspect provider Read implementations for parameter version GET payload (parameterVersions.get),
Secret Manager write-only-version handling without :access, SQL users, GKE clusters and IAM
members. For new reads adjust bootstrap plan_project_roles using least privilege and
plan_identity_is_read_only tests; they reject writes, impersonation and secret-value access.

### 5.11 Prices

Quarterly review GKE, Cloud SQL, LB, Armor, NAT, PSC, DNS, Secret Manager, Parameter Manager,
Artifact Registry and Logging prices for us-central1; update COSTS/README date/totals and verify
Autopilot/free-tier terms. Per-run FinOps worksheets additionally need current regional prices
within their shorter freshness window.

### 5.12 Cloud SQL edition, tiers and CA root

1. Check PostgreSQL 17/db-g1-small ENTERPRISE availability and max_connections (baseline assumption
   50, used by the contract capacity calculation). Adjust db_tier validation/tests if changed.
2. Download the regional bundle and inspect the self-signed root:

```bash
curl -fsS https://storage.googleapis.com/cloudsql-ca-bundles/us-central1.pem -o /tmp/ca.pem
awk '/BEGIN CERT/ { n++ } n { print > ("/tmp/ca-" n ".pem") }' /tmp/ca.pem
for f in /tmp/ca-*.pem; do openssl x509 -in "$f" -noout -subject -issuer -fingerprint -sha256; done
```

Root SHA-256 must match CONTRACT; a new root requires a contract change because DX rejects
different roots.

### 5.13 GKE DNS endpoint, authorized networks and Autopilot

Review control_plane_endpoints_config, master_authorized_networks_config and
gcp_public_cidrs_access_enabled release notes, Autopilot minimums/ratios (baseline assumptions:
50m CPU/52 MiB per pod, CPU:memory 1:1–1:6.5), and free-tier terms.
autopilot_private_dns_endpoint_gateway proves configuration, not GKE runtime behavior.

### 5.14 Local charts, images and kind

Pins match TX01; update all TX together.

1. Read upstream notes, pull each platform/local/versions.env chart, record version/archive
   SHA256. Local ESO_SHA256 must equal cloud ESO_CHART_SHA256.
2. Update local values image index digests; helm-template-local rejects unpinned images.
3. Bump GATOR_VERSION with GATEKEEPER_VERSION; local-versions enforces equality.
4. Update all emulated-service image pins. kind node in terraform/envs/local/kind-config.yaml
   follows harness GKE_KUBERNETES_MINOR.
5. Run verify/e2e or let required Actions e2e prove the PR; update CHANGELOG.
   Heavy validation in Bruno's workspace stays in Actions.

### 5.15 Cloud full charts

1. Keep only required charts in platform/full/charts.txt, matching local/TX01/TX02 version,
   SHA256 and image pins. GCP excludes privileged ambient, node-exporter, Trivy node collector
   and Chaos daemon.
2. Verify upstream values, archive SHA256/OCI digest, run helm-template-full and inspect images,
   requests, Service types and Chaos Mesh Helm 4 post-rendering.
3. Run kubeconform, policy-gator, contract-platform-full, image-admission-policy, full-install-order
   and platform-sizing. Keep KYVERNO_* and image pins equal across TX. Update request sums/costs
   after chart/replica/request changes; core remains default.
4. Verify official Autopilot support before changing exclusions; record source/date in architecture.
   Local renders do not prove GKE admission/runtime.

## 6. Incident response

| Situation | First steps |
|---|---|
| CI failure | inspect the first FAIL/log; fix code, preserve gates, reproduce light checks with strict verify |
| Vulnerability | Dependabot/advisory PR; tools 5.1, ESO 5.5; private reporting in SECURITY |
| Budget email | leftovers --project as Owner; destroy active lab; inspect Cloud Billing by service/SKU |
| Exposed credential | no service-account keys/cloud passwords in GitHub; rotate leaked Secret Manager values through db_password_version/admin_token_version/apply; review WIF trust; history rewrite is a maintainer decision |
| Leftovers | follow script output and RUNBOOK section 9; record sanitized cloud_run_report |
| Reserved name | architecture's soft-delete/naming guidance for WIF pool/deleted SQL instance |

## 7. Cloud run records

Each run gets cloud_run_report with date, region, redacted billing scope, commits, steps, duration,
observed costs, problems and leftovers. Change README cloud labels only with real evidence.

## 8. Ownership

Maintainer @maringelix owns decisions, merges and cloud runs. Agents follow AGENTS.
Public docs/instructions use English. Keep the central TX00 getting-started guide synchronized
with bootstrap, variables/secrets, profiles and workflows.
