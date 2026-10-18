# tx03v2 harness

The harness checks this repository's claims without a cloud account. scripts/harness.sh owns
every check; Makefile/CI call it and CI sets HARNESS_STRICT=1.
Before initial commits gitleaks scans the working tree; with commits it scans history.
Indexed scripts require executable bits; not-yet-indexed scripts only warn.

Use scripts/harness.sh list for current checks, including full cloud renders, GitOps contract,
request sums and runbook references. Real chart downloads use platform/full/charts.txt pins.

Historical R8 local evidence (2026-10-17): non-strict Windows runs passed lab Terraform tests
(52 runs), bootstrap tests (33), fmt, container shellcheck/actionlint, contract-parameter/platform/
platform-full, image-admission-policy, full-install-order, fork-references, platform-sizing,
helm-template-full, destroy/leftovers/preflight/local-preflight flows. kubeconform/gator/tflint/
Trivy/full local e2e remained for that PR's CI. Subsequent merged CI provides the construction
evidence; these tests do not prove GKE admission/runtime. Cloud remains
`not run in the cloud (v2)`; LOCAL_LAB records portable runtime evidence.

## Layers

| Layer | Check | Proves | Does not prove | Runs |
|---|---|---|---|---|
| Tools | make tools | pinned versions/SHA256 for linux_amd64, linux_arm64, darwin_arm64 | — | local/CI |
| Versions | tool-versions | pinned PATH versions, mismatch fails strict mode | — | local/CI |
| Structure/evidence | repo-structure, version-consistency | required English docs/status labels, no self-ratings/emojis/v1 README links, <=250-line README, CLAUDE, LF, executable index modes, digest-pinned devcontainer, coherent Kubernetes contract minor/gcloud workflow versions | prose correctness | local/CI |
| Terraform policy | policy-terraform, policy-labels | write-only secrets, no SA keys/authoritative IAM/owner/principalSet/public resources/above-project scope; Autopilot/private DB/cluster/IAM DNS; no cloud-root 0.0.0.0/0 or kubernetes/helm/google-beta providers; empty GCS backend, APIs retained, protected buckets, no perpetual timestamp diff; local root has no cloud provider/remote backend, only local backend, localhost publishing, no privileged containers and only local random_password; four exact default_labels | author intent | local/CI |
| Identifiers | policy-identifiers | placeholder-only project numbers/billing accounts/project-ID paths/SA emails/WIF pools/emails/public IPs/GUIDs; permits documented private/documentation/LB ranges | other formats | local/CI |
| Workflows | policy-workflows, actionlint | SHA actions, permissions, vars-only federation/no keys, trusted guards, lock=false only plan, no blanket state/lock removal, reviewed destroy unlock input, masked operator secrets, typed confirmation/destroy.sh, YAML/expressions/run-block shellcheck | actual Google behavior | local/CI |
| Script safety | policy-scripts | no generic environment target override, temporary kubeconfig before get-credentials, require_lab_cluster project label in install/uninstall, require_lab_context locally | actual Google behavior | local/CI |
| Offline flows | destroy-flow, leftovers-flow, preflight-flow, local-preflight | failed uninstall still reaches destroy/leftovers; only lab LB components removed/count as leftovers; projects with unrelated cluster/DB/secret refused; local different-daemon/overlap/occupied-port/other-state-dir cases rejected | real cloud/Docker calls; CLIs are stubs | local/CI |
| Exceptions | trivyignore-policy | statement/expired_at within about seven months, none at baseline | — | local/CI |
| Contract | contract-platform, contract-parameter | rendered objects/labels/Role/unique RoleBinding subjects/ClusterSecretStore, invalid-input denial, ESO values/pins; exact 18 contract keys, fixed values, parameter name and documented table entries | extra table rows or DX behavior; DX has its own checks | local/CI |
| Full contract | contract-platform-full | platform AppProject/Application, DX Application/GitOps ref, named-Application/user-scoped Role, Telemetry, no embedded Secret | real Argo sync | local/CI |
| Admission/mesh/order | image-admission-policy, full-install-order | fail-closed digest/promotion-workflow identity policy for the fork, contract owner/repo, selector on port-specific PeerAuthentication, default STRICT, non-cluster.local trust domain, only two external LB ranges, security before observability/admission before Argo, uninstall releases/PVCs | runtime admission/CEL/mesh | local/CI |
| Cloud admission regression | image-admission-fixtures, policy-gator | Helm/jq-parsed Kubernetes mode, Fail/Deny, namespace/signer/fork and three image groups; JSON/Audit/wrong-signer/missing-group mutations rejected; real Rego with injected Pod and 12 negative cases; replacement gate precedes old cloud constraint removal | CEL, image crypto or GKE subresource admission; no Docker | light local/CI |
| Allocation convergence | cost-allocation | actual allocation_positive/retry with stub kubectl/wait: zero/wrong-namespace denied, positive accepted, persistent zero/HTTP failure exhaust seven attempts; retains 15-second HTTP timeout/30-second interval | HTTP/Docker; real OpenCost integration belongs to e2e | light local/CI |
| HCL/schema | terraform-fmt, terraform-validate:* | formatted HCL valid against pinned schemas in roots/modules | provider acceptance in a real project | local/CI |
| Provider locks | terraform-lockfiles | at least four h1 hashes/provider for Linux amd64/arm64, Darwin arm64, Windows amd64 | which platform corresponds to each hash | local/CI |
| Lint | tflint | recommended preset/Google ruleset 0.40.0 with no issues | live-API-dependent rules | local/CI |
| IaC security | trivy-config, trivy-config-tfvars | no HIGH/CRITICAL, no current exceptions | effective runtime IAM | local/CI |
| Shell | shellcheck | style-level analysis in scripts/platform | Google behavior | local/CI |
| Manifests | kubeconform | strict core/full/GitOps Kubernetes 1.36/CRD validation | cluster admission/runtime | local/CI/network |
| Core charts | helm-template | real pinned/checksummed ESO/Collector archives, digest images, ServiceAccounts, Cloud Trace exporter/requests | actual controller install/runtime | local/CI/network |
| Full charts | helm-template-full | every GCP chart archive SHA256, image digests, no LB/NodePort/placeholder; Collector Tempo/spanmetrics; Velero bucket/plugin/KSA without Secret; observability exemption; Trivy without mirror; Chaos controller without privileged daemon | Autopilot admission/controller runtime | local/CI/network |
| Sizing | platform-sizing | rendered platform CPU/memory requests including Prometheus/Alertmanager match COSTS | billing or Autopilot request adjustment | local/CI/network |
| Secrets | gitleaks | known-pattern history secrets, or initial working-tree scan | unknown formats | local/CI |
| Terraform tests | terraform-test:bootstrap, terraform-test:envs/lab | APIs/state bucket/WIF exact subjects, plan/apply roles, root IAM role allowlist, derived-bucket Velero scope, budget, Autopilot/network/NAT, SQL PSC/TLS/edition/backups, write-only secrets, registry/WAF/none, contract keys/values/grants, negative validation | actual cloud provisioning; providers mocked | local/CI |
| Local Terraform | terraform-validate:envs/local, terraform-test:envs/local | private network/labels, only localhost registry publishing, TLS-only DB, image digests and negative cases; original suite had ten plan-only runs | real Docker creation, covered by e2e | local/CI |
| Gatekeeper | policy-gator | actual local/GCP Rego test cases with gator 3.23.1 | webhook runtime decision | local/CI |
| Fork references | fork-references | cited scripts/make targets/workflows/variables in FORK/RUNBOOK exist; DX commands name sibling paths | completed real run or synchronized sibling checkout | local/CI |
| Local platform | local-versions, helm-template-local, kubeconform-local, policy-gator | checksum/digest-pinned charts, ClusterIP, small overlays preserve images, valid manifests, positive/negative policies, kind minor/gator/Gatekeeper consistency, same local/cloud ESO archive | cluster behavior | local/CI/network |
| Local end to end | local-lab-e2e / make e2e | Docker root apply, full install, real platform probes including later HA/backup/capacity, always destroy/leftovers | Google Cloud | Docker host or CI; heavy runs in Actions for Bruno |
| Cloud | terraform-* and platform workflows | source/configuration only until an authorized cloud run | managed behavior | not run in the cloud (v2) |

Historical local probe totals (26 then 34 as R1 expanded) are recorded in LOCAL_LAB; use the
current harness/probe registry for current counts rather than treating historical counts as coverage.

## CI jobs

| Stable job ID | Target | Stage |
|---|---|---|
| static | make tools && make static | static |
| test | make tools && make test | test |
| e2e | make tools && make e2e | e2e; full logs/diagnostics uploaded on failure |

All three are required by .github/rulesets/main.json; e2e became required in October 2026.
policy-workflows rejects missing jobs and id-token: write in standalone ci.yml. CI receives no
Google Cloud credentials. HA/FinOps runtime settings are exercised in Actions without cloud access.

## Strict mode and variables

HARNESS_STRICT=1, used in CI/devcontainer, turns every SKIP into FAIL and requires pinned PATH
versions. Without it, SKIP is allowed only for a missing local prerequisite with a printed reason.

- HARNESS_VERBOSE=1 prints passing check output.
- HARNESS_ONLY=<regex> selects local debugging checks, never CI. Example:
  HARNESS_ONLY='^tflint$' scripts/harness.sh static.
- HARNESS_WORK_DIR changes scratch storage, described below.

## Adding a check

1. Write check_<name> returning zero for PASS, nonzero for FAIL. need/skip are only for absent
   local prerequisites.
2. Register in the correct stage.
3. Inspect harness list and strict verify. Prove the intended negative case in a disposable
   repository copy instead of weakening checks.
4. Update this table, relevant GUARDRAILS rule and CHANGELOG.

New tools need official metadata in scripts/lib/tools.sh, tools/versions.env and checksum updater.
Current check counts come from harness list; they change as regression coverage grows.

## Windows and macOS

- Supported installer platforms: linux_amd64, linux_arm64, darwin_arm64.
- Windows: devcontainer/pinned image or Ubuntu WSL2. The installer does not provide Windows
  binaries; native maintainer light checks do not change the supported learner setup.
- Apple Silicon: Homebrew Bash >=4.4 or devcontainer; system Bash 3.2 is too old.
- Disposable tool container example:

```bash
docker run --rm -e HARNESS_STRICT=1 -v "$PWD:/work" -w /work ubuntu:24.04 bash -c "apt-get update -qq && apt-get install -y -qq --no-install-recommends ca-certificates curl unzip git xz-utils make >/dev/null && make tools && make verify"
```

Add GIT_CONFIG_COUNT=1, GIT_CONFIG_KEY_0=safe.directory and GIT_CONFIG_VALUE_0=* if ownership
requires it. In OneDrive folders mount named volumes over /work/.tools and /work/.cache.
Heavy kind/full/Sonar/DR/load validation stays in Actions in Bruno's workspace.

## Data outside the repository

Terraform TF_DATA_DIR, logs/charts/caches use HARNESS_WORK_DIR (default $TMPDIR/tx03v2-harness).
TF_PLUGIN_CACHE_DIR defaults ~/.terraform.d/plugin-cache and is also cached in CI.
Only .tools and ignored module locks live in the source tree.
make clean removes source .tools/.cache/.terraform, module locks and default harness scratch;
custom scratch/plugin caches remain. Clean is relative to the Makefile's repository.

## Common problems

| Symptom | Likely cause | Action |
|---|---|---|
| SKIP tool-versions: missing tools | setup absent | make tools |
| terraform-validate lock error | provider changed without lock | four-platform providers lock in the root; MAINTENANCE 5.3 |
| policy-labels | wrong four default labels, missing attribution setting or module provider block | fix root provider; modules inherit it |
| project role not in modules/project-roles | unlisted grant | grant per resource or justify allowlist expansion/test/bootstrap reapply |
| contract-parameter | key/value changed in only one location | coordinate contract.tf, CONTRACT_KEYS, CONTRACT and DX |
| helm-template SHA256/OCI digest failure | upstream artifact differs | stop/review release; never blindly replace pins |
| setup-gcloud mismatch | tools/workflow versions differ | coordinate both, MAINTENANCE 5.6 |
| expired Trivy exception | deadline passed | fix or renew with current reason |
| kubeconform could not find schema | network or incompatible schema | check connectivity and note below |
| executable index failure | Windows commit mode | git update-index --chmod=+x <file> |
| gitleaks | real secret or false positive | rotate/remove real secrets; justified false-positive handling requires PR review; initial dir scan includes ignored tfvars/backend/state/gha-creds files, so keep private material outside source |
| policy-identifiers | real project/billing/email/IP | use tx03v2-lab-example, 000000000000, 000000-000000-000000, you@example.com, 203.0.113.10 |

Schema note (verified 2026-10-10 in reference TX01): catalog b7e2015/2026-10-08 generated from
ESO 2.12 put additionalProperties=false inside a properties map/provider crd, which kubeconform
could not compile. Pinned f3e4382/2026-06-02 validates this ClusterSecretStore strictly and rejects
misspelled fields. Recheck quarterly, MAINTENANCE 5.7.

## R10 capacity and FinOps

[FINOPS.md](FINOPS.md) covers kind HA, load/HPA/PDB, OpenCost, recommendation-only VPA, opt-in
Spot, regional pricing, budget/expiry and cleanup. These are reproducible construction exercises;
no Google Cloud v2 run has occurred.
