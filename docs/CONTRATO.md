# Contrato tx03v2 <-> dx03v2 — versão 1 (2026-10-11)

Interface entre a infraestrutura (este repositório) e a aplicação (`dx03v2`). Esta é a fonte da
verdade: `dx03v2/docs/CONTRATO.md` repete a parte que o app usa e aponta para cá. Qualquer mudança
exige PRs coordenados nos dois repositórios e incremento da versão. Os dois harnesses conferem a
parte que cada um controla. O formato é o mesmo dos contratos AWS (`tx01v2` ⇄ `dx01v2`) e Azure
(`tx02v2` ⇄ `dx02v2`), com os serviços equivalentes do Google Cloud.

## Como o contrato é verificado aqui

| O quê | Onde | Status |
|---|---|---|
| Pool e provider de Workload Identity Federation (issuer, mapeamento, condição), contas de serviço do CI e um sujeito exato por vínculo `roles/iam.workloadIdentityUser` | `terraform/bootstrap/tests/identities.tftest.hcl` | `verificado localmente` |
| Papéis do plan e do apply; a condição IAM do `roles/resourcemanager.projectIamAdmin` do apply lista exatamente os papéis de projeto que o root do lab concede | `terraform/bootstrap/tests/roles.tftest.hcl`, `terraform/envs/lab/tests/roles.tftest.hcl` | `verificado localmente` |
| Papéis de `dx03v2-gha-deploy`, dos `app_deployer_members`, do ESO e da conta de serviço dos nós | `terraform/envs/lab/tests/roles.tftest.hcl` | `verificado localmente` |
| As 15 chaves do parâmetro de contrato (nomes, valores fixos, origem de cada valor) | `terraform/envs/lab/tests/lab.tftest.hcl`; o check `contract-parameter` confere que `contract.tf`, a lista do harness e a tabela deste arquivo são iguais | `verificado localmente` |
| Secret Manager (segredos write-only), Cloud SQL (PSC, TLS, CA compartilhada), Artifact Registry | `terraform/envs/lab/tests/data_stores.tftest.hcl` | `verificado localmente` |
| GKE Autopilot (canal, nós privados, endpoint DNS, Gateway API), rede, NAT, endpoint PSC e zona DNS | `terraform/envs/lab/tests/gke.tftest.hcl`, `network.tftest.hcl` | `verificado localmente` |
| Cloud Armor (regras pré-configuradas, inspeção de 64 KB) e `none` sem WAF | `terraform/envs/lab/tests/waf.tftest.hcl` | `verificado localmente` |
| Namespace, Role, RoleBinding e ClusterSecretStore renderizados | checks `contract-platform` e `kubeconform` | `verificado localmente` |
| Comportamento real no Google Cloud | `docs/RUNBOOK.md` | `não executado em nuvem (v2)` |

## Equivalência com os contratos AWS e Azure

| AWS (tx01v2) | Azure (tx02v2) | Google Cloud (tx03v2) |
|---|---|---|
| EKS + access entries | AKS + Entra ID | GKE Autopilot + IAM do Google (endpoint DNS do control plane) e RBAC do Kubernetes para o deployer |
| EKS Pod Identity | Entra Workload ID | Workload Identity Federation for GKE (principal do ServiceAccount, sem conta de serviço do Google) |
| RDS PostgreSQL 17 | PostgreSQL Flexible Server 17 | Cloud SQL for PostgreSQL 17, edição Enterprise, acesso só por Private Service Connect |
| Secrets Manager | Key Vault (RBAC) | Secret Manager |
| SSM Parameter Store | App Configuration (Free) | Parameter Manager (um parâmetro JSON) |
| ECR | Azure Container Registry (Basic) | Artifact Registry (Docker, tags imutáveis) |
| ALB (Load Balancer Controller) + WAF | Application Gateway for Containers + WAF (DRS 2.1) | Gateway da GKE (Application Load Balancer externo global) + Cloud Armor |
| Papéis IAM com OIDC do GitHub | managed identities com credenciais federadas | contas de serviço com Workload Identity Federation para o GitHub |
| AWS Budgets | budget do Cost Management | budget do Cloud Billing (escopo do projeto) |

## Identificadores

| Item | Valor |
|---|---|
| Projeto Google Cloud | um projeto dedicado ao lab, criado pelo operador com faturamento vinculado (variável `project_id`; nos exemplos `tx03v2-lab-example`, número `000000000000`) |
| Região | variável `region`, padrão `us-central1` |
| Projeto / ambiente / prefixo | `tx03v2` / `lab` / `tx03v2-lab` |
| Labels (`default_labels` do provider, em todo recurso que aceita labels) | `project=tx03v2`, `environment=lab`, `managed-by=terraform`, `repository=<owner>_tx03v2` (valores de label não aceitam `/`) |
| Sufixo dos nomes globais | `suffix = substr(sha1(<project_id>), 0, 8)` (determinístico; nos exemplos `00000000`) |
| Bucket do state | `tx03v2-tfstate-<suffix>` (bootstrap; versionado, acesso uniforme, prevenção de acesso público) |
| Rede | VPC `tx03v2-lab` (modo custom); subnet `tx03v2-lab-nodes` (padrão `10.30.0.0/20`, Private Google Access ligado) com faixas secundárias `pods` (padrão `10.32.0.0/16`) e `services` (padrão `10.33.0.0/20`); Cloud Router `tx03v2-lab` + Cloud NAT `tx03v2-lab` (saída dos nós privados) |
| Cluster GKE | `tx03v2-lab`, **Autopilot**, regional (`region`), canal `REGULAR` (Kubernetes 1.36 no padrão do canal em 2026-10-08), nós privados, endpoint IP público desligado, endpoint DNS com tráfego externo liberado e autorização só pelo IAM, Gateway API (canal standard), Dataplane V2 (aplica NetworkPolicy), conta de serviço dos nós `tx03v2-lab-nodes` |
| Nós | x86-64 (o Autopilot usa a classe general-purpose): as imagens do dx03v2 são `linux/amd64` |
| Namespace do app | `dx03v2` — criado pela camada de plataforma do tx03v2 com os labels `pod-security.kubernetes.io/enforce=restricted`, `pod-security.kubernetes.io/enforce-version=latest` |
| RBAC Kubernetes do deployer | Role `dx03v2-deployer` + RoleBinding `dx03v2-deployers` no namespace `dx03v2`; sujeitos `kind: User`, `name: <e-mail da conta de serviço dx03v2-gha-deploy>` e os e-mails de `app_deployer_members` |
| Artifact Registry | repositório `dx03v2` (formato Docker, região `region`, tags imutáveis, varredura de vulnerabilidades desligada — o gate é o trivy do CI do dx03v2); imagens `<region>-docker.pkg.dev/<project_id>/dx03v2/api` e `.../web` com a tag do SHA git completo (40 caracteres) do dx03v2. A conta de serviço dos nós tem `roles/artifactregistry.reader` no repositório |
| Contas de serviço do GitHub (no projeto do lab, criadas pelo bootstrap) | `tx03v2-gha-plan`, `tx03v2-gha-apply`, `dx03v2-gha-deploy` |
| Instância Cloud SQL | `tx03v2-lab-<4 hex aleatórios>` (o nome de uma instância apagada fica bloqueado por até uma semana), PostgreSQL 17, edição `ENTERPRISE`, tier padrão `db-g1-small` |

Regras da Role `dx03v2-deployer` (namespace `dx03v2`), as mesmas dos contratos AWS e Azure v1, com os
CRDs de tráfego da GKE no lugar dos da Azure:

- `apps`: deployments → get, list, watch, create, update, patch, delete; replicasets → get, list, watch
- core: services, configmaps, serviceaccounts → get, list, watch, create, update, patch, delete;
  pods, pods/log, events, endpoints → get, list, watch; secrets → get, list, watch (o ESO escreve
  os segredos; o deployer nunca os escreve)
- `networking.k8s.io`: networkpolicies → CRUD completo (mesmos verbos de deployments)
- `gateway.networking.k8s.io`: gateways, httproutes → CRUD completo
- `networking.gke.io`: healthcheckpolicies, gcpbackendpolicies → CRUD completo
- `autoscaling`: horizontalpodautoscalers → CRUD completo; `policy`: poddisruptionbudgets → CRUD completo
- `external-secrets.io`: externalsecrets → CRUD completo

## Workload Identity Federation do GitHub

Pool `tx03v2-github`, provider OIDC `github` com issuer `https://token.actions.githubusercontent.com`,
mapeamento `google.subject = assertion.sub`, `attribute.repository = assertion.repository`,
`attribute.repository_owner = assertion.repository_owner` e condição
`assertion.repository_owner == '<owner>' && assertion.repository in ['<owner>/tx03v2', '<owner>/dx03v2']`
(dono configurável, `github_owner`, padrão `maringelix`). Cada conta de serviço recebe
`roles/iam.workloadIdentityUser` só para sujeitos exatos
(`principal://iam.googleapis.com/projects/<número>/locations/global/workloadIdentityPools/tx03v2-github/subject/<sujeito>`):

| Conta de serviço | Sujeitos |
|---|---|
| `tx03v2-gha-plan` | `repo:<owner>/tx03v2:pull_request`, `repo:<owner>/tx03v2:ref:refs/heads/main` |
| `tx03v2-gha-apply` | `repo:<owner>/tx03v2:environment:lab` |
| `dx03v2-gha-deploy` | `repo:<owner>/dx03v2:environment:lab` |

Papéis de `dx03v2-gha-deploy` (concedidos pelo root do lab): `roles/artifactregistry.writer` no
repositório `dx03v2`; `roles/container.clusterViewer` no projeto (obter credenciais e passar pelo
endpoint DNS; o IAM da GKE não tem escopo de cluster); `roles/parametermanager.parameterAccessor` no
projeto (ler o parâmetro de contrato; o Parameter Manager não tem IAM por parâmetro no provider
8.6.0, e o projeto do lab só tem esse parâmetro). Nada no Secret Manager. Acesso Kubernetes só pela
RoleBinding acima.

Os `app_deployer_members` (pessoas que fazem o deploy do dx03v2 a partir de um laptop, no formato
`user:<e-mail>`, ou contas de serviço, `serviceAccount:<e-mail>`) recebem os mesmos três papéis, nos
mesmos escopos, e entram como sujeitos da RoleBinding pelo e-mail. Membros `group:` são recusados
pela validação do Terraform e pelo `platform/install.sh`: o Google Groups for RBAC não está
configurado no cluster, então um grupo nunca casaria com um sujeito `kind: User`. Também não recebem
nada no Secret Manager.

## Parâmetro de contrato: Parameter Manager `tx03v2-lab-contract`

Parâmetro global com formato `JSON`, uma versão viva lida pelo alias `latest`. O ID da versão é
`c-<16 primeiros hex do sha256 do JSON>`, então qualquer mudança cria uma versão nova antes de apagar
a antiga (`create_before_destroy`). O dx03v2 recebe o projeto pela variável `GCP_PROJECT_ID` do GitHub
e lê com `gcloud parametermanager parameters versions render latest --parameter=tx03v2-lab-contract
--location=global`. Nenhum valor é segredo. O JSON tem exatamente estas 15 chaves (valores string):

| Chave | Valor |
|---|---|
| `project-id` | ID do projeto do lab |
| `region` | região |
| `cluster-name` | `tx03v2-lab` |
| `network-name` | `tx03v2-lab` |
| `nodes-subnet-cidr` | CIDR da subnet dos nós |
| `db/endpoint-ip` | IP interno do endpoint Private Service Connect do Cloud SQL (a saída da API para o banco vai só para ele) |
| `lb-source-ranges` | `35.191.0.0/16,130.211.0.0/22` (fixo: origens do tráfego e das verificações de saúde do Application Load Balancer externo global para NEGs zonais) |
| `artifact-registry/repository` | `<region>-docker.pkg.dev/<project_id>/dx03v2` |
| `db/secret-name` | `tx03v2-lab-db-app` |
| `app/admin-token-secret-name` | `tx03v2-lab-app-admin-token` |
| `eso/cluster-secret-store` | `gcp-secret-manager` |
| `gateway/address-name` | `tx03v2-lab-gateway` (endereço IPv4 externo global reservado) |
| `gateway/address` | o IPv4 desse endereço |
| `waf/security-policy` | `tx03v2-lab-waf`, ou o literal `none` quando o tx03v2 roda com `enable_waf = false` |
| `deploy/service-account` | e-mail de `dx03v2-gha-deploy` |

## Secret Manager

Replicação gerenciada pelo usuário na região do lab; os valores são gravados com argumentos
write-only (`secret_data_wo`) e nunca entram no state nem no plan.

- `tx03v2-lab-db-app`: JSON com valores string `username`, `password`, `host`, `port`, `dbname`.
  `host` é o nome DNS da instância para Private Service Connect (`dns_name`, sem o ponto final:
  `<uid>.<rótulo do projeto>.<region>.sql.goog`), o nome que o `verify-full` confere; `port` `5432`;
  `dbname` `app`; `username` `app`.
- `tx03v2-lab-app-admin-token`: string pura, 48 caracteres alfanuméricos aleatórios.
- O ServiceAccount `external-secrets/external-secrets` do ESO, como principal do Workload Identity
  Federation for GKE
  (`principal://iam.googleapis.com/projects/<número>/locations/global/workloadIdentityPools/<project_id>.svc.id.goog/subject/ns/external-secrets/sa/external-secrets`),
  tem `roles/secretmanager.secretAccessor` só nesses dois segredos.

## Cloud SQL

- PostgreSQL 17, edição `ENTERPRISE` (PostgreSQL 16+ cria Enterprise Plus por padrão, e os tiers de
  núcleo compartilhado só existem na Enterprise), tier padrão `db-g1-small` (50 conexões por padrão:
  até 4 réplicas da API × `DB_POOL_MAX` 10 + a migração; o `db-f1-micro` tem 25 e é recusado pela
  validação), zonal, disco SSD de 10 GB sem crescimento automático, backups automáticos ligados com
  1 backup retido e `retain_backups_on_delete = false`, proteção contra exclusão desligada (lab).
- Sem IP público e sem acesso a serviços privados (peering): só Private Service Connect, com
  `allowed_consumer_projects = [project_id]`. Endpoint: endereço interno `tx03v2-lab-db` na subnet dos
  nós + forwarding rule `tx03v2-lab-db` para o `psc_service_attachment_link` da instância. Zona DNS
  privada `tx03v2-lab-sql` (`<region>.sql.goog.`, visível só na VPC do lab) com o registro A
  `<dns_name>` → IP do endpoint.
- TLS: `ssl_mode = ENCRYPTED_ONLY`, `server_ca_mode = GOOGLE_MANAGED_CAS_CA` (CA compartilhada da
  região; o certificado do servidor traz o nome DNS da instância no SAN) e rotação automática do
  certificado do servidor na manutenção.
- Banco `app` e usuário `app` com senha write-only (`password_wo`); os dois com
  `deletion_policy = "ABANDON"` (somem com a instância; apagar antes falha no PostgreSQL).

## Cloud Armor

Política `tx03v2-lab-waf` (tier Standard, escopo global), criada quando `enable_waf = true` (padrão):
regras pré-configuradas `sqli-v33-stable` e `xss-v33-stable` com sensibilidade 1 em modo `deny(403)`,
regra padrão `allow`, `request_body_inspection_size = "64KB"` e análise JSON padrão. Corpos maiores que
64 KB não são bloqueados por tamanho (só os primeiros 64 KB são inspecionados), então o corpo de 70 KB
do smoke chega à API, que responde 413 ela mesma. Nenhuma regra pode bloquear o smoke test; um limite
de taxa, se for adicionado, precisa ser >= 300 requisições por minuto por cliente.

## Camada de plataforma (instalada pelo `platform/install.sh` do tx03v2, nunca pelo Terraform)

- External Secrets Operator 2.12.0 no namespace `external-secrets`, ServiceAccount `external-secrets`
  (sem anotação: o próprio ServiceAccount é o principal do IAM), requests de CPU e memória definidos
  para o Autopilot; ClusterSecretStore `gcp-secret-manager` (provider `gcpsm`, `projectID` do
  contrato, sem bloco `auth`: usa a identidade do controller), utilizável só a partir do namespace
  `dx03v2`.
- Namespace `dx03v2`, Role e RoleBinding acima. O controlador de Gateway da GKE é gerenciado pelo
  Google (GatewayClass `gke-l7-global-external-managed`); nada a instalar.
- `platform/uninstall.sh` apaga o namespace `dx03v2` antes de qualquer destroy e espera o finalizer do
  Gateway e o sumiço dos NEGs `k8s1-*` do app: o load balancer criado pelo controlador fica fora do
  state do Terraform e vazaria se o cluster sumisse antes.

## Runtime do app (dx03v2)

- Secret `db-credentials`: chaves `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` (Google
  Cloud: ExternalSecret de `tx03v2-lab-db-app`; local/kind/compose: gerado em tempo de execução).
- Secret `app-secrets`: chave `ADMIN_TOKEN` (Google Cloud: ExternalSecret de `tx03v2-lab-app-admin-token`).
- TLS do banco: `DB_SSL_MODE=verify-full`, `DB_SSL_CA_FILE=/etc/cloudsql-ca/ca.pem` a partir do
  ConfigMap `cloudsql-ca`, criado pelo deploy com o bundle público da região
  (`https://storage.googleapis.com/cloudsql-ca-bundles/<region>.pem`). O deploy **recusa** um bundle que
  não tenha exatamente uma raiz autoassinada com o SHA-256 abaixo ou que tenha um certificado não
  emitido por ela. Não fixe o SHA-256 do arquivo: as CAs subordinadas da região mudam com a rotação.

  | Raiz | SHA-256 (contrato) | SHA-1 | Validade |
  |---|---|---|---|
  | `CN=Google Cloud SQL Root Server CA 0b29df` (ECDSA P-384) | `C7B0FCD282B346F1FCC45EE8A79ECF6EF6FAEF2D669BEEC664293B93D83E59BE` | `9E0DDEC1969957360315A0B849CD609E6FC0905C` | 2049-06-27 |

  Local: `DB_SSL_MODE=disable`.
- `TRUST_PROXY_HOPS=2`: o Application Load Balancer externo global acrescenta
  `<ip do cliente>,<ip do load balancer>` ao `X-Forwarded-For` e a conexão chega de um GFE.
- Services: `api` (porta 3000 http, 9464 métricas), `web` (porta 8080).
- Tráfego (só Google Cloud): Gateway `dx03v2` (classe `gke-l7-global-external-managed`,
  `spec.addresses` com `type: NamedAddress` e o valor `gateway/address-name`), listener HTTP na porta 80
  (HTTPS `planejado`); HTTPRoute `dx03v2`: `/api` → `api:3000`, `/` → `web:8080`; HealthCheckPolicies
  `web` (`/healthz`, porta 8080) e `api` (`/readyz`, porta 3000); GCPBackendPolicies `api` e `web` com
  `securityPolicy` = `waf/security-policy` (omitidas quando é `none`, e as antigas são apagadas).
- NetworkPolicies no Google Cloud: entrada em web:8080 e api:3000 só a partir de `lb-source-ranges`;
  saída da api para `db/endpoint-ip`/32:5432; DNS (base) e a saída para o cache DNS do nó
  `169.254.20.10/32:53` (NodeLocal DNSCache do Autopilot).

## Lab local (contrato local, versão 1)

O lab local (`docs/LAB_LOCAL.md`) é um contrato à parte, com versão própria (chave `version`), para o
deploy local do dx03v2 (`planejado` lá). Ele espelha o contrato da nuvem com nomes do lab local; não
muda nada acima. As chaves são as mesmas do lab local do `tx01v2` (o app consome os dois do mesmo
jeito); só a coluna da nuvem muda. Publicado por `platform/local/install.sh` no ConfigMap
`lab-system/lab-contract`:

| Chave | Valor | Equivale na nuvem |
|---|---|---|
| `version` | `1` | versão deste arquivo |
| `cluster-name` | `tx03v2-local` | `cluster-name` |
| `network-cidr` | `10.252.0.0/24` (ou `subnet_cidr`) | `nodes-subnet-cidr` |
| `registry` | `registry.tx03v2.local` (nome das imagens no cluster) | `artifact-registry/repository` (prefixo) |
| `registry-push` | `localhost:5003` (push desta máquina) | — |
| `db.endpoint-ip`, `db.hostname`, `db.port` | `10.252.0.11`, `db.tx03v2.local`, `5432` | `db/endpoint-ip` (endpoint Private Service Connect) e o `host` de `tx03v2-lab-db-app` (nome DNS do PSC) |
| `db.secret-name` | `tx03v2-lab-db-app` (chaves `host`, `port`, `dbname`, `username`, `password`) | `db/secret-name` |
| `db.ca-configmap` | `lab-system/lab-ca` (chave `ca.crt`) | ConfigMap `cloudsql-ca` (bundle da região, aceito só com a raiz do contrato; criado pelo deploy) |
| `app.admin-token-secret-name` | `tx03v2-lab-app-admin-token` (chave `token`; no Secret Manager é uma string pura) | `app/admin-token-secret-name` |
| `eso.cluster-secret-store` | `local-secrets` (só o namespace `dx03v2`) | `eso/cluster-secret-store` (`gcp-secret-manager`) |
| `gateway.class` | `istio` (Gateway API) | GatewayClass `gke-l7-global-external-managed` (com `gateway/address-name`) |
| `tls.cluster-issuer` | `lab-ca` (cert-manager) | — (HTTPS no Gateway `planejado`) |
| `gitops.push-url`, `gitops.read-url` | `ssh://10.252.0.13:23231/dx03v2-gitops`, `http://10.252.0.13:23232/dx03v2-gitops.git` | — |
| `gitops.push-key-secret` | `lab-secrets/gitops-push-key` (chave SSH do push, `kubernetes.io/ssh-auth`) | conta de serviço `dx03v2-gha-deploy` |
| `argocd.project` | `dx03v2` (AppProject: só o repositório GitOps, só o namespace `dx03v2`, só os kinds do deploy, nada de Secret ou recurso de cluster) | Role `dx03v2-deployer` |
| `monitoring.prometheus-service-account` | `monitoring/kube-prometheus-stack-prometheus` (identidade do Prometheus no mesh) | — |

Os Secrets `tx03v2-lab-db-app` e `tx03v2-lab-app-admin-token` ficam no namespace `lab-secrets` (o
gêmeo local do Secret Manager) com os mesmos nomes dos segredos do Secret Manager, que já são válidos
no Kubernetes. Regras do namespace `dx03v2` no lab local: Pod Security `restricted`, mesh ambient
(`istio.io/dataplane-mode: ambient`), constraints do Gatekeeper em `deny` (`policy.lab/enforce:
"true"`; imagens só de `registry.tx03v2.local/`), métricas do app coletadas pelo Prometheus do
namespace `monitoring`. O deploy local escreve no repositório GitOps; quem aplica no cluster é o Argo
CD. Diferenças de borda: o Gateway local mantém um `X-Request-Id` externo (o que o smoke do dx03v2
espera no kind); no Google Cloud a documentação do load balancer não diz o que ele faz com esse
cabeçalho (o `SMOKE_EDGE=gke` confere só a propriedade de segurança). O banco do lab local aceita só
TLS (CA do lab em `db.ca-configmap`); o `DB_SSL_MODE=disable` acima vale para o compose e o kind do
próprio dx03v2.

## Mudando o contrato

1. Abra PRs nos dois repositórios, com links cruzados, e incremente a versão no título dos dois
   arquivos `docs/CONTRATO.md`.
2. Atualize os testes e checks que cobrem o item (tabela "Como o contrato é verificado aqui"); uma
   chave nova do parâmetro muda `terraform/envs/lab/contract.tf`, `CONTRACT_KEYS` em
   `scripts/harness.sh` e a tabela acima, juntos.
3. Faça o merge do lado que publica (tx03v2) antes do lado que consome (dx03v2), salvo remoções (ao
   contrário).
