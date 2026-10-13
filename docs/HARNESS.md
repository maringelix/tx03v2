# Harness do tx03v2

O harness é o conjunto de checks que prova o que este repositório afirma, sem conta na nuvem.
Ele vive em `scripts/harness.sh`; o `Makefile` e o CI só o chamam, e o CI usa `HARNESS_STRICT=1`.
Duas diferenças conhecidas entre uma pasta sem commits e o CI: o `gitleaks` lê a árvore de trabalho
(no CI, o histórico inteiro) e o bit executável só é exigido de scripts que já estão no índice do
git. `scripts/harness.sh list` mostra os checks: 35 no estágio `static` e os 3 `terraform-test:*` no
`test`, que também roda `tool-versions` (38 no `make verify`, que conta o `tool-versions` uma vez),
mais o `local-lab-e2e` no estágio `e2e` (`make e2e`, fora do `verify`).

Estado: `HARNESS_STRICT=1 make verify` passou com 32 PASS no CI (jobs `static` e `test`) antes do lab
local; com os checks do lab local são 38 PASS num container Linux (`verificado localmente`; o CI
ainda não rodou essa versão). O `local-lab-e2e` está `verificado localmente` (26 sondas, 2026-10-13).

## Camadas

| Camada | Check | O que prova | O que NÃO prova | Onde roda |
|---|---|---|---|---|
| Ferramentas | `make tools` | binários nas versões de `tools/versions.env`, SHA256 conferido (linux_amd64, linux_arm64, darwin_arm64) | — | local, CI |
| Versões | `tool-versions` | o PATH usa as versões fixadas (no modo estrito, divergência é FAIL) | — | local, CI |
| Estrutura e honestidade | `repo-structure`, `version-consistency` | arquivos obrigatórios; rótulos de status, sem auto-elogios, emojis ou links para o v1 nos READMEs; README com até 250 linhas; `CLAUDE.md`; LF; bit executável no índice do git (só um aviso para scripts ainda fora do índice); devcontainer por digest; versões coerentes entre arquivos (inclusive a minor do Kubernetes no `docs/CONTRATO.md` e a versão do gcloud nos workflows) | que a documentação está certa | local, CI |
| Políticas do Terraform | `policy-terraform`, `policy-labels` | erros do v1 não voltam (segredos write-only, sem chaves de conta de serviço, sem IAM autoritativo, sem `roles/owner`, sem `principalSet`, nada público, nada acima do projeto, só Autopilot, cluster e banco privados, endpoint DNS só IAM, sem `0.0.0.0/0` nos roots de nuvem e nos módulos, sem providers `kubernetes`/`helm`/`google-beta`, backend `gcs {}` sem argumentos, APIs nunca desligadas, bucket sem `force_destroy`, sem `timestamp()` com diff perpétuo; no `terraform/envs/local`: nenhum provider de nuvem nem backend remoto, só o backend `local {}`, portas só em 127.0.0.1, nada privilegiado, `random_password` permitido só ali); `default_labels` com exatamente os quatro labels do contrato nos dois roots | intenção de quem escreveu | local, CI |
| Identificadores | `policy-identifiers` | sem números de projeto, contas de faturamento, IDs de projeto (em caminhos `projects/<id>/`, e-mails de conta de serviço e pools `<id>.svc.id.goog`), e-mails, IPs públicos ou GUIDs reais; só os placeholders, as faixas privadas e de documentação e as duas faixas do load balancer | identificadores fora desses formatos | local, CI |
| Workflows | `policy-workflows`, `actionlint` | actions por SHA, `permissions`, regras de Workload Identity Federation (`auth` só com `vars.*`, sem chaves), guardas, `-lock=false` só no plan, nada apaga state ou lock, confirmação digitada, uninstall e checagem de sobras no destroy; YAML, expressões e shellcheck dos blocos `run` | comportamento contra o Google Cloud | local, CI |
| Exceções | `trivyignore-policy` | cada ignore tem `statement` e `expired_at` em até ~7 meses (hoje não há nenhum) | — | local, CI |
| Contrato | `contract-platform`, `contract-parameter` | os manifests renderizados são os do contrato (objetos, labels, regras da Role, sujeitos da RoleBinding sem repetição, ClusterSecretStore); o renderizador recusa entradas inválidas; values e pins do ESO; as 15 chaves de `contract.tf` = lista do harness, valores fixos, nome do parâmetro no Terraform e nos scripts, e cada chave tem uma linha na tabela de `docs/CONTRATO.md` | linhas a mais na tabela; o que o dx03v2 faz (o harness dele vai conferir) | local, CI |
| Formato e sintaxe | `terraform-fmt`, `terraform-validate:*` (3 roots, 8 módulos) | HCL formatado e válido para o schema do provider fixado | que o Google Cloud aceita os valores | local, CI |
| Lock de providers | `terraform-lockfiles` | pelo menos 4 hashes `h1:` por provider nos lock files dos roots (gerados para linux_amd64, linux_arm64, darwin_arm64, windows_amd64) | a qual plataforma cada hash pertence | local, CI |
| Lint | `tflint` | preset recommended + ruleset google 0.40.0 sem issues | regras que dependem de chamadas ao Google Cloud | local, CI |
| Segurança da IaC | `trivy-config`, `trivy-config-tfvars` | sem HIGH/CRITICAL (não há exceções) | configuração em runtime, IAM efetivo | local, CI |
| Scripts | `shellcheck` | bash correto (nível style) em `scripts/` e `platform/` | comportamento contra o Google Cloud | local, CI |
| Manifests | `kubeconform` | manifests renderizados válidos (estrito) para Kubernetes 1.36 e para os CRDs do ESO | admission e comportamento no cluster | local, CI (rede) |
| Chart da plataforma | `helm-template` | o chart do ESO 2.12.0 baixado por tag e digest do manifest OCI tem o SHA256 registrado e aceita `platform/values`: três imagens com o digest, ServiceAccount `external-secrets` sem anotação de conta de serviço do Google, requests nos três contêineres, CRDs | instalação real e comportamento do controller | local, CI (rede) |
| Segredos | `gitleaks` | nenhum segredo conhecido (histórico completo quando há commits; antes disso, a árvore de trabalho) | segredos fora dos padrões do gitleaks | local, CI |
| Testes unitários | `terraform-test:bootstrap` (19 casos), `terraform-test:envs/lab` (41 casos) | APIs, bucket do state, pool e provider do Workload Identity Federation, um sujeito por vínculo, papéis do plan e do apply, condição IAM = papéis de projeto do lab, budget, GKE Autopilot, rede e NAT, Cloud SQL (PSC, TLS, edição, backups), segredos write-only, Artifact Registry, Cloud Armor e `none`, chaves e valores do contrato, concessões IAM, validações negativas | que os recursos sobem no Google Cloud (provider mockado) | local, CI |
| Lab local: Terraform | `terraform-validate:envs/local`, `terraform-test:envs/local` (10 casos, só plan) | rede privada, labels em tudo, só o registry publicado e só em 127.0.0.1, banco só TLS, imagens por digest, validações negativas | que o Docker cria os contêineres (isso é o `e2e`) | local, CI |
| Lab local: plataforma | `local-versions`, `helm-template-local`, `kubeconform-local`, `policy-gator` | os 15 charts fixados por SHA256 renderizam só imagens por digest e Services ClusterIP; manifests válidos; cada política do Gatekeeper aceita e recusa os casos de `platform/local/policies/tests`; kind no mesmo minor da GKE do lab (`GKE_KUBERNETES_MINOR`); gator igual ao Gatekeeper; o arquivo do ESO local tem o mesmo SHA256 do chart OCI da plataforma | comportamento no cluster | local, CI (rede) |
| Lab local: ponta a ponta | `local-lab-e2e` (`make e2e`) | apply do `terraform/envs/local`, instalação do perfil `full` e as 26 sondas de `platform/local/check.sh` (`docs/LAB_LOCAL.md`); destroy e checagem de sobras sempre | Google Cloud | local (Docker, 8 GB), CI; `verificado localmente` em 2026-10-13 (26 sondas) |
| Nuvem | workflows `terraform-*`, `platform` | — | — | `não executado em nuvem (v2)` |

## Jobs do CI

| Job (`ci.yml`) | Alvo | Estágio do harness |
|---|---|---|
| `static` | `make tools && make static` | `static` |
| `test` | `make tools && make test` | `test` |
| `e2e` | `make tools && make e2e` | `e2e` (o lab local; diagnósticos e o log completo do e2e como artifact em caso de falha) |

Os ids `static` e `test` são estáveis: são os checks exigidos pelo ruleset
(`.github/rulesets/main.json`); o `policy-workflows` falha se um deles sumir. O `e2e` roda em todo PR
e precisa estar verde para o merge (disciplina do mantenedor; ainda não está no ruleset). O CI não
recebe credenciais do Google Cloud (o `policy-workflows` recusa `id-token: write` no `ci.yml`).

## Modo estrito

`HARNESS_STRICT=1` (definido no CI e no devcontainer) transforma todo `SKIP` em `FAIL` e exige que as
versões no PATH sejam as de `tools/versions.env`. Sem ele, um check só pode dar `SKIP` quando falta um
pré-requisito local (por exemplo, ferramenta não instalada) e sempre imprime o motivo.

Outras variáveis: `HARNESS_VERBOSE=1` mostra a saída dos checks que passam; `HARNESS_ONLY=<regex>`
roda só os checks cujo nome casa com a expressão (depuração local, por exemplo
`HARNESS_ONLY='^tflint$' scripts/harness.sh static`; o CI nunca usa); `HARNESS_WORK_DIR` muda a pasta
de dados (seção "Dados fora do repositório").

## Como adicionar um check

1. Escreva uma função `check_<nome>` em `scripts/harness.sh` que retorna 0 (PASS) ou não-zero (FAIL);
   use `need <ferramenta>` ou `skip "<motivo>"` só para pré-requisitos ausentes.
2. Registre-a em `register_checks` no estágio certo (`static` ou `test`).
3. Rode `scripts/harness.sh list` e `HARNESS_STRICT=1 make verify`. Prove que o check falha: aplique a
   mudança que ele deve pegar numa cópia do repositório e confira o `FAIL`.
4. Atualize esta tabela, `docs/GUARDRAILS.md` (se for um guardrail) e o CHANGELOG.

Ferramenta nova: adicione-a a `scripts/lib/tools.sh` (URLs oficiais), a `tools/versions.env` e rode
`scripts/update-tool-checksums.sh <ferramenta> <versão>`.

## Windows e macOS

- Windows: use o devcontainer (`.devcontainer/devcontainer.json`, imagem fixada por digest) ou WSL 2
  com Ubuntu. Git Bash não é suportado (as ferramentas são binários Linux/macOS).
- macOS (Apple Silicon): `brew install bash` (o bash 3.2 do sistema não serve; o harness exige
  bash >= 4.4) ou o devcontainer. Plataformas suportadas pelo `install-tools.sh`: linux_amd64,
  linux_arm64, darwin_arm64.
- Container avulso (como a verificação local deste repositório):
  `docker run --rm -e HARNESS_STRICT=1 -v "$PWD:/work" -w /work ubuntu:24.04 bash -c "apt-get update -qq && apt-get install -y -qq --no-install-recommends ca-certificates curl unzip git xz-utils make >/dev/null && make tools && make verify"`
  (adicione `-e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0=*` se o
  dono dos arquivos for outro usuário). Numa pasta sincronizada (OneDrive, por exemplo), monte
  volumes nomeados sobre `/work/.tools` e `/work/.cache` para não criar milhares de arquivos nela.

## Dados fora do repositório

O harness grava dados do Terraform (`TF_DATA_DIR`), logs, charts e caches em `HARNESS_WORK_DIR`
(padrão `$TMPDIR/tx03v2-harness`) e usa o cache de plugins `TF_PLUGIN_CACHE_DIR` (padrão
`~/.terraform.d/plugin-cache`, também cacheado no CI). No repositório ficam só `.tools/` e os lock
files dos módulos (ignorados pelo git). `make clean` remove `.tools/`, `.cache/`, os diretórios
`.terraform`, os lock files dos módulos e o `HARNESS_WORK_DIR` padrão; o cache de plugins e um
`HARNESS_WORK_DIR` personalizado ficam.

## Problemas comuns

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `SKIP tool-versions (...) - missing tools: ...` | `make tools` não rodou | `make tools` |
| `FAIL terraform-validate:envs/lab` com erro de lock | provider mudou sem atualizar o lock | `terraform providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64 -platform=windows_amd64` no root (`docs/SUSTENTACAO.md`, 5.3) |
| `FAIL policy-labels` | `default_labels` diferente dos quatro labels do contrato, `add_terraform_attribution_label` ausente, ou um módulo com bloco `provider` | corrija o provider do root; módulos herdam o provider |
| `FAIL terraform-test:envs/lab` (ou erro de `precondition` no plan) com `Project role ... is not in modules/project-roles` | papel de projeto fora de `modules/project-roles` | conceda no recurso ou adicione o papel à lista (amplia a condição do apply: justifique no PR e reaplique o bootstrap) |
| `FAIL contract-parameter` | chave do contrato só em um dos três lugares, ou valor fixo alterado | mude `contract.tf`, `CONTRACT_KEYS` e `docs/CONTRATO.md` juntos (e o dx03v2) |
| `FAIL helm-template ... SHA256` ou falha no `helm pull` por digest | o chart no registry mudou | pare: não troque o digest nem o SHA256 sem revisar o release (`docs/SUSTENTACAO.md`, 5.5) |
| `FAIL version-consistency ... setup-gcloud` | `GCLOUD_VERSION` e o `version:` de algum `setup-gcloud` diferentes | atualize os dois juntos (`docs/SUSTENTACAO.md`, 5.6) |
| `FAIL trivyignore-policy ... expired` | ignore venceu | revise a exceção: corrija o código ou renove com nova justificativa |
| `FAIL kubeconform ... could not find schema` | sem rede, ou schema do catálogo que o kubeconform não compila | confira a rede; veja a nota abaixo |
| `FAIL repo-structure ... not executable in the git index` | arquivo commitado do Windows sem o bit | `git update-index --chmod=+x <arquivo>` |
| `FAIL gitleaks` | segredo ou falso positivo | remova o segredo e gire a credencial; falso positivo vai para `.gitleaksignore` com justificativa no PR. Antes do primeiro commit o check roda `gitleaks dir .`, que também lê arquivos ignorados pelo git (`terraform.tfvars`, `backend.hcl`, `terraform.tfstate`, `gha-creds-*.json`): mantenha credenciais locais fora da pasta do repositório |
| `FAIL policy-identifiers` | ID ou número de projeto, conta de faturamento, e-mail ou IP real | use `tx03v2-lab-example`, `000000000000`, `000000-000000-000000`, `you@example.com`, `203.0.113.10` |

Nota sobre o kubeconform (verificado em 2026-10-10 no tx01v2, mesmo pin aqui e no tx02v2): a revisão
de 2026-10-08 de `external-secrets.io/clustersecretstore_v1.json` no datreeio/CRDs-catalog
(`b7e2015`, gerada do ESO 2.12) contém `"additionalProperties": false` dentro de um mapa
`properties` (provider `crd`), e o kubeconform não consegue compilá-la ("could not find schema"). O
harness usa a revisão anterior (commit `f3e4382`, 2026-06-02), que valida o ClusterSecretStore deste
repositório em modo estrito (um campo com erro de digitação é rejeitado). Reavalie a cada revisão
trimestral (`docs/SUSTENTACAO.md`, 5.7).
