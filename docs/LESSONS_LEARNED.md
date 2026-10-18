# Lessons from the GCP v1 lab (tx03 and dx03)

> These lessons preserve each round's initial decisions and implementation snapshot. Current
> HA/backup/PITR/DR is in [CONTINUITY.md](CONTINUITY.md); capacity, OpenCost/VPA/Spot and estimates
> are in [FINOPS.md](FINOPS.md). Historical exclusions do not override later R7–R10 deliveries.
> “In v2 at the initial baseline” below is historical, including its older versions/key counts.

This document records what failed in GCP v1 (tx03/dx03, master), why it failed and the original
v2 response. It supports operating/evolving the pair without repeating those mistakes.
Private/archived v1 repositories are not linked.

Sources: 28 deleted Git-history notes (25 TX, three DX; about 11,800 lines), the repositories'
then-current master files and v2 specifications/contracts. Real identifiers became placeholders
(<PROJECT_ID>, <owner>, 203.0.113.x, example.com, <suffix>); no password, token or run ID was copied.

Each lesson follows **What happened in v1 → Lesson → In v2 at the initial baseline**.
Those v2 statements describe source checked by the harness (`verified in CI`) and retain
`not run in the cloud (v2)`. DX references describe its own implementation, without cloud evidence.

## Costs and billing

### 1. Budget existed as a module, never as a resource

- What happened in v1: terraform/modules/billing-budget (five thresholds, Pub/Sub and cost-spike
  alert) was never called by root dev; the session note still marked GCP budget alerts pending.
  It was invalid too: a resource.type="global" alert filter without a metric, email channels
  disconnected from the budget, hardcoded USD and billing-account lookup by display name.
- Lesson: budget is the first applied/tested lab resource, not just documentation.
- In v2 at the initial baseline: bootstrap google_billing_budget scoped to the project,
  budget_amount default 5 without currency_code, thresholds 0.5/0.9/1.0 and forecast 1.0,
  email through google_monitoring_notification_channel; bootstrap terraform test covers it.

### 2. Invented cost numbers

- What happened in v1: cost-management.yml printed current cost $60–70/month, 65% of a $100 budget,
  and three-month forecasts from hardcoded ranges. The Cloud SQL tier was blank and that budget
  did not exist. Claimed $38–48/month (60%) quick-win savings were never measured.
- Lesson: actual cost comes from Cloud Billing; estimates must identify themselves.
- In v2 at the initial baseline: cost workflows were excluded; bootstrap budget and
  scripts/leftovers.sh BILLABLE/ORPHANED controlled exposure. COSTS labels estimates.
  Later FinOps construction is documented separately.

### 3. Load balancers were the largest fixed cost

- What happened in v1: notes assigned roughly 34% of cost to LB (about $18/month per forwarding
  rule). There were three: Ingress HTTP/HTTPS and an Argo CD LoadBalancer Service/second public IP.
- Lesson: one entry point; every forwarding rule adds cost and attack surface.
- In v2 at the initial baseline: one DX-created gke-l7-global-external-managed Gateway using
  reserved tx03v2-lab-gateway, HTTP listener 80; no Argo CD at that baseline.

### 4. Destroy left Kubernetes-created orphans

- What happened in v1: validation found 10+ resources outside state: three forwarding rules,
  three backend services, URL map, two target proxies, two managed certificates, three k8s-*
  firewalls and 5/10 GB PVC disks, estimated at $15–25/month if forgotten.
- Lesson: delete controller-owned resources before Terraform, then inspect leftovers.
- In v2 at the initial baseline: platform/uninstall.sh deletes dx03v2, waits for Gateway
  finalization and app k8s1-* NEGs to disappear; destroy ends with leftovers.sh --retry-for 900.

### 5. Add-ons cost more than the app

- What happened in v1: Prometheus/Grafana/Alertmanager were estimated at $26–40/month plus 17 Gi
  PVCs; five idle Istio pods and seven Argo CD pods accompanied a four-pod app using ~10m CPU each.
- Lesson: every lab add-on needs a purpose and accepted cost.
- In v2 at the initial baseline: ESO 2.12.0 with explicit requests and GKE SYSTEM_COMPONENTS/
  WORKLOADS logging only. In-cluster observability, Istio and Argo CD were initially excluded;
  later full profiles supersede that exclusion.

## GKE and networking

### 6. Exposed control plane

- What happened in v1: GKE had no private_cluster_config/master_authorized_networks_config,
  leaving the public IP endpoint open. Example master_authorized_cidrs, enable_private_nodes
  and enable_private_endpoint variables did not exist in the root.
- Lesson: ignored example variables mislead; enforce endpoint restrictions and prove them.
- In v2 at the initial baseline: private nodes, disabled public IP endpoint, no authorized
  CIDRs, IAM-authorized DNS endpoint/get-credentials --dns-endpoint, tested in gke.tftest.hcl.

### 7. Autopilot rejects privileged components

- What happened in v1: Warden denied NET_ADMIN for sidecar/ztunnel, kube-system patching,
  node-exporter hostPath and Trivy webhook wildcard/nodes-proxy rules
  (“GKE Admission Webhook Controller: the following (group,resource) pairs are not allowed”).
- Lesson: check each chart's Autopilot compatibility before workflows/docs.
- In v2: core installs ESO/Collector; full adds compatible charts. Privileged ambient,
  node-exporter, Trivy node collector and Chaos daemon stay outside the GCP profile.
  helm-template-full/kubeconform validate renders; real cloud admission remains unverified.
  The later managed-mesh path is described in current architecture/runbooks.

### 8. Ingress had no IP for over three hours

- What happened in v1: Ingress used container port 3000 instead of Service port 80, lacked NEG
  annotation and referenced a nonexistent ManagedCertificate; no forwarding rule was created.
- Lesson: route to Service ports, define health checks, wait for LB readiness and fail on timeout.
- In v2 at the initial baseline: HTTPRoute /api→api:3000 and /→web:8080, HealthCheckPolicies
  /readyz and /healthz; DX waits for Gateway Programmed and compares its address with gateway/address.

### 9. Cloud Armor attached by script after deploy

- What happened in v1: the app workflow listed k8s1-* backend services by name and attached
  tx03-waf-policy to each; it included 100 requests/minute and adaptive protection.
- Lesson: WAF/backend association must be declarative/versioned; rate limits must allow smoke.
- In v2 at the initial baseline: DX GCPBackendPolicies api/web use contract securityPolicy,
  omitted for none; tx03v2-lab-waf sqli-v33-stable/xss-v33-stable; any rate limit >=300/minute.

### 10. Flat cluster network

- What happened in v1: allow-internal firewall allowed TCP/UDP 0–65535; initial manifests lacked
  NetworkPolicy; database used peering with a reserved /16.
- Lesson: segment exact destinations rather than broad ranges.
- In v2 at the initial baseline: Autopilot Dataplane V2; DX contract NetworkPolicies allow
  web/API ingress from 35.191.0.0/16 and 130.211.0.0/22, API egress to db/endpoint-ip/32:5432
  and DNS to 169.254.20.10.

### 11. Autopilot waits and timeouts

- What happened in v1: pods took 5–10 minutes; Helm exceeded ten minutes, then used twenty without
  --wait. kubectl delete pod --all left zero app pods for ~17 hours without an alarm.
- Lesson: waits need explicit deadlines and visible failures.
- In v2 at the initial baseline: installer helm --wait=watcher --rollback-on-failure with
  15-minute timeout and ClusterSecretStore readiness. Uninstall fails loudly at 900-second
  namespace/NEG deadlines. DX waits for ExternalSecrets Ready, rollouts/Gateway and
  SMOKE_WAIT_SECONDS=900; not run in the cloud (v2).

## Cloud SQL

### 12. PostgreSQL 16 selected Enterprise Plus

- What happened in v1: three applies failed with Invalid Tier (db-f1-micro) for ENTERPRISE_PLUS,
  followed by db-custom-1-3840/db-perf-optimized-N-2 attempts (~$150/month).
  Downgrading to PostgreSQL 14 worked; the then-current root reverted to POSTGRES_16/db-g1-small
  without edition, recreating the initial risk on fresh deployments.
- Lesson: configure edition explicitly instead of trusting version-dependent defaults.
- In v2 at the initial baseline: PostgreSQL 17, edition=ENTERPRISE, db-g1-small default.
  Validation rejects Enterprise Plus tiers and db-f1-micro (25 connections, below four
  replicas × pool 10 plus migration).

### 13. Partial creation and fixed names

- What happened in v1: failed creation left tx03-postgres-<suffix> outside state, requiring import;
  apply then checked that fixed name with gcloud sql instances describe.
- Lesson: names belong in code; inventory after failure before retrying.
- In v2 at the initial baseline: two-byte random_id suffix because deleted SQL names can remain
  blocked for up to a week; leftovers lists instances and retained backups.

### 14. Special-character passwords and passwords in docs

- What happened in v1: a 32-character symbolic password failed pipeline authentication (FATAL
  28P01). It was manually replaced by 24 alphanumerics and saved in GitHub; both passwords were
  pasted into APPLICATION_DEPLOYMENT.md/STATUS.md (<REDACTED>).
- Lesson: passwords should not pass through shell substitutions/docs; one generator feeds DB/vault.
- In v2 at the initial baseline: ephemeral 40-alphanumeric random_password feeds Cloud SQL and
  Secret Manager through write-only *_wo arguments, outside state/plan; ESO delivers it to pods.

### 15. Divergent Secret keys

- What happened in v1: workflow created host/port/name/user/password while Deployment expected
  database/username, causing CreateContainerConfigError. Earlier create-secret --dry-run piped
  to apply failed with “no objects passed to apply”.
- Lesson: key names are a machine-checked contract.
- In v2 at the initial baseline: secret JSON username/password/host/port/dbname and db-credentials
  DB_* keys in the contract. contract-parameter checked the original 15 parameter keys;
  DX contract-app checked consumption with green CI. Current key counts are in CONTRACT.

### 16. TLS without server verification

- What happened in v1: private peering IP/ssl_mode=ENCRYPTED_ONLY, but app used neither CA nor
  server-name verification.
- Lesson: encryption alone does not authenticate the database.
- In v2 at the initial baseline: PSC-only connectivity, private DNS and shared CA with instance
  DNS in the certificate. DX verify-full accepts a regional CA bundle only with the contract's
  root SHA-256; cloud execution remained unverified.

### 17. “Production-ready” backups never restored

- What happened in v1: 30 backups/seven-day PITR and daily Kubernetes Secrets exported as base64
  artifacts; restore-test checkbox remained unchecked.
- Lesson: backup without tested restore is an assumption; never export secrets in artifacts.
- In v2 at the initial baseline: one retained backup, retain_backups_on_delete=false; backup/
  restore workflows initially excluded. Current continuity implementation supersedes this limit.

## IAM, WIF and CI

### 18. Manual WIF trusted the whole owner

- What happened in v1: gcloud-created pool/provider outside Terraform trusted repository_owner
  by name; repository principalSet needed another manual DX binding after failure.
- Lesson: federation belongs in code and must restrict repository and subject.
- In v2 at the initial baseline: tx03v2-github bootstrap pool, owner/two-repository conditions,
  exact PR/main/environment:lab workloadIdentityUser subjects, proven by identities.tftest.hcl.
  Later immutable-ID hardening is recorded in current contracts.

### 19. One service account accumulated every role

- What happened in v1: github-actions-sa served plan/apply/deploy/Istio/costs. Permissions grew
  after errors such as artifactregistry.repositories.create and iam.serviceAccounts.getAccessToken
  until compute.admin, container.admin, self serviceAccountTokenCreator, serviceUsageAdmin and
  unconditioned projectIamAdmin; ASM also requested gkehub.admin.
- Lesson: one identity per function; IAM grant authority must be conditional.
- In v2 at the initial baseline: tx03v2-gha-plan read-only/-lock=false;
  tx03v2-gha-apply projectIamAdmin constrained by modifiedGrantsByRole hasOnly matching the
  root's role list; dx03v2-gha-deploy registry writer, clusterViewer and parameterAccessor.
  Both roots have roles.tftest.hcl.

### 20. New workflows repeated three authentication errors

- What happened in v1: missing secrets produced “must specify exactly one of
  workload_identity_provider or credentials_json”; missing id-token: write prevented token
  injection; missing gke-gcloud-auth-plugin broke access across infra/app/observability/Istio,
  sometimes for three consecutive failures.
- Lesson: use a validated job pattern rather than manual copying.
- In v2 at the initial baseline: first-step vars validation, token-write only for protected
  lab cloud jobs and guarded same-repository plan; pinned auth/setup-gcloud 588.0.0 with the GKE
  plugin and harness policy-workflows.

### 21. CI only ran ls

- What happened in v1: ci.yml listed Markdown, workflows and Terraform, then printed
  “Repository is valid!” without fmt/validate/lint/tests.
- Lesson: green CI must mean something.
- In v2 at the initial baseline: static/test harness, HARNESS_STRICT=1/zero SKIP,
  mocked terraform test, Google tflint, Trivy config and shellcheck.

### 22. Plan targeted main while the repo used master

- What happened in v1: terraform-plan listened for PRs to main while default branch was master,
  so no PR received a plan.
- Lesson: verify triggers and the default branch together.
- In v2 at the initial baseline: main with versioned ruleset; plan subject covers PRs/main.

## Terraform and state

### 23. Deleting the lock before every apply

- What happened in v1: canceled/timed-out runs left locks, blocking five or more executions.
  The workaround unconditionally removed default.tflock with continue-on-error before apply,
  deleting legitimate locks too.
- Lesson: never remove locks automatically; force-unlock <ID> is a deliberate operator decision.
- In v2 at the initial baseline: read-only unlocked plan and apply storage.objectUser behind
  lab. Workflow policy rejected blanket lock-removal commands. The later destroy workflow's
  explicit reviewed force_unlock_id recovery is documented in RUNBOOK.

### 24. Plan and apply in one job without review

- What happened in v1: apply planned with detailed-exitcode then immediately applied; offered
  nonexistent prod directory; destroy used refresh=false/auto-approve. An apply waited over
  16 minutes for interactive service_account_email.
- Lesson: reviewed plans, validated variables and no interactive pipeline input.
- In v2 at the initial baseline: separate PR/manual terraform-plan, protected reviewed lab apply
  of that job's saved plan, TF_INPUT=0/validation, typed destroy confirmation, platform uninstall
  and leftovers.

### 25. Local and CI execution mixed

- What happened in v1: personal local applies created resources outside the pipeline; Already
  exists 409 errors and two manual imports followed, breaking workflow idempotence.
- Lesson: define the executor for each root.
- In v2 at the initial baseline: human Owner/laptop bootstrap with documented local state;
  lab mutations through plan/apply workflow identities. Read-only local plan inspection does
  not authorize another local apply.

### 26. Loose backend and versions

- What happened in v1: hardcoded GCS bucket also overridden by backend-config; destroy could
  delete state/all versions. Provider ~>6.50, Terraform >=1.9.0 and no committed lockfile.
- Lesson: protect state and make builds reproducible.
- In v2 at the initial baseline: empty backend "gcs" and backend.hcl.example; versioned
  tx03v2-tfstate-<suffix>, force_destroy=false/deletion_policy=PREVENT until reviewed teardown,
  outside lab destroy. Google 8.6.0/random 3.9.1 in multiplatform locks, constraints ~>8.6/~>3.9.

### 27. Merge broke destroy.yml

- What happened in v1: cleanup had an unclosed echo quote followed by pasted older code; Bash
  could not parse it and continue-on-error hid the failure.
- Lesson: shell logic belongs outside YAML with static analysis.
- In v2 at the initial baseline: scripts/platform shell checked by shellcheck, actionlint
  runs shellcheck on run blocks, leftovers has meaningful exit codes.

## Service mesh and GitOps

### 28. README claimed mTLS with PERMISSIVE and no sidecars

- What happened in v1: PeerAuthentication was PERMISSIVE and injection never worked (zero
  sidecars), so no mTLS existed.
- Lesson: docs claim only verified behavior.
- In v2 at the initial baseline: mesh initially excluded; contract used explicit verified-locally/
  not-run-in-cloud labels. Later managed mesh is covered by current R8 documentation.

### 29. Three blocked mesh approaches

- What happened in v1: sidecar Init:CrashLoopBackOff from iptables validation/NET_ADMIN denial;
  ambient denied ztunnel NET_ADMIN/kube-system patching; ASM lacked serviceusage.services.enable/
  gkehub.memberships.create. Five or more attempts produced about 2,400 documentation lines.
- Lesson: prove viability in a small spike before workflows/guides. Later troubleshoot-pods/
  istio-fix-sidecar/forced-delete workflows treated symptoms only.
- In v2 at the initial baseline: mesh initially excluded; Dataplane V2 NetworkPolicy segmented
  traffic. Current supported managed mesh supersedes that early exclusion.

### 30. Argo CD referenced a nonexistent path

- What happened in v1: dx03-app synced infra k8s/application at HEAD with prune/selfHeal, but the
  path never existed. The actual app workflow also owned the namespace, and an insecure Argo
  server was exposed by LoadBalancer.
- Lesson: one deployment owner/path per namespace.
- In v2 at the initial baseline: Argo initially excluded; DX alone wrote the namespace through
  dx03v2-deployer/contract-platform. Later full GitOps ownership is documented separately.

## Application and deployment

### 31. Client dependencies would not install

- What happened in v1: npm ci failed EUSAGE without lockfile; Dockerfiles switched to npm install.
  A *.json ignore then hid package.json, breaking Docker checksums. The then-current client
  combined eslint ^8.55 with react-refresh ^0.5.2 requiring eslint 9, causing ERESOLVE.
- Lesson: commit locks, run npm ci and use the same local/remote build.
- In v2 at the initial baseline: copy green-CI DX02 api/web, exact versions and verify/build
  in the DX03 development container.

### 32. NODE_ENV=dev stopped the backend

- What happened in v1: ConfigMap changed production to dev only to alter a UI label, but config
  accepted development/test/staging/production and terminated with Invalid NODE_ENV "dev".
- Lesson: separate the displayed environment from Node execution mode.
- In v2 at the initial baseline: APP_ENV=lab in GCP app-config, without reusing NODE_ENV.

### 33. Probe depended on sed

- What happened in v1: readiness sent a literal METRICS_TOKEN_PLACEHOLDER also stored in Secret;
  without deployment sed, health/ready returned 401 and pods stayed unready.
- Lesson: health/probes do not require secrets; secrets come from Secrets.
- In v2 at the initial baseline: contract /readyz API and /healthz web; ADMIN_TOKEN only via
  ExternalSecret app-secrets.

### 34. UI read removed API fields

- What happened in v1: health returned only status=alive after details moved to token-protected
  health/ready, while App.tsx still read health.memory.used/health.database.*. The same
  Cannot read 'used' TypeError had appeared in deployment #42.
- Lesson: change API/UI together with end-to-end tests.
- In v2 at the initial baseline: same DX02 app with integration tests, 12/12 smoke and kind e2e;
  SMOKE_EDGE=gke covers Gateway behavior in DX03.

### 35. Build-time API URL

- What happened in v1: empty VITE_API_URL was not substituted and browsers called localhost:3000.
  window.location.origin replaced it, accompanied by a comment containing a real public IP.
- Lesson: same origin behind the LB; no real addresses in source.
- In v2 at the initial baseline: /api and / on one HTTPRoute; policy-identifiers permits only
  placeholders and documented ranges.

### 36. Mutable images and GitHub cloud secrets

- What happened in v1: latest/SHA tags on floating node:20-alpine/nginx:alpine bases; DB_PASSWORD/
  DB_HOST in GitHub and create-secret inside deploy. First deploy took twenty runs/nineteen
  failures; UI worked only after forty-four deployments.
- Lesson: immutable commit-addressed images; deployment must not handle database secret values.
- In v2 at the initial baseline: immutable Artifact Registry tags, 40-character SHA/reuse,
  linux/amd64 and DX Trivy gate. Deploy has no Secret Manager grants
  (repository_and_secret_grants). Later signed digest-promotion details are in CI_SECURITY.

## Process and documentation

### 37. Status before evidence

- What happened in v1: notes claimed production readiness, full health, 99.9% uptime and
  Lighthouse 95+ without measurements; the same note called the DB connected with a different
  user from Terraform.
- Lesson: status requires reproducible evidence.
- In v2 at the initial baseline: explicit contract-verification/status tables and RUNBOOK for
  cloud behavior.

### 38. Identifiers and secrets in Markdown

- What happened in v1: notes contained project ID/number, service-account email, bucket names,
  public IPs/domain and two DB passwords; one DX note exposed the project ID without redaction.
- Lesson: machine-check public examples for placeholders only.
- In v2 at the initial baseline: harness policy-identifiers with placeholder/range allowlist;
  gitleaks in harness and pre-commit.

### 39. Trial-and-error CI debugging

- What happened in v1: infrastructure needed eleven runs/ten failures/~four hours; app twenty
  runs/nineteen failures/~three hours; Istio ten-plus failures and a commit per attempt.
  Twenty-five TX notes totaled roughly 10,000 lines before deletion.
- Lesson: validate before pushing and maintain concise documentation.
- In v2 at the initial baseline: pre-push development-container harness; DX deploy tested offline
  with gcloud/kubectl/docker stubs across thirteen scenarios; README/CHANGELOG/CONTRACT/RUNBOOK
  replace session notes. Heavy validation later moved to Actions under the host-resource rule.

## Claims in the notes that could not be confirmed

- $60–70 monthly costs, forecasts/savings: no billing evidence; workflow numbers were fixed text.
- Active budget/Slack alerts: budget module unused and external webhook unverifiable.
- Managed HTTPS/301 redirect: manifests existed; cloud behavior cannot be checked here.
- Daily PITR backups/tested restore: module configuration existed but no restore was recorded.
- Cloud Armor on every backend: depended on an imperative workflow step, without declared state.
- “Final idempotent test in 1m25s” and four healthy pods: no versioned log.
- Conflicting ambient notes claimed compatibility and later denial; the final version said blocked.
- The then-current destroy cleanup could not parse; successful-cleanup notes described an earlier version.
