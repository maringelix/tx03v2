# Contributing

Thanks for helping. This lab only claims what its harness proves, so every change goes through it.

Forking the lab to run it on your own machine and cloud account? Start with [FORK.md](FORK.md).

## Workflow

1. Open an issue for anything non-trivial (bugs: use the bug report form).
2. Branch from `main`; use [Conventional Commits](https://www.conventionalcommits.org/)
   (`feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `refactor:`, `test:`).
3. `make tools` once, then `HARNESS_STRICT=1 make verify` before pushing. Windows/macOS: use the
   devcontainer.
4. Optional fast feedback: `pre-commit install` (hooks in `.pre-commit-config.yaml`).
5. Open a PR and complete the Definition of Done in the template. Merges are squash-only.

## Rules that matter most

- No secrets or real identifiers (project IDs and numbers, billing accounts, service account
  e-mails, name suffixes, IPs, e-mails) anywhere, including examples. Examples use
  `tx03v2-lab-example`, `000000000000`, `000000-000000-000000` and `you@example.com`.
- Do not weaken checks or add scanner ignores without `statement` and `expired_at`.
- Explain any IAM role (including the list of `terraform/modules/project-roles`), network,
  Kubernetes RBAC or CORS widening in the PR.
- Contract changes (`docs/CONTRATO.md`) need a coordinated PR in `dx03v2` and a version bump.
- Pin new actions (full commit SHA + `# vX.Y.Z`), charts and images (SHA256/digest) and tools
  (version + SHA256).
- Docs live in Brazilian Portuguese (`docs/`, `README.pt-BR.md`); `README.md`, `AGENTS.md`,
  `CONTRIBUTING.md`, `SECURITY.md` and `CHANGELOG.md` in English.

## Cloud runs

You never need a Google Cloud project to contribute. If you run the lab in your own project, follow
`docs/RUNBOOK.md` (read the cost section first) and share the result with the **Cloud run report**
issue form.

The full rule list is in [docs/GUARDRAILS.md](docs/GUARDRAILS.md); agents and humans also follow
[AGENTS.md](AGENTS.md).
