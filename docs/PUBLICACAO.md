# Publicação do tx03v2

Checklist para tornar o repositório público com as proteções do padrão v2. Siga na ordem; cada item
tem o comando ou o lugar onde é verificado. O repositório nasce privado; torná-lo público e rodar o
`scripts/repo-guardrails.sh` só com o OK explícito do mantenedor.

## Antes de publicar

- [ ] `HARNESS_STRICT=1 make verify` verde no devcontainer ou em Linux.
- [ ] Bit executável nos scripts de entrada antes do primeiro commit (o Windows não o grava):
      `git add --chmod=+x platform/install.sh platform/render-manifests.sh platform/uninstall.sh scripts/harness.sh scripts/install-tools.sh scripts/leftovers.sh scripts/repo-guardrails.sh scripts/update-tool-checksums.sh`
      (o check `repo-structure` confere o índice do git).
- [ ] Primeiro commit feito e enviado para `main` (privado) e CI verde (`static`, `test`).
- [ ] `gitleaks git` limpo no histórico completo (o check `gitleaks` faz isso quando há commits).
- [ ] Nenhum identificador real: `policy-identifiers` verde (IDs e números de projeto, contas de
      faturamento, e-mails, IPs) e uma leitura humana de `docs/` (o sufixo real do bucket,
      `tx03v2-tfstate-<suffix>`, deriva do ID do projeto e também o identifica).
- [ ] Matriz de status do README conferida: `verificado localmente` só vira `verificado no CI` depois
      do primeiro CI verde; tudo de nuvem continua `não executado em nuvem (v2)` até um
      `cloud_run_report`.
- [ ] Descrição e tópicos do repositório (`gh repo edit maringelix/tx03v2 --description ... --add-topic terraform`).

## Publicar

- [ ] `gh repo edit maringelix/tx03v2 --visibility public --accept-visibility-change-consequences`
- [ ] `scripts/repo-guardrails.sh maringelix/tx03v2`: alertas de vulnerabilidade, security updates do
      Dependabot, squash-only, `delete_branch_on_merge`, `GITHUB_TOKEN` só leitura por padrão (sem
      aprovar PRs), ruleset `main`, secret scanning + push protection, private vulnerability
      reporting e environment `lab` (revisor: o dono; só `main`). O script imprime o que foi
      aplicado, pulado e o que falhou.
- [ ] Aprovação obrigatória para workflows de PRs de forks de todos os colaboradores externos
      (Settings > Actions > General, ou
      `gh api --method PUT repos/maringelix/tx03v2/actions/permissions/fork-pr-contributor-approval --input -`
      com `{"approval_policy":"all_external_contributors"}` na entrada).

## Ruleset `main` (`.github/rulesets/main.json`)

- Bloqueia deleção e force-push; exige PR (0 aprovações para mantenedor solo,
  `dismiss_stale_reviews_on_push`, `required_review_thread_resolution`), merge só squash.
- Checks obrigatórios (modo estrito, app GitHub Actions): `static` e `test`.
- Bypass: papel de admin do repositório, modo `pull_request` — **só para emergência** (por exemplo,
  um check quebrado por fator externo bloqueando uma correção de segurança). Registre o motivo no PR.

## Ids de jobs estáveis

Mudar um id quebra a proteção. Ids atuais:

| Workflow | Job | Exigido pelo ruleset |
|---|---|---|
| `ci.yml` | `static` | sim |
| `ci.yml` | `test` | sim |
| `terraform-plan.yml` | `plan` | não (só roda com `GCP_PLAN_SERVICE_ACCOUNT` e em PRs do próprio repositório) |
| `terraform-apply.yml` | `apply` | não |
| `platform.yml` | `platform` | não |
| `terraform-destroy.yml` | `destroy` | não |

## Depois de publicar

- [ ] CI verde em `main` público e badge funcionando; atualize a matriz, o `AGENTS.md` e o
      `docs/SUSTENTACAO.md` (`verificado no CI`) num PR.
- [ ] Atualize as tabelas de família dos outros repositórios v2 (link para o tx03v2 no lugar do nome)
      por PRs.
- [ ] Variáveis do GitHub só depois do bootstrap (`docs/RUNBOOK.md`, seção 3); as do dx03v2 também.
- [ ] Primeira rodada em nuvem registrada com `cloud_run_report`.
