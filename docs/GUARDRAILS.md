# tx03v2 guardrails

A guardrail combines a rule with its enforcement mechanism, automated wherever
possible. This document lists repository rules, their enforcement and their
limits. Types: `blocking` (fails harness/CI/plan), `alert` (notifies), `process`
(human/agent discipline). Cited tests live under `terraform/*/tests/` and run
through `make test`.

## Rules

| ID | Rule | Reason | Enforcement | Type |
| --- | --- | --- | --- | --- |
| SEC-01 | No repository secrets | Public repository; committed history persists | harness/pre-commit gitleaks | blocking |
| SEC-02 | No real identifiers: project tx03v2-lab-example (plus two test placeholders), number000000000000, billing000000-000000-000000, example.com emails or placeholder-project service accounts; private/RFC5737 IPs or LB35.191.0.0/16, 130.211.0.0/22; repeated-digit GUIDs | Protect projects, billing accounts and people | policy-identifiers scans every Git-visible file, including projects/<id>/ paths | blocking |
| SEC-03 | Ephemeral random_password plus write-only password_wo/secret_data_wo; no random_password/random_string resources except local LOC-01, no plaintext password/secret_data | Values absent from plan/state | policy-terraform; secrets_are_regional_and_write_only, cloudsql_postgres_17_enterprise_psc_only | blocking |
| SEC-04 | GitHub WIF only: pool tx03v2-github, provider condition numeric repository_owner_id/repository_id for owner/both repos, exact immutable repo:<owner>@<id>/<repo>@<id>: subject per workloadIdentityUser, no principalSet/service-account key | No other owner/repository/branch/environment identity; reclaimed names cannot inherit | identities tests pool_and_provider_follow_the_contract/one_grant_per_exact_subject/owner_is_configurable/the_ids_are_numeric; repo-guardrails checks subject; policy-terraform rejects keys/principalSet | blocking |
| SEC-05 | id-token:write only guarded cloud jobs; lab environment for mutations, guarded plan has no environment approval; never ci.yml. No credentials_json, secrets.GCP*/GOOGLE* or credential files in workflows; auth uses vars workload_identity_provider/service_account only | Limit credential acquisition | policy-workflows | blocking |
| SEC-06 | Private nodes; no public control-plane IP, no authorized CIDRs/Google public IPs; IAM-only DNS endpoint, no Kubernetes tokens/certificates there; no0.0.0.0/0 in cloud Terraform. Local pg_hba applies only inside private Docker network | No exposed cluster IP port; IAM required | policy-terraform; autopilot_private_dns_endpoint_gateway | blocking |
| SEC-07 | No organization/folder resources, Owner grants or authoritative IAM bindings/policies | Cannot reach organization or erase other grants | policy-terraform; nothing_for_the_deployer_and_no_owner | blocking |
| SEC-08 | Apply project grants limited by modifiedGrantsByRole to exactly four project-roles roles; lab root grants exactly those | Prevent self-promotion | apply_identity_grants_only_the_lab_project_roles/project_grants_follow_the_contract, lab/otel IAM preconditions | blocking |
| SEC-09 | Read-only plan: project Viewer/SecurityReviewer/ParameterViewer, state objectViewer, no write/impersonation/secret access | Plan runs in PRs | plan_identity_is_read_only | blocking |
| SEC-10 | Cloud SQL PSC only, no public IP/private-services-access; only lab consumer project, encrypted connections/sharedCA/automatic certificate rotation | No Internet DB port, verifiable hostname | policy-terraform rejects ipv4_enabled=true; cloudsql_postgres_17_enterprise_psc_only | blocking |
| SEC-11 | No deployer Secret Manager grant; ESO secretAccessor only on owned lab secrets | Least privilege | repository_and_secret_grants/project_grants_follow_the_contract | blocking |
| SEC-12 | Plan only same-repository PRs (head.repo.full_name == github.repository), GCP_PLAN_SERVICE_ACCOUNT configured | Forks receive no credentials | terraform-plan.yml, policy-workflows | blocking |
| SEC-13 | No allUsers/allAuthenticatedUsers; uniform/private state bucket | No public lab data | policy-terraform; state_bucket_is_private_versioned_and_protected | blocking |
| SEC-14 | Nodes use tx03v2-lab-nodes with defaultNodeServiceAccount/registry-reader, never default Compute Engine account | Default identity may have Editor | cluster_follows_the_contract/project_grants_follow_the_contract | blocking |
| SEC-15 | No bootstrap defaults for github_owner/IDs; reject your-github-user. budget_alert_emails requires at least one real monitored address, rejects you@example.com; numeric owner/repo IDs required | Fork cannot trust original owner accidentally; cost alert reaches operator | variable validations, placeholder_owner_is_refused/placeholder_alert_email_is_refused/an_empty_alert_list_is_refused/the_ids_are_numeric; FORK | blocking |
| SEC-16 | Scripts act only on contract tx03v2-lab with project=tx03v2 label; env CLUSTER_NAME/LAB_NAME cannot retarget. Temporary kubeconfig preserves user's context. Local scripts accept only kind-tx03v2-local | Fork operators may have other clusters/contexts/environment variables | policy-scripts; require_lab_cluster in lib/gcp, require_lab_context in lib/local | blocking |
| SEC-17 | Leftovers requires explicit --project, not shell/gcloud default; lab ownership by project label/name/network or dx03v2 Gateway piece. Other resources INFO/not the lab's | Must not suggest deleting unrelated work, RUNBOOK9 | leftovers-flow simulated mixed project, lab_resource | blocking |
| SEC-18 | Preflight before bootstrap/apply rejects foreign GKE/Cloud SQL/secrets; unreadable inventory never proves dedicated project | Apply has powerful lab-service project roles despite removed Editor/Secret ManagerAdmin; shared project unsupported | preflight-flow, apply Pre-flight step | blocking |
| SEC-19 | LAB_APP_DEPLOYER_MEMBERS is a secret; each cloud workflow masks elements/emails and redacts summaries/plan artifacts | Public logs/artifacts must not expose operator emails | policy-workflows | blocking |
| SEC-20 | Apply has no Editor/Secret ManagerAdmin/project-wide serviceAccountUser; lab service admins, custom secret role without general versions.access, node-only impersonation, two-bucket Velero metadata. Empty apply_extra_project_roles rejects Owner/ProjectIAMAdmin/service-account roles | Compromised approved workflow cannot impersonate arbitrary identities or gain broad unrelated data access. Continuity synchronization separately reads four exact lab secrets | apply_identity_has_the_service_roles_of_the_lab_and_no_editor, secrets_can_be_managed_but_not_read, apply_acts_as_the_node_account_only, apply_manages_velero_bucket_metadata_but_not_backup_objects, extra_roles_*; policy-terraform | blocking |
| SEC-21 | Apply metadata only on tx03v2-lab-velero-<project_id> and tx03v2-lab-dr-velero-<project_id>; tx03v2VeleroBucket create/delete/get/getIamPolicy/setIamPolicy/update conditioned on exact bucket type/names; no object permissions. KSA velero/velero WIF gets bucket-only objectAdmin; no Google key/account/Secret, force_destroy=false | Backup data inaccessible to Terraform workflow; requested-name creation condition reviewed in Storage IAM docs2026-10-16, cloud unrun | bootstrap roles, velero module, velero/roles tests | blocking |
| SEC-22 | Kubernetes-mode Kyverno checks regular/init/ephemeral app images in dx03v2: exact api/web repository SHA256 digests, keyless main deploy-gcp.yml promotion attestation, Fail/Deny; Kyverno/Trivy KSA get repository-only Reader, no pull key/Secret | Unpromoted apps cannot start; registry access without secrets | image-admission-policy/image-admission-fixtures/policy-gator/helm-template-full, scanner_and_admission_read_only_the_repository | blocking |
| SEC-24 | Cloud Gatekeeper accepts only contract api/web SHA25664; managed exception needs container name istio-proxy/istio-validation and exact gcr.io/gke-release/asm/proxyv2 path with explicit tag/digest. Apply replacement before removing old cloud constraint | Managed injection must neither block app nor allow other repositories; proxyv2-malicioso rejected | policy-gator/image-admission-fixtures; cloud-only template | blocking |
| SEC-23 | Full mesh namespace STRICT; each plaintext PeerAuthentication selects one workload/port (CRD requires selector); external sources only LB ranges, Prometheus9464, Collector healthz/readyz; trust <project>.svc.id.goog, not cluster.local | Invalid CRD fails real apply; broad exemption defeats mTLS | image-admission-policy renders/selectors/default/trust/sources | blocking |
| SUP-01 | Version/SHA256-pinned tools; mismatch fatal | Supply chain | install-tools/checksums, tool-versions | blocking |
| SUP-02 | Every action full40SHA with vX.Y.Z comment, one SHA/action | Tags can move | policy-workflows/version-consistency | blocking |
| SUP-03 | Lockfiles for four platforms, at least four h1 hashes/provider; init -lockfile=readonly | Reproducibility | terraform-lockfiles/terraform-validate | blocking |
| SUP-04 | ESO OCI tag/manifest digest/archive SHA256; three ESO images/devcontainer pinned by digest | Changes require diff | helm-template/contract-platform/version-consistency/repo-structure, installer | blocking |
| SUP-05 | Trivy only via install-tools, never trivy-action/setup-trivy, GHSA-69fq-xp46-6x23 | March 2026 supply-chain incident | policy-workflows | blocking |
| SUP-06 | Consistent tflint ruleset, gitleaks hook, ESO digests, required_version, google constraints/locked version, Kubernetes minor in schemas/CONTRACT, GCLOUD_VERSION/setup-gcloud | No partial upgrade | version-consistency | blocking |
| SUP-07 | Monthly Dependabot, group minor/patch, separate majors; google majors/gitleaks hook deliberately ignored with comments | Avoid silent decay | dependabot.yml | alert |
| IAC-01 | No Kubernetes/Helm Terraform; GA google only, no beta | Layer separation/stable attributes | policy-terraform | blocking |
| IAC-02 | No credentials/access_token/impersonation in google provider; empty gcs backend, bucket/prefix from backend.hcl | ADC or WIF credentials | policy-terraform | blocking |
| IAC-03 | Exactly four provider default_labels, attribution off; no module provider; project tx03v2/environment lab | Every label-capable resource identified | policy-labels | blocking |
| IAC-04 | timestamp/plantimestamp only with attribute ignore_changes | No perpetual diff | policy-terraform | blocking |
| IAC-05 | Validate every nonboolean input: project/region/owner/deploy email/project, lowercase unique user/serviceAccount members, no groups, canonical private nonoverlapping CIDRs/prefixes, DB tier exclusions, positive integer versions, billing/budget/emails | Fail before cloud calls | validations tests/rejects_* | blocking |
| IAC-06 | No unexcepted HIGH/CRITICAL IaC finding, including rendered example tfvars | IaC security | trivy-config/trivy-config-tfvars | blocking |
| IAC-07 | Recommended/google0.40.0 tflint, no issues; inline ignore needs reviewed reason | IaC quality | tflint, PR review | blocking |
| IAC-08 | Formatted valid HCL in every root/module, including local | Readable review | terraform-fmt/terraform-validate | blocking |
| IAC-09 | Autopilot only, no node_pool/min_master_version, legacy ABAC off | Channel owns version, no node sizing | policy-terraform, autopilot_private_dns_endpoint_gateway | blocking |
| IAC-10 | Never disable APIs on destroy;state no force_destroy, PREVENT until state_protection=false | Preserve project/state | policy-terraform, apis_are_enabled_and_never_disabled, state_bucket_is_private_versioned_and_protected, final_teardown_lifts_the_protection | blocking |
| IAC-11 | Explain IAM/network/RBAC/CORS expansion in PR | Deliberate review | PR template | process |
| K8S-01 | Strict kubeconform, pinned schemas | Invalid manifests do not reach cluster | kubeconform | blocking |
| K8S-02 | Restricted/latest dx03v2 namespace;exact contract Role incl networking.gke.io policies;unique email Users;gcpsm ClusterSecretStore projectID/no auth/dx03v2-only;renderer rejects invalid inputs | Least privilege | contract-platform | blocking |
| K8S-03 | ESO external-secrets SA without annotation, digest pins, requests in all three containers | IAM principal depends on names, Autopilot requests | contract-platform, helm-template | blocking |
| K8S-04 | Uninstall dx03v2/wait Gatewayfinalizer/NEGs before destroy;timeout fails | Controller LB outside state | destroy.sh/workflow, policy-workflows;API fallback CUSTO-03 | blocking |
| K8S-05 | Reject group members without configured GoogleGroupsRBAC | IAM member must have equivalent Kubernetes access | rejects_a_group_member, emails_from_members | blocking |
| K8S-06 | Fixed nonoverlapping control-plane /28, firewall only source range/node SA/TCP8443 Gatekeeper, 9443 Kyverno/Chaos | Default control-plane initiation only443/10250;otherwise policy webhook unreachable/full pods blocked | autopilot_private_dns_endpoint_gateway, rejects_a_control_plane_range_* | blocking |
| APP-01 | Versioned DX contract:18keys match contract.tf, harness list, CONTRACT table;fixed store/LB ranges/name;coordinated changes | Both sides evolve together | contract-parameter, contract_keys_in_the_parameter | blocking |
| APP-02 | Deployer/members exactly registry writer, clusterViewer, parameterAccessor | Equal deploy access, no extras | project_grants_follow_the_contract, repository_and_secret_grants, no_extra_deployer_by_default | blocking |
| APP-03 | Cloud Armor seven CRS categories, 600/min/IP>=300, default allow, 64 KBinspection, alert-only Adaptive Protection;none without WAF | Smoke not accidentally blocked | waf_policy_follows_the_contract, no_waf_publishes_none, root_wiring_of_enable_waf | blocking |
| CUSTO-01 | Monthly project budget5 billing currency, actual50/90/100%, forecast100%, named validated recipients+billing admins, EXCLUDE_ALL_CREDITS | Earlier full alerts, but no spending cap | bootstrap budget/tests | alert |
| CUSTO-02 | Core default, full rendered requests;core zonal db-g1-small10 GB/1backup/noPITR, NATerrorlogs, registrycleanup/no scan, GKEsystem/workloadlogs | Reproducible profile/hourly cost in COSTS | platform-sizing, defaults_are_lab_friendly, module tests | blocking |
| CUSTO-03 | Destroy fails loudly, no swallowed errors;continues Terraform after failed uninstall, first deletes only owned controller leftovers via API;always leftovers | Failed uninstall must not leave billable lab | destroy-flow mocked CLIs, destroy.sh/workflow, policy-workflows | blocking |
| CUSTO-04 | Same-day destroy, Owner leftovers, cloud_run_report | Avoid forgotten cost | RUNBOOK | process |
| CUSTO-05 | Uninstall full releases/monitoringPVCs before destroy | Disks outside state keep charging | full-install-order, leftovers persistent-disk list | blocking |
| CI-01 | Harness is CI, jobs call make targets | Same checks | review/ci.yml | process |
| CI-02 | No continue-on-error or success-swallowing fallbacks, Terraform sed, state/lock deletion;force-unlock only typed destroy input | Honest gates, v1lesson | policy-workflows | blocking |
| CI-03 | Top-level contents:read, timeouts, concurrency, ubuntu24.04, persist-credentials:false | Least privilege, predictable execution | policy-workflows | blocking |
| CI-04 | HARNESS_STRICT=1 makes SKIP fail | No silent skipping | ci.yml/harness | blocking |
| CI-05 | Manual cloud workflows (guarded PR plan also);mutations lab;first Check validates variables, review checks content;WIF-only, typed destroy | Costly actions require intent | policy-workflows | blocking |
| CI-06 | Plan -lock=false, apply/destroy retain lock | Plan cannot write lock | policy-workflows | blocking |
| CI-07 | Plan summary/artifact and apply summary replace project/number/suffix with PROJECT_ID/PROJECT_NUMBER/SUFFIX placeholders;mask operators;plan MEMBER/EMAIL redaction | Public logs | plan/apply workflows, lib/gcp mask | process |
| CI-08 | Weekly Monday 06:00UTC CI | Detect changed charts/URLs/new findings | ci.yml | alert |
| CI-09 | E2E local lab everyPR, green before merge | Runtime proof beyond rendering | ci.yml, required ruleset check | blocking |
| LOC-01 | No cloud provider/remote backend in local root;local Docker socket only;local credentials/state outside repo | Free cloud-independent execution | policy-terraform, docker_host validation/local tests | blocking |
| LOC-02 | Local containers tx03v2.lab=local;only registry port127.0.0.1:5003;no privileged infrastructure containers | No unintended exposure/orphans | local tests, policy-terraform, leftovers-local | blocking |
| LOC-03 | Local chart versions/archiveSHA256, image digests, ClusterIP except runtime gateways | Supply chain/private UIs | helm-template-local, local-versions, installer | blocking |
| LOC-04 | Gatekeeper deny/Fail for app, positive/negative fixtures per policy | v1dryrun without audit was insufficient | policy-gator, policies probe | blocking |
| LOC-05 | Traffic/API probe per component;always destroy/leftovers | Claim only proved behavior | local/check/local-lab e2e | blocking |
| LOC-06 | Preflight daemon consistency, nonoverlapping Docker/host routes, free registry port;only own LOCAL_STATE_DIR lab;make clean under Makefile directory | Fork machines may have VPN/other containers/labs | local-preflight mocked docker/kind/ip, preflight/require_own_lab | blocking |
| MUD-01 | Protected main, PR, strict static/test/e2e, no force push | Every change goes through harness | main ruleset/repo-guardrails, policy-workflows | blocking after publication |
| MUD-02 | Scanner exceptions justified, expiry <=about7months | Review/expire accepted risk | trivyignore-policy | blocking |
| MUD-03 | Entrypoint executable bits in Git | Windows may lose bits | repo-structure;before first commit warning with git add --chmod=+x | blocking after first commit |
| MUD-04 | ConventionalCommits, one topic/PR, Unreleased changelog | Readable history | CONTRIBUTING, PRtemplate | process |
| DOC-01 | Claims need exact status/evidence;no self-ratings/emojis/v1links;README<=250lines, LF | Honest documentation | repo-structure, review | blocking |
| DOC-02 | Docs change with code | Prevent stale instructions | PR template | process |
| DOC-03 | Public documentation, examples, comments and contributor guidance in English;single README and central guide | One consistent fork onboarding path | repo-structure/review, GETTING_STARTED link | blocking/process |
| AGT-01 | No agent cloud mutation without explicit human request for that action | Cost/security | AGENTS | process |
| AGT-02 | Never weaken gates or add unjustified/nonexpiring ignores | Harness must retain meaning | Agent instructions/checks | process |
| AGT-03 | Ask in AGENTS-listed cases | Human owns expensive decisions | AGENTS | process |

## Exceptions

A scanner ignore is an exception. To add one:

1. Confirm that the finding is a deliberate lab choice, rather than a defect.
2. Add `.trivyignore.yaml` entry with `id`, narrow `paths`, `statement` explaining
   acceptance/compensating controls, and `expired_at` within about seven months.
3. Explain it in the PR. `trivyignore-policy` rejects missing reasons/dates,
   expired entries or excessive durations; Trivy stops honoring expired entries.

Current exceptions: none (`misconfigurations: []`, checked 2026-10-11).
Known accepted MEDIUM/LOW findings, outside the failure severity threshold
(Trivy0.75.0, `--severity LOW,MEDIUM`):

- MEDIUM GCP-0014/0016/0020/0022/0025: unset PostgreSQL temporary-file, connection,
  lock-wait, disconnection/checkpoint logging flags. Cloud SQL logs cost money;
  this lab is disposable.
- LOW GCP-0029/MEDIUM GCP-0076: subnet flow logs disabled (billed perGB).
- LOW GCP-0051: cluster labels come from root provider default_labels, unseen by
  Trivy's module scan.
- LOW GCP-0066: state has Google default encryption rather than CMEK (ADR23).

## Limits (what is not guaranteed)

- No v2 Google Cloud execution. Mocked provider tests prove configuration, not
  acceptance of every API call or integration of managed services.
- Apply remains powerful in its dedicated project (SEC-20): service admins for
  Kubernetes Engine, Cloud SQL, Compute networking/security, DNS, Artifact Registry,
  Parameter Manager and secret creation/grants. Name conditions are not uniformly
  available on creation calls; the full apply remains cloud-unverified. Velero
  metadata uses the exact two derived bucket names, tested as configuration, not
  live authorization. Node-only serviceAccountUser and project-role grant
  allowlist narrow scope; resource grants still depend on service roles/review.
  A dedicated project is mandatory (preflight rejects foreign clusters/DB/secrets),
  with reviewed lab environment and main-only deployment. Shared projects are
  unsupported. Protected DR sync reads only the four exact lab secrets.
- Roles were chosen from service documentation, not real apply. On
  PERMISSION_DENIED, inspect the missing permission and deliberately review
  apply_extra_project_roles (RUNBOOK12).
- Plan reads project configuration/IAM/nonsecret contract payload. Same-repo
  branch authors could change a PR workflow to use this read access; fork PRs
  receive no credential.
- Project ID/number are repository variables, not Google secrets; masking and
  summary redaction help, but retain a dedicated project.
- GCP_*/LAB_*/TF_STATE_BUCKET variables appear in logs. Put no private value there;
  operators belong in the SEC-19 secret.
- DNS control-plane name is Internet-reachable, though each request needs Google
  IAM container.clusters.connect then Kubernetes RBAC.
- Core Gateway is plaintext HTTP80. Full implements managed HTTPS, but managed
  certificate provisioning and listener behavior remain cloud-unrun.
- Cloud Armor inspects first64 KB; larger bodies pass size inspection and API413.
- GKE policy plurals and Autopilot minima remain unverified on a live cluster;
  implemented deploy can-i preflight catches mismatches before writes.
- db-g1-small default max_connections50 is assumed from Cloud SQL quota docs.
- Budget alerts do not stop resources.
- Leftovers covers lab resource types/ownership only. gcloud labels/network
  formats and controller gkegw1-…-dx03v2-… names remain unverified in an account.
  Apply may not read some inventories (UNCHECKED warning, no exit-code change);
  full check must run locally as project Owner.
- Deleted WIF pool ID unavailable30 days (ARCHITECTURE, Names retained after deletion).
- kubeconform ClusterSecretStore schema snapshot2026-06-02 (HARNESS).
- Local proof is kind, not GCP/Autopilot. cloud-provider-kind uses the Docker
  socket to create containers; run only on disposable machines/CI (LOCAL_LAB).
  Complete CI e2e is required by ruleset.
- Local istio-system, monitoring-agents, chaos-mesh require privileged components
  (unacceptable upstream on Autopilot). Platform namespaces are outside
  Gatekeeper webhook so bootstrap can proceed when it is unavailable.

## Verification

```bash
make tools                 # pinned tools in .tools/
HARNESS_STRICT=1 make verify
scripts/harness.sh list    # all checks and stages
scripts/leftovers.sh --project <id>   # after destroy, gcloud Owner login
```
