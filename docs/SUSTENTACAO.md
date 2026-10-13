# Sustentação do tx03v2

Como manter o repositório saudável sem conta na nuvem: rotinas, calendário de fim de suporte e
procedimentos passo a passo. Datas e versões verificadas em 2026-10-11.

## 1. Objetivo e escopo

Cobre o código (Terraform, scripts, workflows), as ferramentas do harness, as versões de plataforma
(GKE, PostgreSQL no Cloud SQL, External Secrets, Google Cloud CLI, Gateway API) e as rodadas
opcionais em nuvem. Não cobre o app (ver o `dx03v2`), mas lista o que precisa mudar junto
com ele.

## 2. Estado atual

- Harness completo (`HARNESS_STRICT=1 make verify`) `verificado no CI` com 32 checks (jobs `static`
  e `test`); com os checks do lab local são 38, `verificado localmente` em container Linux (o CI
  ainda não rodou essa versão).
- Lab local (`docs/LAB_LOCAL.md`): `make e2e` com o perfil `full` (26 sondas) `verificado no CI`
  (job `e2e`) e `verificado localmente` em 2026-10-13 (rodada do zero, destroy sem sobras).
- Bootstrap, apply, plan em PRs, plataforma e destroy: `não executado em nuvem (v2)`.
- Contrato com o dx03v2: versão 1 (`docs/CONTRATO.md`); o dx03v2 confere a parte dele no próprio
  harness (CI verde lá) e o deploy dele é `não executado em nuvem (v2)`.
- Exceções do trivy: nenhuma (`.trivyignore.yaml` vazio).

## 3. Rotinas

| Quando | O quê | Como |
|---|---|---|
| Semanal (automático) | CI agendado (segunda 06:00 UTC) roda todo o harness | Falhou? Seção 6. Causas típicas: chart ou URL que mudou, achado novo do trivy, rede |
| Mensal | PRs do Dependabot (actions, providers Terraform, pre-commit) | Playbook "Dependency updater" do `AGENTS.md`; um PR por grupo, harness verde antes do merge |
| Trimestral | Ferramentas do harness, gcloud, chart e imagem do ESO, versões de plataforma (GKE, PostgreSQL, Gateway API), schemas do kubeconform, preços do `docs/CUSTOS.md`, preços do Autopilot e free tier da GKE, edições e tiers do Cloud SQL, raiz da CA do Cloud SQL (SHA-256 do contrato), comportamento do endpoint DNS e das redes autorizadas da GKE, ignores perto de vencer, regras `ignore` do Dependabot | Seções 4 e 5; registre no CHANGELOG |
| Por rodada em nuvem: antes | Ler `docs/CUSTOS.md`, conferir o budget, CI verde no commit, variáveis do GitHub, cotas do projeto | `docs/RUNBOOK.md`, seção 1 |
| Por rodada em nuvem: durante | Anotar horários e problemas; não deixar a rodada aberta de um dia para o outro | `docs/RUNBOOK.md` |
| Por rodada em nuvem: depois | destroy, `scripts/leftovers.sh` limpo localmente como Owner do projeto, issue `cloud_run_report`, matriz de status só com evidência | `docs/RUNBOOK.md`, seções 8 a 11 |

## 4. Calendário de fim de suporte

| Componente | Versão | Fim do suporte | Fonte | Ação |
|---|---|---|---|---|
| Kubernetes na GKE | 1.36 (padrão do canal REGULAR: 1.36.4-gke.1391002, nota de 2026-10-08) | fim do suporte padrão por volta de 2027-06-30 (endoflife.date; confirme no cronograma da GKE) | [cronograma de versões da GKE](https://cloud.google.com/kubernetes-engine/docs/release-schedule), [endoflife.date](https://endoflife.date/google-kubernetes-engine) | O canal REGULAR atualiza o cluster sozinho (o código não fixa versão); o repositório acompanha a minor nos schemas e no contrato (5.4) |
| Gateway API servida pela GKE | 1.5.0 (GKE >= 1.35.2-gke.1842000; ligada por padrão no Autopilot) | segue a versão da GKE | documentação "GatewayClass capabilities" da GKE | O dx03v2 fixa os schemas dessa versão; mudança junto com ele |
| PostgreSQL no Cloud SQL | 17 (edição ENTERPRISE) | fim de vida da comunidade em 2029-11-08 | [política de versões do PostgreSQL](https://www.postgresql.org/support/versioning/) | Upgrade de major (mudança de contrato, PR no dx03v2) antes de 2029-11-08; confira o suporte estendido do Cloud SQL |
| Terraform CLI | 1.16.5 (`>= 1.11`) | sem data fixa | [releases](https://releases.hashicorp.com/terraform/) | Trimestral (5.2) |
| Provider hashicorp/google | 8.6.0 (`~> 8.6`) | sem data fixa; em geral uma major por ano (o Dependabot ignora majors) | registry.terraform.io | Dependabot mensal (5.3); a cada versão, reavaliar os papéis do plan (5.10) |
| Provider hashicorp/random | 3.9.1 (`~> 3.9`) | sem data fixa | registry.terraform.io | Dependabot mensal |
| tflint-ruleset-google | 0.40.0 (2026-09-23) | sem data | [releases](https://github.com/terraform-linters/tflint-ruleset-google/releases) | Trimestral (5.1) |
| External Secrets Operator | v2.12.0 (chart OCI 2.12.0, CRDs `external-secrets.io/v1`) | o projeto mantém só as versões recentes | [releases](https://github.com/external-secrets/external-secrets/releases) | Trimestral (5.5), junto com o tx01v2 e o tx02v2 |
| Google Cloud CLI (gcloud) | 588.0.0 (2026-10-02), com `gke-gcloud-auth-plugin` | sem política por versão; versões novas toda semana | [release notes](https://cloud.google.com/sdk/docs/release-notes) | Trimestral (5.6) |
| `google-github-actions/auth` / `setup-gcloud` | v3.0.0 / v3.0.1 | sem data publicada | releases dos repositórios | Dependabot de actions (5.8) |
| kubectl / Helm | 1.37.1 / 4.3.0 | kubectl suporta ±1 minor da API (1.36–1.38) | kubernetes.io, helm.sh | Acompanhar a minor do cluster; o Helm 4 usa `--rollback-on-failure` no lugar de `--atomic` |
| Raiz da CA do Cloud SQL (contrato) | `CN=Google Cloud SQL Root Server CA 0b29df` (ECDSA P-384) | válida até 2049-06-27 | `https://storage.googleapis.com/cloudsql-ca-bundles/<region>.pem` | Trocar a raiz é mudança de contrato; as CAs subordinadas giram sem aviso (5.12) |
| Runners e devcontainer | Ubuntu 24.04 LTS | suporte padrão até 2029-04 | ubuntu.com | Trocar antes do fim |
| Schemas do kubeconform | yannh/kubernetes-json-schema `5f1fa4f` (1.36.0); datreeio/CRDs-catalog `f3e4382` (2026-06-02) | — | `docs/HARNESS.md` | Reavaliar a cada revisão trimestral (5.7) |
| Exceções do trivy | nenhuma | — | `.trivyignore.yaml` | Uma exceção nova precisa de `statement` e `expired_at` (5.9) |
| Istio (lab local) | 1.31.1 | ~2027-02 (6 semanas depois da 1.33) | [releases suportadas](https://istio.io/latest/docs/releases/supported-releases/) | Trimestral (5.14), junto com o tx01v2 |
| Demais charts do lab local | `platform/local/versions.env` (cert-manager 1.21.2, kube-prometheus-stack 92.3.0, Loki 7.3.0, Alloy 1.13.1, Argo CD 10.10.3, Gatekeeper 3.23.1, Trivy Operator 0.37.0, Velero 12.2.1, Chaos Mesh 2.8.4, metrics-server 3.14.0) | cada projeto mantém as versões recentes | releases de cada projeto | Trimestral (5.14), junto com o tx01v2 |
| Imagens dos serviços emulados | registry 3.1.2, Versity S3 Gateway 1.8.0, Soft Serve 0.12.3, cloud-provider-kind 0.12.0, PostgreSQL 17 | sem data fixa | `terraform/envs/local/images.tf` | Trimestral (5.14) |
| kind / gator | 0.33.0 (nó `kindest/node:v1.36.4`) / 3.23.1 | sem política publicada | releases do kind e do Gatekeeper | Trimestral (5.14); o nó segue a minor da GKE do lab |

## 5. Procedimentos

### 5.1 Ferramenta do harness (terraform, tflint, ruleset google, trivy, actionlint, shellcheck, kubeconform, gitleaks, kubectl, helm, kind, gator)

```bash
scripts/update-tool-checksums.sh trivy 0.76.0   # baixa o arquivo de checksums oficial da release
make tools && HARNESS_STRICT=1 make verify
git diff tools/ .tflint.hcl                     # versions.env + checksums.txt (+ .tflint.hcl para o ruleset)
```

O script lê o arquivo de checksums publicado na release exata (o shellcheck não publica: o script
baixa os três artefatos e calcula o SHA256) para linux_amd64, linux_arm64 e darwin_arm64. Leia as
release notes antes. Casos especiais:

- gitleaks: atualize também o `rev:` do hook em `.pre-commit-config.yaml` (SHA do commit da tag +
  `# frozen: vX.Y.Z`); o `version-consistency` compara os dois.
- tflint-ruleset-google: o script já atualiza o `version` de `.tflint.hcl`; confira que o ruleset
  carrega com o google 8.x (`tflint` com 0 issues).
- trivy: achados novos aparecem com a ferramenta nova, porque o harness usa as regras embutidas
  (`--skip-check-update`).
- kubectl: fique a no máximo uma minor de distância do cluster.

### 5.2 Terraform CLI

Atualize com `scripts/update-tool-checksums.sh terraform <versão>`. `required_version` só muda se a
versão mínima precisar subir (todos os `versions.tf` iguais, checado pelo `version-consistency`).

### 5.3 Providers (google, random) e lock em 4 plataformas

1. Leia o CHANGELOG e, numa major, o guia de upgrade do provider.
2. Mesma restrição em todos os `versions.tf`, inclusive os de `terraform/modules/*` (o PR do
   Dependabot só altera os roots; o `version-consistency` exige a mesma restrição em todos).
3. Em `terraform/bootstrap` e `terraform/envs/lab`:
   ```bash
   terraform init -backend=false -upgrade
   terraform providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64 -platform=windows_amd64
   ```
4. `HARNESS_STRICT=1 make verify`: `terraform-lockfiles` exige 4 hashes `h1:` por provider, os dois
   roots precisam travar a mesma versão do google e o `terraform-validate:*` usa o schema novo.
   Confira no schema da versão nova (`terraform providers schema -json`) os atributos que o lab usa
   (por exemplo `control_plane_endpoints_config`, `psc_config`, `server_ca_mode`, `secret_data_wo`,
   `password_wo`) e se apareceu um `google_parameter_manager_parameter_iam_member` (permitiria trocar
   o `parameterAccessor` de projeto por uma concessão no parâmetro: mudança de contrato).
5. Faça a revisão de papéis do plan da seção 5.10.

### 5.4 Versão do Kubernetes

O cluster segue o canal REGULAR: não há `min_master_version` (o `policy-terraform` recusa) e o
Autopilot atualiza sozinho. Quando a minor padrão do canal mudar (release notes da GKE):

1. `GKE_KUBERNETES_MINOR`, `K8S_SCHEMA_KUBERNETES_VERSION` e, se preciso, `K8S_SCHEMA_REF` em
   `scripts/harness.sh` (o `version-consistency` compara a minor do lab com a dos schemas).
2. A minor citada no `docs/CONTRATO.md` (mudança de contrato: versão + PR no dx03v2; o
   `version-consistency` exige exatamente a minor de `GKE_KUBERNETES_MINOR`).
3. `kubectl` a no máximo uma minor de distância (5.1).
4. No dx03v2: a mesma minor nos schemas, no kind e no kubectl dele.
5. Lab local: a imagem do nó em `terraform/envs/local/kind-config.yaml` (o `local-versions` exige a
   minor de `GKE_KUBERNETES_MINOR`; 5.14).

### 5.5 External Secrets Operator (junto com o tx01v2 e o tx02v2)

1. Leia as release notes (versão de API dos CRDs, valores do chart, requisitos de Kubernetes).
2. Chart: `helm pull oci://ghcr.io/external-secrets/charts/external-secrets --version <versão>`
   imprime o `Digest:` do manifest OCI (`ESO_CHART_DIGEST`); `sha256sum external-secrets-<versão>.tgz`
   dá o `ESO_CHART_SHA256`. Atualize também `ESO_CHART_VERSION` em `platform/versions.env` e o
   `ESO_SHA256` do lab local (`platform/local/versions.env`, o mesmo arquivo pelo repositório HTTP;
   o `local-versions` exige os dois iguais).
3. Imagem: `docker buildx imagetools inspect ghcr.io/external-secrets/external-secrets:v<versão>` →
   o digest do índice nas três entradas `tag:` de `platform/values/external-secrets.yaml` (controller,
   webhook e cert controller usam a mesma imagem; o `version-consistency` exige `v<versão>@sha256:`
   três vezes). Use a mesma release e o mesmo digest do tx01v2 e do tx02v2.
4. `HARNESS_STRICT=1 make verify`: o `helm-template` baixa o chart por tag e digest, confere o SHA256
   e renderiza com os values (as três imagens com o digest, requests nos três contêineres, o
   ServiceAccount `external-secrets` sem anotação); o `contract-platform` confere values e pins.
5. Se a versão de API dos CRDs mudar (`external-secrets.io/v1` hoje), é mudança de contrato, e o
   schema do ClusterSecretStore no kubeconform também muda (5.7).

O `platform/install.sh` recusa um chart com outro digest (o `helm pull` falha) ou outro SHA256.

### 5.6 Google Cloud CLI (gcloud)

1. Leia as release notes desde a versão atual (mudanças em `container clusters get-credentials`,
   `parametermanager`, `compute network-endpoint-groups`, `sql backups` e nos comandos de listagem do
   `scripts/leftovers.sh`).
2. `GCLOUD_VERSION` em `tools/versions.env` e o `version:` de todo passo `setup-gcloud`
   (`platform.yml`, `terraform-destroy.yml`), juntos: o `version-consistency` compara.
3. O componente `gke-gcloud-auth-plugin` vem pelo `install_components` do mesmo passo.

### 5.7 Schemas do kubeconform

`K8S_SCHEMA_REF` (yannh/kubernetes-json-schema) e `CRD_SCHEMA_REF` (datreeio/CRDs-catalog) em
`scripts/harness.sh` apontam para commits fixos, os mesmos do tx01v2 e do tx02v2:
`gh api 'repos/datreeio/CRDs-catalog/commits?path=external-secrets.io/clustersecretstore_v1.json&per_page=3'`.
Veja a nota sobre o schema do ESO em `docs/HARNESS.md`.

### 5.8 Digests de imagens e actions

Devcontainer: `docker buildx imagetools inspect mcr.microsoft.com/devcontainers/base:ubuntu-24.04`.
Actions (fora do Dependabot): `gh api repos/<o>/<r>/git/ref/tags/<tag>`; se `object.type == "tag"`,
siga `gh api repos/<o>/<r>/git/tags/<sha>`; use o SHA do commit com `# vX.Y.Z` e confirme que ele
existe (`gh api repos/<o>/<r>/commits/<sha>`). O `version-consistency` exige um SHA por action em
todos os workflows. Nunca `aquasecurity/trivy-action` nem `setup-trivy` (o `policy-workflows` recusa).

### 5.9 Revisão das exceções do trivy

Hoje não há nenhuma. Se uma entrada for adicionada a `.trivyignore.yaml` (`docs/GUARDRAILS.md`,
"Exceções"): perto do `expired_at`, o motivo ainda vale? Se sim, renove por até ~7 meses com a
justificativa atualizada; se não, corrija o código e remova a entrada. O `trivyignore-policy` recusa
entradas vencidas ou com validade longa demais.

### 5.10 Papéis do plan depois de um bump do google

O plan só funciona se o refresh do provider não pedir nada além dos papéis de `tx03v2-gha-plan`
(`roles/viewer`, `roles/iam.securityReviewer`, `roles/parametermanager.parameterViewer` e
`roles/storage.objectViewer` no bucket; `docs/ARQUITETURA.md`, ADR 16). Numa versão nova, procure no
código do provider o que o `Read` de `google_parameter_manager_parameter_version` (hoje um GET com o
payload, que exige `parametermanager.parameterVersions.get`), `google_secret_manager_secret_version`
(com `secret_data_wo_version` ele não pode chamar `:access`), `google_sql_user`,
`google_container_cluster` e dos recursos `*_iam_member` chama. Se aparecer uma chamada nova,
ajuste `plan_project_roles` em `terraform/bootstrap/roles.tf` com o papel de menor privilégio e o
teste `plan_identity_is_read_only` (que recusa papéis de escrita, de personificação e de acesso a
segredos).

### 5.11 Preços

Na revisão trimestral, releia as páginas de preço (GKE, Cloud SQL, Cloud Load Balancing, Cloud
Armor, Cloud NAT, Private Service Connect, Cloud DNS, Secret Manager, Parameter Manager, Artifact
Registry, Cloud Logging) para us-central1, atualize a data e os totais do `docs/CUSTOS.md` e do
README e confira o free tier da GKE e os preços do Autopilot.

### 5.12 Cloud SQL: edições, tiers e a raiz da CA

1. Confira que o PostgreSQL 17 e o tier `db-g1-small` continuam oferecidos na edição ENTERPRISE e o
   `max_connections` padrão do tier (50, assumido; a conta do contrato depende dele). Se mudar,
   ajuste a validação de `db_tier` em `terraform/envs/lab/variables.tf` e os testes.
2. Baixe o bundle da região e confira a raiz (o certificado com `subject` igual ao `issuer`):
   ```bash
   curl -fsS https://storage.googleapis.com/cloudsql-ca-bundles/us-central1.pem -o /tmp/ca.pem
   awk '/BEGIN CERT/ { n++ } n { print > ("/tmp/ca-" n ".pem") }' /tmp/ca.pem
   for f in /tmp/ca-*.pem; do openssl x509 -in "$f" -noout -subject -issuer -fingerprint -sha256; done
   ```
   O SHA-256 da raiz tem de ser o da tabela de `docs/CONTRATO.md`. Uma raiz nova é mudança de
   contrato: o deploy do dx03v2 recusa bundles com outra raiz.

### 5.13 GKE: endpoint DNS, redes autorizadas e Autopilot

Nas release notes da GKE, procure mudanças no endpoint DNS do plano de controle
(`control_plane_endpoints_config`), nas redes autorizadas (`master_authorized_networks_config`,
`gcp_public_cidrs_access_enabled`), nos mínimos e proporções de recursos do Autopilot (50m de CPU e
52 MiB por pod, CPU:memória entre 1:1 e 1:6,5, assumidos) e no free tier. O teste
`autopilot_private_dns_endpoint_gateway` prova a configuração, não o comportamento da GKE.

### 5.14 Lab local (charts, imagens, kind)

Os pins são os mesmos do lab local do `tx01v2`: atualize os repositórios juntos.

1. Para cada chart de `platform/local/versions.env`: leia as notas da release, rode
   `helm pull <chart> --repo <repo> --version <nova>` e grave a versão e o `sha256sum` do `.tgz`. O
   ESO local segue a 5.5: `ESO_SHA256` igual a `ESO_CHART_SHA256` (o `local-versions` confere).
2. Atualize os digests em `platform/local/values/*.yaml` (`docker buildx imagetools inspect <imagem>:<tag>`
   devolve o digest do índice multi-arquitetura). O check `helm-template-local` recusa imagem sem digest.
3. Gatekeeper: suba `GATOR_VERSION` (`scripts/update-tool-checksums.sh gator <versão>`) junto com
   `GATEKEEPER_VERSION`; o check `local-versions` exige as duas iguais.
4. Imagens dos serviços emulados: `terraform/envs/local/images.tf` (o teste exige digest em todas). O
   nó do kind (`terraform/envs/local/kind-config.yaml`) segue o `GKE_KUBERNETES_MINOR` do harness
   (`local-versions` confere a minor).
5. Rode `make verify` e `make e2e` (ou deixe o job `e2e` do CI provar no PR) e registre no CHANGELOG.

## 6. Resposta a problemas

| Situação | Primeiros passos |
|---|---|
| CI vermelho | Leia o primeiro `FAIL` (o log do check vem logo abaixo). Corrija no código; nunca enfraqueça o check. Reproduza com `HARNESS_STRICT=1 make verify` |
| Vulnerabilidade | Alerta do Dependabot ou advisory: atualize por PR. Em ferramenta do harness: 5.1. No chart ou na imagem do ESO: 5.5. Reporte privado: `SECURITY.md` |
| Alerta de custo (e-mail do budget) | `scripts/leftovers.sh` localmente como Owner do projeto; se houver lab de pé, rode o destroy; confira os relatórios do Cloud Billing por serviço e SKU |
| Credencial exposta | Não há chaves de conta de serviço nem segredos de nuvem no GitHub. Se um segredo do Secret Manager vazar, gire com `db_password_version`/`admin_token_version` e rode o apply. Revise os vínculos `roles/iam.workloadIdentityUser` das contas de serviço e a condição do provider do pool. Reescrever histórico é decisão do mantenedor |
| Sobras após o destroy | Siga a saída de `scripts/leftovers.sh` e a seção 9 do `docs/RUNBOOK.md`; registre no `cloud_run_report` |
| Nome preso (pool de Workload Identity Federation em soft delete, instância Cloud SQL apagada) | `docs/ARQUITETURA.md`, "Nomes que ficam presos" |

## 7. Registro de execuções em nuvem

Toda rodada gera uma issue com o template `cloud_run_report` (data, região, conta de faturamento,
commits, passos, duração, custo observado, problemas, sobras). A matriz de status do README só muda
com essa evidência.

## 8. Responsáveis

Mantenedor: @maringelix (decisões, merges, rodadas em nuvem). Agentes de IA seguem o `AGENTS.md`.
