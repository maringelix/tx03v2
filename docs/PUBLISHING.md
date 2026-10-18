# Publishing tx03v2

Checklist for initial publication with v2 protections. Follow this order; every
item names its command or verification point. Visibility changes and applying
repository settings require the maintainer's explicit instruction.

## Before publication

- [ ] `HARNESS_STRICT=1 make verify` green in Linux/devcontainer.
- [ ] Set entrypoint executable bits before first commit (Windows may lose them):
  `git add --chmod=+x platform/install.sh platform/render-manifests.sh platform/uninstall.sh scripts/harness.sh scripts/install-tools.sh scripts/leftovers.sh scripts/repo-guardrails.sh scripts/update-tool-checksums.sh`.
  `repo-structure` checks the Git index.
- [ ] Initial private main commit pushed, CI static/test/e2e green.
- [ ] Full-history `gitleaks git` clean; harness performs this after commits exist.
- [ ] `policy-identifiers` green and human review of docs: project IDs/numbers,
  billing accounts, emails/IPs and the real project-derived bucket suffix must
  not be published.
- [ ] Status matrix reviewed: verified locally becomes verified in CI only after
  green CI; cloud remains not run in the cloud (v2) until a cloud_run_report.
- [ ] Set description/topics, for example `gh repo edit maringelix/tx03v2 --description ... --add-topic terraform`.

## Publication

- [ ] `gh repo edit maringelix/tx03v2 --visibility public --accept-visibility-change-consequences`.
- [ ] Run `scripts/repo-guardrails.sh maringelix/tx03v2`: vulnerability alerts,
  Dependabot security updates, squash-only merges, delete merged branches, issues,
  read-only default token without PR approval, main ruleset, secret scanning/push
  protection, private reporting, approval of external fork workflows, protected
  lab environment with invoking user as reviewer and main-only deployment.
  It fails while Actions is disabled, identifies fork settings and reports
  applied settings, skips, notes and failures. Fork owners use their own repo.

## Main ruleset (`.github/rulesets/main.json`)

- Block deletion/force-push; require PR with zero reviews for a solo maintainer,
  dismiss stale reviews, resolve threads and squash-only merging.
- Required strict GitHub Actions checks: static, test, e2e.
- Repository-admin bypass is PR-only, for emergencies such as an external broken
  check obstructing a security fix. Record the reason. Never use it to disguise
  an implementation failure.

## Stable job IDs

Changing IDs breaks protection.

| Workflow | Job | Required by ruleset |
|---|---|---|
| ci.yml | static | yes |
| ci.yml | test | yes |
| ci.yml | e2e | yes |
| terraform-plan.yml | plan | no; guarded same-repo PR/manual run with GCP_PLAN_SERVICE_ACCOUNT |
| terraform-apply.yml | apply | no |
| platform.yml | platform | no |
| terraform-destroy.yml | destroy | no |

## After publication

- [ ] Public main CI/badge green; update README matrix, AGENTS and MAINTENANCE
  with CI evidence through a PR.
- [ ] Update sibling family tables through PRs.
- [ ] Configure TX and DX variables only after bootstrap (RUNBOOK3).
- [ ] Record first cloud run through cloud_run_report.
