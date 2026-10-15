# Runbook: uma rodada completa na nuvem

Passo a passo para subir o lab no seu projeto Google Cloud, publicar o app do `dx03v2`, destruir tudo
e registrar o resultado. Nada disto foi executado em nuvem na v2 (`não executado em nuvem (v2)`):
você será a primeira evidência. Os tempos abaixo são estimativas, não medições. O deploy do app
segue o [runbook do dx03v2](https://github.com/maringelix/dx03v2/blob/main/docs/RUNBOOK.md)
(também `não executado em nuvem (v2)`).

> **Custo**: com os padrões, cerca de US$0,12 por hora em `us-central1` enquanto o free tier da GKE
> cobre a taxa do cluster, cerca de US$0,22 por hora sem ele. Os maiores itens são a taxa do cluster
> (sem o free tier), o Cloud SQL e o load balancer. Uma rodada de 3 horas fica perto de
> US$0,40-0,70 mais dados; um lab esquecido custa cerca de US$90-160 por mês. Estimativas com os
> preços de tabela lidos em 2026-10-11, não verificadas numa fatura (`docs/CUSTOS.md`). Destrua no
> mesmo dia.

## 1. Pré-requisitos

- Projeto **dedicado** ao lab, criado por você e com faturamento vinculado: o budget, o
  `scripts/leftovers.sh` e os papéis do CI valem para o projeto inteiro (toda forwarding rule,
  endereço, disco, instância e segredo dele conta). Os exemplos usam `tx03v2-lab-example`.
- Você precisa ser **Owner** do projeto para o bootstrap (liga APIs, cria contas de serviço e
  concede papéis) e de um papel na conta de faturamento que crie budgets (por exemplo Billing Account
  Administrator ou Billing Account Costs Manager; o Owner do projeto não basta).
- Ferramentas: Google Cloud CLI (`gcloud`) com o componente `gke-gcloud-auth-plugin`, `jq`, `gh`
  autenticado e as ferramentas do harness com `make tools` (terraform, kubectl, helm). O deploy do
  dx03v2 a partir de um laptop também precisa de Docker com buildx e Node.js 24 (runbook do dx03v2).
- Repositórios `tx03v2` e `dx03v2` no GitHub (seus forks ou os originais), públicos e com
  `scripts/repo-guardrails.sh` aplicado (environment `lab` com revisor obrigatório e só `main`;
  `docs/PUBLICACAO.md`). Os sujeitos do Workload Identity Federation aceitam o apply e o deploy só no
  environment `lab`. Num fork, use o seu usuário em `github_owner`.
- Cotas e restrições: confira as cotas regionais do projeto (Compute Engine, Cloud SQL) no console
  antes da rodada; contas com créditos de avaliação podem ter limites próprios (não verificado).
- Tempo estimado: bootstrap ~5 min; apply ~20–40 min (cluster Autopilot e instância Cloud SQL);
  plataforma ~10 min; deploy do dx03v2 ~15 min; destroy ~20–40 min. Uma rodada completa: 2–3 horas.

## 2. Bootstrap (uma vez, local, como Owner)

```bash
gcloud auth login
gcloud auth application-default login
gcloud billing projects describe tx03v2-lab-example --format='value(billingAccountName)'   # billingAccounts/<conta>
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # project_id, billing_account (sem o prefixo), budget_alert_emails, github_owner
terraform init
terraform apply
terraform output -raw backend_hcl > ../envs/lab/backend.hcl
terraform output github_variables_tx03v2       # seção 3
terraform output github_variables_dx03v2       # seção 3
```

O bootstrap liga as 15 APIs do lab (nunca desligadas no destroy), cria o bucket do state
(`tx03v2-tfstate-<suffix>`, com `suffix = substr(sha1(project_id), 0, 8)`; versionado, acesso
uniforme, prevenção de acesso público), o pool `tx03v2-github` com o provider `github`, as contas
`tx03v2-gha-plan`, `tx03v2-gha-apply` e `dx03v2-gha-deploy` com um vínculo por sujeito exato e os
papéis do contrato, e o budget mensal (padrão 10 na moeda da conta de faturamento, alertas de 50, 90
e 100 % do gasto e de 100 % da previsão para os administradores da conta e os e-mails opcionais).

- `github_owner` não tem padrão: use o seu usuário do GitHub, o dono dos repositórios `tx03v2` e
  `dx03v2` (ou dos seus forks). O placeholder do exemplo (`your-github-user`) e o e-mail
  `you@example.com` são recusados.
- O state do bootstrap fica **local** (`terraform.tfstate`, ignorado pelo git). Faça backup dele.
- O provider usa as suas credenciais de usuário (ADC) com `user_project_override` e o próprio
  projeto como projeto de cota (a API de budgets exige um).
- APIs recém-ligadas podem levar alguns minutos para responder: se um recurso falhar com
  `SERVICE_DISABLED` logo depois de ligar a API, espere e rode `terraform apply` de novo.
- Opcional, migrar o state do bootstrap para o bucket: crie `terraform/bootstrap/backend_override.tf`
  (ignorado pelo git) com o bloco abaixo e rode
  `terraform init -migrate-state -backend-config="bucket=tx03v2-tfstate-<suffix>" -backend-config="prefix=bootstrap"`.
  O harness lê todo `.tf` em `terraform/`: o bloco não pode ter argumentos. Antes do teardown
  (seção 10), volte para local: apague o arquivo e rode `terraform init -migrate-state`.

  ```hcl
  terraform {
    backend "gcs" {}
  }
  ```

## 3. Variáveis do GitHub

Settings > Secrets and variables > Actions > **Variables**, como variáveis de repositório (o job de
plan não roda num environment). Elas aparecem nos logs: não coloque nada privado. Os workflows
conferem o formato no primeiro passo (e que as contas e o bucket são os do projeto), mascaram nos
logs o ID e o número do projeto e o sufixo, e trocam esses valores por `<PROJECT_ID>`,
`<PROJECT_NUMBER>` e `<SUFFIX>` nos resumos.

O `FORK.md` (passo 7) grava os outputs `github_variables_tx03v2` e `github_variables_dx03v2` do
bootstrap com `gh variable set -f`; as variáveis `LAB_*` que você escolhe vêm da tabela abaixo.

### tx03v2

| Variável | Exemplo | Usada por | Vem de |
|---|---|---|---|
| `GCP_PROJECT_ID` | `tx03v2-lab-example` | todos os workflows de nuvem | output `github_variables_tx03v2` |
| `GCP_REGION` | `us-central1` | todos os workflows de nuvem (`TF_VAR_region`, `REGION`) | idem; tem de ser a região do bootstrap |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/000000000000/locations/global/workloadIdentityPools/tx03v2-github/providers/github` | todos os workflows de nuvem | idem (`workload_identity_provider`) |
| `GCP_PLAN_SERVICE_ACCOUNT` | `tx03v2-gha-plan@tx03v2-lab-example.iam.gserviceaccount.com` | plan (também liga a guarda do workflow) | idem (`plan_service_account`) |
| `GCP_APPLY_SERVICE_ACCOUNT` | `tx03v2-gha-apply@tx03v2-lab-example.iam.gserviceaccount.com` | apply, platform, destroy | idem (`apply_service_account`) |
| `TF_STATE_BUCKET` | `tx03v2-tfstate-00000000` | plan, apply, destroy | idem (`state_bucket_name`) |
| `LAB_DEPLOY_SERVICE_ACCOUNT` | `dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com` | plan, apply, destroy (`TF_VAR_deploy_service_account`) | idem (`deploy_service_account`) |
| `LAB_APP_DEPLOYER_MEMBERS` | `["user:you@example.com"]` | `TF_VAR_app_deployer_members` e o workflow `platform` (RoleBinding) | opcional, padrão `[]`; lista JSON de `user:<e-mail>` ou `serviceAccount:<e-mail>` (sem `group:`) de quem faz deploy do dx03v2 de um laptop |
| `LAB_ENABLE_WAF` | `true` | `TF_VAR_enable_waf` | opcional, padrão `true` (`docs/CUSTOS.md`) |
| `LAB_DB_TIER` | `db-g1-small` | `TF_VAR_db_tier` | opcional, padrão `db-g1-small` (a validação recusa `db-f1-micro`) |

`TF_VAR_github_owner` vem de `github.repository_owner`. Os demais inputs usam os padrões de
`terraform/envs/lab/variables.tf`; para mudar um (por exemplo `nodes_subnet_cidr`), adicione o
`TF_VAR_<nome>` ao bloco `env` dos workflows num PR.

### dx03v2

| Variável | Exemplo | Vem de |
|---|---|---|
| `GCP_PROJECT_ID` | `tx03v2-lab-example` | output `github_variables_dx03v2` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/000000000000/locations/global/workloadIdentityPools/tx03v2-github/providers/github` | idem |
| `GCP_DEPLOY_SERVICE_ACCOUNT` | `dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com` | idem |

O workflow `deploy-gcp` do dx03v2 roda no environment `lab` daquele repositório (sujeito
`repo:<owner>/dx03v2:environment:lab`) e lê o resto do contrato no Parameter Manager.

## 4. Apply

1. Dispare `terraform-plan` a partir de `main` (ou abra um PR que mexa em `terraform/**`) e leia o
   plano no resumo do job (identificadores substituídos; o texto também fica 7 dias como artefato).
2. Dispare `terraform-apply` e aprove o environment `lab`. O job planeja e aplica no mesmo run (o
   plano salvo do próprio job) e escreve os outputs no resumo.

Alternativa local, com as suas credenciais de Owner (ADC):

```bash
cd terraform/envs/lab
cp terraform.tfvars.example terraform.tfvars   # seus valores reais (arquivo ignorado pelo git)
terraform init -backend-config=backend.hcl
terraform plan -out tfplan && terraform apply tfplan
terraform output
```

O apply cria a VPC, a subnet dos nós com as faixas secundárias, o Cloud Router e o Cloud NAT, o
endereço global `tx03v2-lab-gateway`, o cluster Autopilot `tx03v2-lab` e a conta dos nós, a instância
Cloud SQL `tx03v2-lab-<4 hex>` com o endpoint PSC `tx03v2-lab-db` e a zona privada
`<region>.sql.goog.`, os dois segredos, o repositório `dx03v2`, a política `tx03v2-lab-waf` (ou nada,
com `enable_waf = false`), o parâmetro `tx03v2-lab-contract` e todas as concessões IAM do lab.

## 5. Plataforma

Dispare `platform` com `action=install` e aprove o environment `lab`. Ele roda como
`tx03v2-gha-apply` (`roles/container.admin`) pelo endpoint DNS do cluster, então os runners não
precisam de lista de IPs. O `platform/install.sh`:

1. lê o contrato com `gcloud parametermanager parameters versions render latest` e confere o
   projeto, a região, o nome do ClusterSecretStore e o e-mail da conta de deploy; acrescenta os
   e-mails de `APP_DEPLOYER_MEMBERS` (recusa `group:`) e renderiza `platform/manifests` antes de
   instalar qualquer coisa;
2. gera um kubeconfig temporário (`gcloud container clusters get-credentials --dns-endpoint`) e
   confere o `/readyz` do API server;
3. baixa o chart do External Secrets Operator 2.12.0 por tag e digest, recusa o arquivo se o SHA256
   diferir de `platform/versions.env` e instala-o em `external-secrets` (`--wait=watcher
   --rollback-on-failure`, 15 min);
4. aplica os namespaces `dx03v2` e `observability`, Role, RoleBinding e ClusterSecretStore (até 5
   tentativas enquanto o webhook do ESO sobe);
5. baixa o chart do OpenTelemetry Collector 0.176.0, recusa o arquivo se o SHA256 diferir de
   `platform/versions.env` e instala-o em `observability` com o projeto do lab (contrato v2: traces no
   Cloud Trace com o principal do próprio ServiceAccount `opentelemetry-collector`);
6. espera o `gcp-secret-manager` ficar `Ready` (o ESO alcançou o Secret Manager com a identidade do
   próprio ServiceAccount).

Ao atualizar um lab criado antes do contrato v2: `roles/cloudtrace.agent` entrou na condição IAM de
`tx03v2-gha-apply` e a API `cloudtrace.googleapis.com` na lista do bootstrap, então aplique o
bootstrap de novo (seção 2) antes do apply.

O controlador de Gateway da GKE é gerenciado pelo Google: nada a instalar. Localmente (como Owner):

```bash
make tools
gcloud auth login
export GCP_PROJECT_ID=tx03v2-lab-example
APP_DEPLOYER_MEMBERS='[]' platform/install.sh   # a mesma lista de LAB_APP_DEPLOYER_MEMBERS
export KUBECONFIG=/tmp/tx03v2-lab.kubeconfig
gcloud container clusters get-credentials tx03v2-lab --location us-central1 --project "$GCP_PROJECT_ID" --dns-endpoint
kubectl get gatewayclass gke-l7-global-external-managed
kubectl get clustersecretstore gcp-secret-manager
kubectl -n dx03v2 get role,rolebinding
```

`APP_DEPLOYER_MEMBERS` tem de ser a mesma lista da variável Terraform `app_deployer_members`: o
Terraform dá os papéis IAM, a plataforma dá a RoleBinding.

## 6. Deploy do app (dx03v2, `não executado em nuvem (v2)`)

Dispare o workflow `deploy-gcp` do [dx03v2](https://github.com/maringelix/dx03v2) e aprove o
environment `lab` de lá (ou rode `scripts/deploy-gcp.sh` de um laptop; passo a passo no
[runbook do dx03v2](https://github.com/maringelix/dx03v2/blob/main/docs/RUNBOOK.md)). O script lê as
15 chaves de `tx03v2-lab-contract`, publica `dx03v2/api` e `dx03v2/web` no Artifact Registry (tag =
SHA do commit, nunca sobrescrita), cria o ConfigMap `cloudsql-ca` com o bundle da região (só com a
raiz do contrato), aplica o overlay `gcp-waf` (ou `gcp`, quando `waf/security-policy` é `none`) no
namespace `dx03v2`, espera os ExternalSecrets, os rollouts e o Gateway `Programmed` com o endereço
`gateway/address`, e roda o smoke test pelo load balancer.

Para fazer o deploy de um laptop, coloque `user:<seu e-mail>` em `LAB_APP_DEPLOYER_MEMBERS`, rode o
apply (papéis IAM de `dx03v2-gha-deploy` para você) e o `platform` de novo (RoleBinding).

## 7. Smoke test

Esperado, não verificado:

```bash
terraform -chdir=terraform/envs/lab output -raw gateway_address
kubectl -n dx03v2 get gateway dx03v2                        # PROGRAMMED True, ADDRESS = gateway_address
curl -fsS "http://<GATEWAY_ADDRESS>/healthz"                 # web
curl -fsS "http://<GATEWAY_ADDRESS>/api/info"                # api
kubectl -n dx03v2 get externalsecrets                        # SecretSynced
kubectl -n dx03v2 get healthcheckpolicies,gcpbackendpolicies
```

Com o WAF, uma requisição com padrão de SQL injection deve receber 403 do Cloud Armor
(`curl -s -o /dev/null -w '%{http_code}\n' "http://<GATEWAY_ADDRESS>/api/info?id=1%27%20OR%20%271%27=%271"`).
O load balancer pode levar vários minutos para responder depois do `Programmed`. Registre o
resultado no `cloud_run_report`.

Traces (contrato v2), esperado e não verificado: depois de algumas requisições, o Trace Explorer do
projeto mostra o serviço `dx03v2-api` (span da rota e da consulta ao PostgreSQL). Nada em alguns
minutos: `kubectl -n observability logs deployment/opentelemetry-collector` (um `PermissionDenied` do
exporter `googlecloud` aponta para a concessão `roles/cloudtrace.agent` do principal do Collector).

## 8. Destroy

Dispare `terraform-destroy` com a confirmação `destroy tx03v2-lab` e aprove o environment `lab`. O
job roda `platform/uninstall.sh` se o cluster existir (apaga o namespace `dx03v2`, espera o finalizer
do Gateway e o sumiço dos NEGs do app, até 900 s cada, e desinstala o ESO), `terraform destroy` e
`scripts/leftovers.sh --retry-for 900`. Qualquer erro para o job: leia o log, corrija e rode de novo.
O `platform/uninstall.sh` só age no cluster `tx03v2-lab` com o label `project=tx03v2`; nenhuma
variável de ambiente (`CLUSTER_NAME`, por exemplo) muda o alvo, e o kubeconfig dele é temporário.
Localmente:

```bash
export GCP_PROJECT_ID=tx03v2-lab-example
platform/uninstall.sh
terraform -chdir=terraform/envs/lab destroy
scripts/leftovers.sh --retry-for 900
```

O bootstrap continua (APIs, bucket, pool, contas de serviço, budget). Os backups da instância somem
com ela (`retain_backups_on_delete = false`); o nome da instância fica reservado por até uma semana,
e a próxima rodada usa outro sufixo aleatório.

## 9. Sobras

No workflow, o `scripts/leftovers.sh` roda com a identidade do apply; uma lista que ela não consiga
ler aparece como `UNCHECKED`, com um aviso, sem mudar o código de saída. Para uma checagem completa,
rode localmente como Owner do projeto:

```bash
gcloud auth login
GCP_PROJECT_ID=tx03v2-lab-example scripts/leftovers.sh --retry-for 900
```

Níveis: `BILLABLE` (ainda custa; sai com 1), `ORPHANED` (grátis, mas atrapalha a próxima rodada),
`INFO` (recursos do bootstrap, APIs desligadas), `UNCHECKED`; saída 2 = problema de login,
`GCP_PROJECT_ID` ausente ou erro da API. Remoção manual dos casos mais comuns (peças do load balancer
na ordem: forwarding rule, proxy, URL map, backend service, health check, NEG):

```bash
p=tx03v2-lab-example
gcloud compute forwarding-rules delete <NOME> --global --project "$p"
gcloud compute target-http-proxies delete <NOME> --global --project "$p"
gcloud compute url-maps delete <NOME> --global --project "$p"
gcloud compute backend-services delete <NOME> --global --project "$p"
gcloud compute health-checks delete <NOME> --global --project "$p"
gcloud compute network-endpoint-groups delete <NOME> --zone <ZONA> --project "$p"
gcloud compute addresses delete tx03v2-lab-gateway --global --project "$p"
gcloud compute disks delete <NOME> --zone <ZONA> --project "$p"
gcloud compute firewall-rules delete <NOME> --project "$p"
gcloud sql instances delete <NOME> --project "$p"
```

Rode o script de novo até não sobrar nada `BILLABLE`.

## 10. Teardown do bootstrap (fim da série de rodadas)

1. Lab destruído e `scripts/leftovers.sh` limpo, rodado localmente como Owner.
2. State do bootstrap de volta para local, se tiver sido migrado (seção 2).
3. Em `terraform/bootstrap`: `state_protection = false` no `terraform.tfvars` e `terraform apply` (só
   troca o `deletion_policy` do bucket).
4. Esvazie o bucket, com as versões antigas (o `force_destroy` continua `false`):
   `gcloud storage rm --all-versions "gs://tx03v2-tfstate-<suffix>/**"`.
5. `terraform destroy`: apaga o bucket, o pool e o provider, as três contas de serviço, os papéis,
   os canais de notificação e o budget. As APIs continuam ligadas (não custam nada). O pool fica em
   soft delete por 30 dias e o ID `tx03v2-github` não pode ser reutilizado nesse tempo
   (`docs/ARQUITETURA.md`, "Nomes que ficam presos").
6. Para encerrar de vez, apague o projeto dedicado (`gcloud projects delete tx03v2-lab-example`): ele
   fica desligado e pendente de exclusão por 30 dias.
7. Confira os relatórios do Cloud Billing no dia seguinte.

## 11. Registro

Abra uma issue com o template **Cloud run report**: data, região, conta de faturamento (créditos ou
paga), commits do tx03v2/dx03v2, versões (Terraform, GKE, `enable_waf`, `db_tier`), passos, duração,
custo observado nos relatórios do Cloud Billing (agrupe por SKU e diga se o free tier da GKE cobriu
a taxa do cluster; `docs/CUSTOS.md`), problemas e a saída (redigida) do `scripts/leftovers.sh`. A
matriz de status do README só muda com essa evidência.

## 12. Problemas comuns

Causas prováveis, não verificadas em nuvem na v2:

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `SERVICE_DISABLED` ou `API has not been used in project` | bootstrap não aplicado neste projeto, ou API recém-ligada | aplique o bootstrap (seção 2); espere alguns minutos e repita |
| Erro de quota project com credenciais de usuário | ADC sem projeto de cota | `gcloud auth application-default set-quota-project tx03v2-lab-example` |
| 403 ao criar o budget | sem papel na conta de faturamento | Billing Account Administrator ou Costs Manager (seção 1) |
| `google-github-actions/auth` falha com `Permission 'iam.serviceAccounts.getAccessToken' denied` | o sujeito não casa: job fora do environment `lab`, outro dono ou fork, variável errada | confira o environment, `github_owner` do bootstrap e as variáveis (seção 3) |
| `terraform init` do lab com 403 no bucket | conta errada em `GCP_*_SERVICE_ACCOUNT` ou `TF_STATE_BUCKET` de outro projeto | confira com os outputs do bootstrap |
| `the DNS endpoint of tx03v2-lab does not answer, or this identity has no Kubernetes access` | identidade sem `container.clusters.connect` (`clusterViewer`) ou sem RBAC | confira os papéis do deployer e a RoleBinding (`platform` de novo) |
| `cannot render tx03v2-lab-contract` | apply não rodou, ou a identidade não tem `parameterAccessor` | rode o apply; confira os papéis |
| `kubectl wait ... clustersecretstore/gcp-secret-manager` expira | o ESO não alcança o Secret Manager | `kubectl describe clustersecretstore gcp-secret-manager`; confira as concessões dos segredos e o pool `<PROJECT_ID>.svc.id.goog` |
| `platform/uninstall.sh` expira esperando NEGs | o controlador do Gateway ainda apaga o load balancer | rode de novo; confira `gcloud compute network-endpoint-groups list` |
| `Requested entity already exists` no pool `tx03v2-github` | pool de um bootstrap anterior em soft delete (30 dias) | `gcloud iam workload-identity-pools undelete tx03v2-github --location=global` e importe no state, ou use outro projeto |
| `leftovers.sh` sai com 2 | `gcloud` sem login, `GCP_PROJECT_ID` ausente ou erro da API | faça login e rode de novo; nunca leia isso como "nada sobrou" |
