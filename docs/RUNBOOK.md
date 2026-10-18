# Runbook: a complete cloud round

Create the lab in your Google Cloud project, publish the dx03v2 app, destroy the
resources and record the result. No v2 cloud run has occurred (`not run in the
cloud (v2)`); this run supplies the first managed-service evidence. Times below
are estimates. App details are in the [dx03v2 runbook](https://github.com/maringelix/dx03v2/blob/main/docs/RUNBOOK.md).
Start with the [family getting started guide](https://github.com/maringelix/tx00v2/blob/main/docs/GETTING_STARTED.md).

> **Cost:** historical list-price estimates checked 2026-10-16 put core near
> USD0.12/hour with available GKE credit or USD0.22 without. Full is roughly
> USD0.21/0.31 including estimated sidecars/disks but excluding unconfirmed managed
> mesh pricing, data and backup storage. Three hours: core USD0.37–0.67; full
> USD0.64–0.94. These are not invoices. Review current regional prices and the
> mandatory estimate gate in FINOPS. Destroy the same day.

## 1. Prerequisites

- A **dedicated**, billing-linked project you created. Budget and powerful apply
  service roles are project-scoped; they could affect unrelated clusters,
  databases or secrets. `scripts/preflight.sh --project <id>` rejects foreign
  GKE/Cloud SQL/Secret Manager resources; apply repeats it before planning.
  Examples use `tx03v2-lab-example`.
- Project **Owner** for enabling APIs, creating identities and IAM grants, plus
  Billing Account Administrator or Billing Account Costs Manager to create the
  budget. Project Owner alone does not authorize billing-account budgets.
- Google Cloud CLI with `gke-gcloud-auth-plugin`, `jq`, authenticated `gh`, and
  `make tools` for pinned Terraform/kubectl/Helm. Laptop app deployment additionally
  needs Node.js 24, Git, curl, base64, openssl, awk, crane and a verified release
  bundle; consult the DX script header. Cloud deployment promotes approved images
  rather than building them on the laptop.
- Separate gcloud configuration **before** login:
  `export CLOUDSDK_CONFIG="$HOME/.config/gcloud-tx03v2"`. ADC login **overwrites**
  Application Default Credentials in that configuration directory. This isolates
  lab logins, settings and ADC; the auth plugin uses the same directory. Otherwise
  Terraform/scripts may use another task's active credentials/configuration.
- Public TX/DX forks with repository guardrails applied: required reviewer on
  environment `lab`, deployments from `main` only (PUBLISHING). Exact immutable
  WIF subjects require your owner and numeric owner/repository IDs at bootstrap.
- Review regional Compute Engine/Cloud SQL quotas and trial-account restrictions
  in your console before starting; actual eligibility has not been verified here.
- Estimated time: bootstrap5 min, apply20–40 min, platform10 min, app15 min,
  destroy20–40 min; allow2–3 hours. Managed certificate delegation may take longer.

## 2. Bootstrap (once, locally as Owner)

From the TX clone, after selecting the dedicated gcloud directory:

```bash
export PATH="$PWD/.tools/bin:$PATH"
gcloud auth login
gcloud auth application-default login
gcloud billing projects describe tx03v2-lab-example --format='value(billingAccountName)'
scripts/preflight.sh --project tx03v2-lab-example
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Set project_id, billing_account without prefix, budget_alert_emails,
# github_owner, github_owner_id, tx03v2_repository_id, dx03v2_repository_id.
# For two-US-region DR, choose state_location="US" before this first creation.
terraform init
terraform apply
terraform output -raw backend_hcl > ../envs/lab/backend.hcl
terraform output github_variables_tx03v2
terraform output github_variables_dx03v2
```

Bootstrap enables18 APIs, never disabled on destroy; creates the versioned uniform
private state bucket `tx03v2-tfstate-<suffix>` (`substr(sha1(project_id),0,8)`),
WIF pool/provider, plan/apply/deploy accounts, exact-subject grants and contract
roles. Apply has service admins without Editor, custom `tx03v2LabSecrets` without
general secret reads, and `iam.serviceAccountUser` only on bootstrap-created
`tx03v2-lab-nodes`. It also creates monthly budget5 in billing-account currency,
excluding credits from spend calculation, with50/90/100% actual and100% forecast
alerts to your named recipients and billing administrators.

- `github_owner` has no default; placeholders `your-github-user` and
  `you@example.com` are rejected.
- Trust uses numeric `repository_owner_id`/`repository_id`, with immutable subject
  `repo:<owner>@<owner id>/tx03v2@<repository id>:environment:lab`. Repos created
  after2026-07-15, including new forks, emit this format. Old name-only subjects
  neither match nor protect against deleted-name reuse. Obtain IDs through
  `gh api users/<owner> --jq .id`, `gh api repos/<owner>/tx03v2 --jq .id`, and
  the equivalent DX query; repo-guardrails also prints them.
- Older repos must opt into immutable subject claims (Settings > Actions >
  General > OpenID Connect). Inspect
  `gh api repos/<owner>/tx03v2/actions/oidc/customization/sub`; the prefix needs
  `@<id>`. Renames/transfers change the subject: reapply bootstrap with current IDs.
- At least one monitored `budget_alert_emails` address is required. Without
  `EXCLUDE_ALL_CREDITS`, trial credits could hold counted spend at zero and silence
  the warning. A budget never stops billing.
- Bootstrap state remains local and ignored; back it up privately. Provider ADC
  uses `user_project_override` and the lab quota project (budget API needs one).
- Newly enabled APIs may report `SERVICE_DISABLED` briefly; wait and repeat apply.
- For US regional recovery, set state_location US before creation. Existing buckets
  cannot move; never approve replacement of the state bucket. Follow the private
  backup/lineage/serial/backend migration checks in CONTINUITY.
- Optional bootstrap-state migration: create ignored `backend_override.tf` with
  the empty block below and run
  `terraform init -migrate-state -backend-config="bucket=tx03v2-tfstate-<suffix>" -backend-config="prefix=bootstrap"`.
  Harness reads all Terraform files; backend arguments belong in CLI config.
  Before final teardown, remove the override and migrate back to local.

  ```hcl
  terraform {
    backend "gcs" {}
  }
  ```

## 3. GitHub variables and secrets

Use repository Settings > Secrets and variables > Actions. Plan does not run in
an environment, so its variables must be repository-scoped. Variables appear in
logs and contain no private credentials/operator emails. `LAB_APP_DEPLOYER_MEMBERS`
is a **secret**; workflows additionally mask every member/email. They validate
formats/account/bucket ownership first and redact project/number/suffix/members
as `<PROJECT_ID>`, `<PROJECT_NUMBER>`, `<SUFFIX>`, `<MEMBER>`, `<EMAIL>` in summaries.

FORK step7 shows `terraform output -json github_variables_tx03v2`/DX piped through
jq to private temporary files, then `gh variable set -f`. Choose remaining LAB
inputs below. Set secrets with `gh secret set ... -R <you>/tx03v2`.

### tx03v2

| Variable | Example | Used by | Source/default |
| --- | --- | --- | --- |
| `GCP_PROJECT_ID` | tx03v2-lab-example | all cloud workflows | bootstrap github_variables_tx03v2 |
| `GCP_REGION` | us-central1 | TF_VAR_region/REGION | bootstrap region |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | projects/000000000000/locations/global/workloadIdentityPools/tx03v2-github/providers/github | WIF | bootstrap |
| `GCP_PLAN_SERVICE_ACCOUNT` | tx03v2-gha-plan@tx03v2-lab-example.iam.gserviceaccount.com | plan and its guard | bootstrap |
| `GCP_APPLY_SERVICE_ACCOUNT` | tx03v2-gha-apply@tx03v2-lab-example.iam.gserviceaccount.com | apply/platform/destroy | bootstrap |
| `TF_STATE_BUCKET` | tx03v2-tfstate-00000000 | plan/apply/destroy | bootstrap |
| `LAB_DEPLOY_SERVICE_ACCOUNT` | dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com | TF_VAR_deploy_service_account | bootstrap |
| `LAB_FINOPS_PRICING_JSON` | reviewed regional worksheet | cost gate; optional OpenCost installation | **required before plan/apply**, resource maxima plus nine external categories; FINOPS |
| `LAB_COST_BUDGET_USD` | chosen decimal USD budget | cost gate | required |
| `LAB_COST_HOURS` | duration<=24 | cost gate | required |
| `LAB_COST_EXPIRES_AT` | UTC timestamp in next24h | cost gate | required, within budgeted duration; refresh each round |
| `LAB_ENABLE_WAF` | true | TF_VAR_enable_waf | true |
| `LAB_DB_TIER` | db-g1-small | TF_VAR_db_tier | db-g1-small; f1-micro rejected |
| `LAB_DB_PROFILE` | core/ha/dr | TF_VAR_db_profile | core; dr creates paid second cluster/replica/services |
| `LAB_HA_DB_TIER` | db-custom-1-3840 | TF_VAR_ha_db_tier | dedicated CPU for HA/DR; shared-core has no HA SLA |
| `LAB_DB_BACKUP_COUNT` | 7 | TF_VAR_db_backup_count | empty:core1, HA/DR7;HA/DR minimum7 |
| `LAB_DB_DELETION_PROTECTION` | true | TF_VAR_db_deletion_protection | false; deliberately disable before destroy |
| `LAB_DB_RETAIN_BACKUPS_ON_DELETE` | true | TF_VAR_db_retain_backups_on_delete | false; retained copies keep billing |
| `LAB_DR_REGION` | us-east1 | TF_VAR_dr_region | different from primary, DR only |
| `LAB_DR_NODES_SUBNET_CIDR`, `LAB_DR_PODS_CIDR`, `LAB_DR_SERVICES_CIDR`, `LAB_DR_CONTROL_PLANE_CIDR` | 10.40.0.0/20, 10.42.0.0/16, 10.43.0.0/20, 172.31.255.224/28 | TF_VAR_dr_* | private, internally nonoverlapping secondary ranges |
| `LAB_DNS_ZONE_NAME` | example.com | TF_VAR_dns_zone_name | empty; own/delegate public zone, required for full with hostname |
| `LAB_APP_DOMAIN_NAME` | lab.example.com | TF_VAR_app_domain_name | empty; subdomain, both DNS inputs required together |
| `LAB_ENABLE_MANAGED_MESH` | true | TF_VAR_enable_managed_mesh | false; fleet membership/managed mesh, required for full |
| `LAB_ACTIVE_REGION` | primary/secondary | TF_VAR_active_region | primary; DR DNS switch only after fencing/promotion/data acceptance |
| `LAB_CONTINUITY_NOTIFICATION_CHANNELS` | JSON list of existing project channel names | TF_VAR_continuity_notification_channels | []; no tokens, replica-lag notifications |

| Secret | Example/use | Default |
| --- | --- | --- |
| `LAB_APP_DEPLOYER_MEMBERS` | JSON `["user:you@example.com"]`, user:/serviceAccount: laptop operators; no group: | []; Terraform IAM and platform RoleBinding must use same list |
| `SLACK_WEBHOOK_URL` | incoming webhook for full alerts | optional; never a public variable |

`TF_VAR_github_owner` comes from `github.repository_owner`. Other inputs use
`terraform/envs/lab/variables.tf` defaults; changing an unexposed input (such as
nodes_subnet_cidr) requires a reviewed workflow TF_VAR addition. Continuity
profiles/isolated restore/promotion are in CONTINUITY. Price HA/DR before apply;
standby cluster/replica incur charges even with no app traffic.

### dx03v2

| Variable | Example | Source |
| --- | --- | --- |
| `GCP_PROJECT_ID` | tx03v2-lab-example | bootstrap github_variables_dx03v2 |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | projects/000000000000/locations/global/workloadIdentityPools/tx03v2-github/providers/github | same output |
| `GCP_DEPLOY_SERVICE_ACCOUNT` | dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com | same output |

DX deploy uses its own protected lab environment and immutable DX subject, then
reads remaining values from Parameter Manager. No service-account key secret.

## 4. Apply

1. Run terraform-plan from main, or a same-repo Terraform PR. Review the redacted
   plan summary/artifact (retained7 days) and cost-gate result. Plan has no lab
   environment approval and cannot write state locks.
2. Run terraform-apply and approve lab. The job saves, estimates and applies its
   own plan in the same run, then summarizes outputs. DR also synchronizes current
   primary secret values to regional containers; it does not generate a new
   unrelated password for the existing database.

Local Owner/ADC alternative, from the clone root:

```bash
cp terraform/envs/lab/terraform.tfvars.example terraform/envs/lab/terraform.tfvars
terraform -chdir=terraform/envs/lab init -backend-config=backend.hcl
terraform -chdir=terraform/envs/lab plan -out=tfplan
# Export FINOPS_PRICING_JSON, COST_BUDGET_USD, COST_HOURS, COST_EXPIRES_AT
# using the same reviewed values as the repository LAB_* cost variables.
bash scripts/cost-workflow.sh gcp us-central1
terraform -chdir=terraform/envs/lab apply tfplan
terraform -chdir=terraform/envs/lab output
```

Use the actual selected region for the gate. Plan JSON is private, never an
artifact. For manual DR apply, also run `scripts/sync-dr-secrets.sh` with the
actual dr_db_hostname as explained in CONTINUITY; repeat after primary rotation.
Apply creates VPC/node subnet/secondary ranges, Router/NAT, reserved Gateway
address, Autopilot, node grants, random-suffix Cloud SQL/PSC/private SQL DNS, two
primary secrets, registry, optional WAF, 18-key contract and IAM. HA/DR/full inputs
add their documented resources. Node identity itself is created by bootstrap.

## 5. Platform

Run platform with action=install, target=primary | secondary, profile=core | full and
optional finops; approve lab. Identity is apply/container.admin via DNS endpoint,
without runner IP allowlists. Installer:

1. Renders validated contract project/region/store/deployer plus operator emails
   before installing; group members rejected.
2. Creates temporary kubeconfig with --dns-endpoint and checks API /readyz.
3. Fetches ESO2.12.0 by pinned OCI tag/manifest digest/archiveSHA256; installs in
   external-secrets with watcher wait/rollback-on-failure, 15minute timeout.
4. Applies app/observability namespaces, Role/RoleBinding/store with up to five
   attempts while ESO webhook starts.
5. Verifies Collector chart0.176.0 archive and installs in observability with
   project/direct ServiceAccount identity to Cloud Trace.
6. Waits for gcp-secret-manager Ready, proving ESO reached Secret Manager.

### Full profile (optional)

Core is default. Full adds persistent observability, cert-manager, ArgoCD, Gatekeeper,
Kyverno, TrivyOperator, Velero and Chaos controller, with app managed mesh. Autopilot
omits upstream ambient, node-exporter, Trivy nodecollector and privileged Chaosdaemon.
Cloud Chaos uses API PodChaos pod-kill; mesh fault injection supplies HTTP faults/
latency (ADR51). Full uses gitops/gcp or secondary gitops/gcp-dr; deployment writes
the image revision and Argo syncs. UI access uses kubectl port-forward.

**Installer refuses full before installation unless:**

1. enable_managed_mesh=true applied and fleet member control-plane ACTIVE:
   `gcloud container fleet mesh describe --project <id>`.
2. DNS zone/hostname applied, output dns_name_servers delegated at registrar,
   and certificate ACTIVE:
   `gcloud certificate-manager certificates describe tx03v2-lab-app --location=global --project <id> --format='value(managed.state)'`.
3. App promotion is signed by the fork main deploy-gcp.yml identity; Kyverno
   deliberately refuses unsigned/wrong-identity images.

Trivy/Kyverno direct ServiceAccounts get registry-only Reader without keys.
A missing report means scan did not run. Live Application stores real overlay,
images/parameters; public GitOps branch contains only revision/example parameters.

### Domain, HTTPS and mesh (R8, not run in the cloud (v2))

```bash
gh variable set LAB_DNS_ZONE_NAME -b example.com -R <you>/tx03v2
gh variable set LAB_APP_DOMAIN_NAME -b lab.example.com -R <you>/tx03v2
gh variable set LAB_ENABLE_MANAGED_MESH -b true -R <you>/tx03v2
# Apply, then delegate output dns_name_servers at your registrar.
```

Issuance starts after delegation resolves and may take minutes/hours; it requires
your domain and remains unrun in v2. Full Gateway443 uses CertificateMap
tx03v2-lab-app;HTTP redirects. Destroy deletes zone/records/cert/mesh, not your domain
registration. Fixed control-plane /28 defaults172.31.255.240/28;change before first
apply if it overlaps existing networks. Later changes recreate the cluster.

Slack is optional secret SLACK_WEBHOOK_URL. Full's Terraform Velero bucket is
US multiregion in DR; CSI snapshots protect PD volumes, Cloud SQL native backup
is separate. Schedule retains35 days; see CONTINUITY for restore/GC. No full→core
in-place transition:destroy/recreate.

Upgrade notes:

- Pre-R8:reapply bootstrap for certificatemanager/mesh APIs and
  certificatemanager.editor/gkehub.admin;fixed control-plane range may recreate
  an existing cluster.
- Pre-v2 contract:reapply bootstrap for cloudtrace API and cloudtrace.agent in
  grant condition before lab apply.
- R4/DR:reapply bootstrap for tx03v2VeleroBucket metadata role and both exact names
  tx03v2-lab-velero-<project_id>/tx03v2-lab-dr-velero-<project_id>;old primary-only
  condition cannot manage DR bucket. No object read/write grant.
- Reinstall full:new LabGcpAllowedImages/allowed-repos is applied before removing
  old LabAllowedRepos/allowed-repos. Post-injection app/migration/other containers
  require app digests;only istio-proxy/istio-validation with exact
  gcr.io/gke-release/asm/proxyv2 explicit tag/digest is exempt. Review new managed
  paths/names;never allow all gcr.io. Google chooses proxy version;fixture does
  not pin live cluster. Kubernetes-mode Kyverno verifies regular/init/ephemeral
  app groups without requiring fork attestation for Google proxy. Runtime
  Autopilot admission remains to validate.
- Pre-R3.16 node identity moved from lab to bootstrap. Deliberately remove/import
  state ownership before applying either:

  ```bash
  terraform -chdir=terraform/envs/lab state rm google_service_account.nodes
  terraform -chdir=terraform/bootstrap import google_service_account.nodes \
    projects/<project_id>/serviceAccounts/tx03v2-lab-nodes@<project_id>.iam.gserviceaccount.com
  terraform -chdir=terraform/bootstrap apply
  ```

Google manages Gateway controller. Local Owner platform commands:

```bash
make tools
gcloud auth login
export GCP_PROJECT_ID=tx03v2-lab-example
APP_DEPLOYER_MEMBERS='[]' platform/install.sh
export KUBECONFIG=/tmp/tx03v2-lab.kubeconfig
gcloud container clusters get-credentials tx03v2-lab --location us-central1 --project "$GCP_PROJECT_ID" --dns-endpoint
kubectl get gatewayclass gke-l7-global-external-managed
kubectl get clustersecretstore gcp-secret-manager
kubectl -n dx03v2 get role,rolebinding
```

Operator list must match Terraform app_deployer_members:IAM from Terraform,
RoleBinding from platform.

## 6. App deployment (dx03v2, not run in the cloud (v2))

Complete DX CI on current main, then manual publish-images with ci_run_id. Deploy
uses the successful publication release_run_id, target, platform_profile and
deploy_mode=auto | gitops | push. It verifies source CI, digests, SPDX hashes/attestations
before lab approval/WIF; promotes exact digest with crane, never rebuilds; reads
18 contract keys and validates Cloud SQL root before creating cloudsql-ca.

Auto chooses Argo when Application exists, otherwise direct apply;authorization/
connection errors fail closed. GitOps configures full overlays gcp-waf-full or
gcp-full (core variants without full), images/real parameters on liveApplication,
publishes public example-only gitops/gcp or gitops/gcp-dr, then waits sync, ESO,
rollouts and programmed Gateway at contract address. Push applies directly.
Both finish smoke. Secondary deployment neither fences nor promotes DB nor
switches DNS;follow CONTINUITY first.

Laptop deployment requires a verified signed release bundle as described by
DX RUNBOOK/script;it is not a build-and-push shortcut. Add your user to secret
LAB_APP_DEPLOYER_MEMBERS, apply IAM, then rerun platform RoleBinding before use.

## 7. Smoke test

Expected, not cloud-verified (core examples):

```bash
terraform -chdir=terraform/envs/lab output -raw gateway_address
kubectl -n dx03v2 get gateway dx03v2
curl -fsS "http://<GATEWAY_ADDRESS>/healthz"
curl -fsS "http://<GATEWAY_ADDRESS>/api/info"
kubectl -n dx03v2 get externalsecrets
kubectl -n dx03v2 get healthcheckpolicies,gcpbackendpolicies
```

Gateway should be Programmed at the output address;ESO should show SecretSynced.
Full uses the verified HTTPS hostname and HTTP301. With WAF, a SQL-injection probe
should return403, for example:
`curl -s -o /dev/null -w '%{http_code}\n' "http://<GATEWAY_ADDRESS>/api/info?id=1%27%20OR%20%271%27=%271"`.
LB may need minutes after Programmed. Record actual results.

After requests, Cloud Trace Explorer should show dx03v2-api route/PostgreSQL spans.
If absent after minutes, inspect Collector logs;googlecloud PermissionDenied points
to its direct-principal cloudtrace.agent grant. This also remains cloud-unrun.

### Velero restore exercise (full only)

Use a disposable namespace with no app data. This simple exercise proves objects,
not Cloud SQL or volume bytes;follow the additional CSI checksum restore in
CONTINUITY to validate actual volume recovery.

```bash
kubectl create namespace velero-restore-drill
kubectl -n velero-restore-drill create configmap restore-proof --from-literal=proof=tx03v2
velero backup create tx03v2-restore-drill --include-namespaces velero-restore-drill --wait
kubectl delete namespace velero-restore-drill
kubectl wait --for=delete namespace/velero-restore-drill --timeout=180s
velero restore create --from-backup tx03v2-restore-drill --wait
kubectl -n velero-restore-drill get configmap restore-proof -o jsonpath='{.data.proof}'; echo
kubectl delete namespace velero-restore-drill
velero backup delete tx03v2-restore-drill --confirm
```

Expect tx03v2. On failure inspect backup/restore describe, BackupStorageLocation,
Velero SA WIF grants;correct and repeat with a fresh backup name.

## 8. Destroy

Before starting, review DB deletion protection/retained backups and both Velero
destinations when DR is enabled. Explicit Owner cleanup of approved backup data
is required because force_destroy=false. For each owned bucket, review its exact
name, retention and recovery requirements before emptying:

```bash
VELERO_BUCKET="$(terraform -chdir=terraform/envs/lab output -raw velero_bucket_name)"
gcloud storage rm --recursive "gs://${VELERO_BUCKET}/**"
gcloud storage ls "gs://${VELERO_BUCKET}/"
```

Repeat only for the exact secondary bucket when present. Retained PD snapshots
need separate reviewed cleanup. No backup data is silently deleted by Terraform.

Run terraform-destroy, typed confirmation **destroy tx03v2-lab**, approve lab.
scripts/destroy.sh:

1. Inventories/uninstalls owned primary and optional secondary runtimes. Uninstall
   removes app namespace, waits Gatewayfinalizer/region-owned NEGs (up to900s each),
   full releases/PVCs and ESO. Requires contract target/project label, temporary
   kubeconfig;CLUSTER_NAME cannot retarget it.
2. On unavailable endpoint/controller/timeout or surviving controller pieces,
   deletes only lab-named/network-owned forwarding rules, proxies, URLmaps, backends,
   healthchecks, NEGs/firewall in dependency order via Google APIs. Warning records
   incomplete platform uninstall. Other project resources are never targeted.
3. Runs Terraform destroy even after uninstall failure.
4. Always runs leftovers --project <id> --retry-for900, including after destroy failure.

Any error is logged/fails the job. Diagnose/correct/repeat. destroy-flow tests
this offline with simulatedCLIs. Local command:

```bash
export TF_STATE_BUCKET=tx03v2-tfstate-<suffix> REGION=us-central1
# Also provide the same TF_VAR_* inputs used to create the lab.
scripts/destroy.sh --project tx03v2-lab-example
```

Interrupted apply/destroy may leave envs/lab/default.tflock. The next command
reports Error acquiring the state lock and generation ID. Only after proving no
other Terraform executor exists, use destroy workflow force_unlock_id or local
destroy.sh --project <id> --force-unlock <ID>. Unjustified unlock permits competing
state writes. A partially created resource absent from state may cause409already
exists;deliberately import it or remove it after ownership review, then repeat.

Bootstrap remains:APIs/state/pool/identities/budget. Default SQL backups disappear
with instance, unless explicit retention was selected;instance name remains
reserved up to a week, next creation uses a random suffix.

## 9. Leftovers

Every gcloud inventory names explicit --project;neither shell variables nor active
configuration chooses the project. Lab ownership:project=tx03v2, label/name
tx03v2-lab*, labnetwork, or dx03v2 Gateway gkegw1/k8s1 controller piece. Unrelated
resources show INFO/not the lab's, never deletion candidates. Workflow identity
may lack some reads:UNCHECKED warns without changing exit status. Complete the
inventory locally as Owner:

```bash
gcloud auth login
scripts/leftovers.sh --project tx03v2-lab-example --retry-for 900
```

BILLABLE means ongoing cost/exit1;ORPHANED is free but obstructs later rounds;
INFO covers bootstrap/disabled APIs/unrelated work;UNCHECKED means no proof.
Exit2 means auth/missingproject/APIerror, never a clean bill of health.

Manual cleanup examples below are only for confirmed BILLABLE/ORPHANED lab
resources. Recheck label/prefix/network. Delete LB dependency order:

```bash
p=tx03v2-lab-example
gcloud compute forwarding-rules delete <NAME> --global --project "$p"
gcloud compute target-http-proxies delete <NAME> --global --project "$p"
gcloud compute url-maps delete <NAME> --global --project "$p"
gcloud compute backend-services delete <NAME> --global --project "$p"
gcloud compute health-checks delete <NAME> --global --project "$p"
gcloud compute network-endpoint-groups delete <NAME> --zone <ZONE> --project "$p"
gcloud compute addresses delete tx03v2-lab-gateway --global --project "$p"
gcloud compute disks delete <NAME> --zone <ZONE> --project "$p"
gcloud compute firewall-rules delete <NAME> --project "$p"
gcloud sql instances delete <NAME> --project "$p"
```

For full HTTPS, inventory also covers HTTPS proxies/certificates/maps;follow actual
reported dependencies rather than guessing. Repeat until no BILLABLE item remains.

## 10. Bootstrap teardown (after the final round)

1. Lab destroyed, Owner-run leftovers clean.
2. Migrate bootstrap state back to local if necessary (section2).
3. In bootstrap, change state_protection=false and apply, only lifting bucket
   deletion_policy protection.
4. Review/back up then empty all state generations:
   `gcloud storage rm --all-versions "gs://tx03v2-tfstate-<suffix>/**"`.
5. Bootstrap destroy removes bucket, pool/provider, three CI identities plus node
   identity, custom roles, notification channels, budget. APIs remain enabled/free.
   Pool ID stays soft-deleted30 days (ARCHITECTURE, Names retained after deletion).
6. Final dedicated-project deletion:
   `gcloud projects delete tx03v2-lab-example`;disabled/pending deletion30 days.
7. Recheck Cloud Billing the following day.

## 11. Recording evidence

Open Cloud run report:date, region, billing type/trial, TX/DX commits, Terraform/GKE
versions, WAF/DBprofile/tier, steps, duration, actual Cloud Billing costs bySKU and GKE
fee/credit treatment, issues and redacted leftovers. README status changes only
with this evidence. Never publish billing IDs, secrets, planJSON or state.

## 12. Troubleshooting

These are likely causes, not v2 cloud-verified outcomes.

| Symptom | Likely cause | Action |
| --- | --- | --- |
| SERVICE_DISABLED/API never used | bootstrap absent or API propagating | apply bootstrap, wait/retry |
| ADC quota-project error | missing quota project | gcloud auth application-default set-quota-project tx03v2-lab-example |
| Budget403 | no billing-account role | billing admin/costs manager, section1 |
| auth getAccessToken denied | subject mismatch, wrong environment/owner/ID/variable | compare immutable subject, bootstrap IDs, lab and outputs |
| Backend init403 | wrong service account/bucket project | bootstrap outputs |
| DNS endpoint does not answer/access denied | missing clusterViewer/connect or RBAC | deploy grants, rerun platform RoleBinding |
| Cannot render contract | apply absent/parameterAccessor missing | apply/check roles |
| Store Ready timeout | ESO cannot read Secret Manager | describe store, secret grants, GKE WIF pool |
| Uninstall NEG timeout | controller still deleting LB | retry, inspect NEG inventory |
| WIF pool already exists | prior bootstrap soft-deleted30 days | deliberately undelete/import or another project |
| Apply PERMISSION_DENIED | documented role set missing an actual permission | find official predefined role or gcloud iam roles list filter;review apply_extra_project_roles, bootstrap again, report. Owner/ProjectIAMAdmin/service-account roles rejected |
| leftovers exit2 | no login/missing project/APIerror | correct/retry;never treat as empty |
| preflight exit1 | foreign cluster/DB/secret | dedicated project;error names resource |
| State lock | interrupted executor | section8, prove no executor before typed force unlock |
| auth fails after rename/transfer | immutable subject includes changed name/ID | bootstrap current owner/IDs |
| Full mesh notACTIVE | disabled/provisioning/API absent | fleet mesh describe, bootstrap APIs/apply, wait |
| Certificate notACTIVE | delegation/CNAME not resolved/not your domain | delegate nameservers, inspect DNSauthorization/dig CNAME, wait PROVISIONING |
| Pod FailedCreate/admission denied/timeout | wrong digest/attestation or unreachable webhook | describe ReplicaSet, Kyverno pods, webhook firewall;redeploy signed promotion |
| monitoring PVCs remain | pod still mounts volume | inspect pods/PVCs, wait releases/retry, inspect leftover disks |
