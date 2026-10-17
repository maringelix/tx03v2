# Contrato tx03v2 <-> dx03v2 — versão 5 (2026-10-17)

Versão 5 (R9): `db_profile=dr` publica um segundo parâmetro
`tx03v2-lab-dr-contract` com as mesmas 18 chaves, mas com região, cluster, VPC, PSC, registry,
segredos e endereço de Gateway secundários. O app escolhe explicitamente o parâmetro de DR
somente após fencing da região primária e promoção manual da réplica PostgreSQL. O parâmetro
primário permanece `tx03v2-lab-contract` e conserva as chaves/valores da v4 no perfil `core`.
O perfil `ha` liga HA/PITR no banco sem mudar o contrato da aplicação. Veja
[CONTINUIDADE.md](CONTINUIDADE.md) para o runbook e a distinção entre provas locais e cloud.

`LAB_TARGET=secondary` seleciona apenas o runtime `tx03v2-lab-dr` e sua branch
`gitops/gcp-dr`; o primário usa `gitops/gcp`. O secundário pode instalar `full` com
mesh próprio e o mapa TLS/WAF globais do projeto. A BSL `primary-recovery` lê o
backup multirregião com identidade `velero-dr`; não confunda esse acesso com o
bucket próprio de novas cópias. `LAB_ACTIVE_REGION` controla o registro A somente
após o aceite de uma recuperação autorizada; não promove o banco nem faz fencing.

Versão 4 (R8): domínio e HTTPS opcionais (zona Cloud DNS pública, certificado gerenciado do Certificate
Manager e Certificate Map para o Gateway), Cloud Service Mesh gerenciado no Autopilot (sidecars só no
namespace do app), admissão Kyverno que exige a atestação de promoção assinada, leitura do Artifact
Registry pelo Trivy Operator e pelo Kyverno, observabilidade persistente, WAF com sete categorias CRS e
limite por IP. O parâmetro de contrato passa a ter 18 chaves (três novas). Versão 3: o perfil `full` registra no Argo CD a Application `dx03v2`, que acompanha a branch
`gitops/gcp`; a identidade de deploy pode pedir refresh somente dessa Application. A versão 2
(2026-10-14) adicionou o OpenTelemetry Collector da camada de plataforma (namespace `observability`,
traces para o Cloud Trace). A versão 1 (2026-10-11) não tinha traces.

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
| Papéis de `dx03v2-gha-deploy`, dos `app_deployer_members`, do ESO, do OpenTelemetry Collector (`roles/cloudtrace.agent`), da conta de serviço dos nós e leitura do repositório `dx03v2` pelo Trivy Operator e pelo Kyverno (principais do Workload Identity Federation, sem chave) | `terraform/envs/lab/tests/roles.tftest.hcl` | `verificado localmente` |
| Collector no namespace `observability`, exporter `googlecloud`, mesmo digest do lab local, chart com SHA256 conferido | checks `contract-platform` e `helm-template` | `verificado localmente` |
| As 18 chaves do parâmetro de contrato (nomes, valores fixos, origem de cada valor) | `terraform/envs/lab/tests/lab.tftest.hcl`; o check `contract-parameter` confere que `contract.tf`, a lista do harness e a tabela deste arquivo são iguais | `verificado localmente` |
| Secret Manager (segredos write-only), Cloud SQL (PSC, TLS, CA compartilhada), Artifact Registry | `terraform/envs/lab/tests/data_stores.tftest.hcl` | `verificado localmente` |
| GKE Autopilot (canal, nós privados, endpoint DNS, Gateway API), rede, NAT, endpoint PSC e zona DNS | `terraform/envs/lab/tests/gke.tftest.hcl`, `network.tftest.hcl` | `verificado localmente` |
| Cloud Armor (sete categorias CRS, limite de 600 requisições por minuto por IP, Adaptive Protection Standard, inspeção de 64 KB) e `none` sem WAF | `terraform/envs/lab/tests/waf.tftest.hcl` | `verificado localmente` |
| Zona Cloud DNS, autorização DNS, certificado gerenciado, Certificate Map e Cloud Service Mesh gerenciado (membership da frota, feature `servicemesh`); `core` não cria nada disso | `terraform/envs/lab/tests/edge_mesh.tftest.hcl`, `validations.tftest.hcl` | `verificado localmente` |
| Range privado do control plane e regra de firewall que deixa o control plane chamar os webhooks de admissão (8443 Gatekeeper, 9443 Kyverno e Chaos Mesh) | `terraform/envs/lab/tests/gke.tftest.hcl`, `validations.tftest.hcl` | `verificado localmente` |
| Política de admissão Kyverno (digest + atestação de promoção do `deploy-gcp.yml` do fork), políticas de mesh (mTLS STRICT, exceções por workload e porta, autorização por identidade) e a ordem de instalação do perfil `full` | checks `image-admission-policy`, `full-install-order`, `contract-platform-full` | `verificado localmente` |
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
| Cluster GKE | `tx03v2-lab`, **Autopilot**, regional (`region`), canal `REGULAR` (Kubernetes 1.36 no padrão do canal em 2026-10-08), nós privados com o control plane num /28 fixo (`control_plane_cidr`, padrão `172.31.255.240/28`), endpoint IP público desligado, endpoint DNS com tráfego externo liberado e autorização só pelo IAM, Gateway API (canal standard), Dataplane V2 (aplica NetworkPolicy), conta de serviço dos nós `tx03v2-lab-nodes` |
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
- `networking.istio.io`: destinationrules, virtualservices; `security.istio.io`: authorizationpolicies → CRUD completo,
  só no namespace `dx03v2` (tráfego e autorização da malha do perfil `full`; sem os CRDs do Istio a regra é inerte)
- `gateway.networking.k8s.io`: gateways, httproutes → CRUD completo
- `networking.gke.io`: healthcheckpolicies, gcpbackendpolicies → CRUD completo
- `autoscaling`: horizontalpodautoscalers → CRUD completo; `policy`: poddisruptionbudgets → CRUD completo
- `external-secrets.io`: externalsecrets → CRUD completo

## Workload Identity Federation do GitHub

Pool `tx03v2-github`, provider OIDC `github` com issuer `https://token.actions.githubusercontent.com`,
mapeamento `google.subject = assertion.sub`, `attribute.repository = assertion.repository`,
`attribute.repository_owner = assertion.repository_owner` e condição
`assertion.repository_owner_id == '<id do dono>' && assertion.repository_id in ['<id do tx03v2>', '<id do dx03v2>']`
(`github_owner`, sem padrão, e os três IDs numéricos `github_owner_id`, `tx03v2_repository_id` e
`dx03v2_repository_id`: um nome de conta apagado e registrado de novo tem outros IDs e não herda o lab).
Cada conta de serviço recebe
`roles/iam.workloadIdentityUser` só para sujeitos exatos
(`principal://iam.googleapis.com/projects/<número>/locations/global/workloadIdentityPools/tx03v2-github/subject/<sujeito>`):

| Conta de serviço | Sujeitos |
|---|---|
| `tx03v2-gha-plan` | `repo:<owner>@<owner id>/tx03v2@<repo id>:pull_request`, `repo:<owner>@<owner id>/tx03v2@<repo id>:ref:refs/heads/main` |
| `tx03v2-gha-apply` | `repo:<owner>@<owner id>/tx03v2@<repo id>:environment:lab` |
| `dx03v2-gha-deploy` | `repo:<owner>@<owner id>/dx03v2@<repo id>:environment:lab` |

O sujeito é o **imutável** do GitHub (repositórios criados depois de 2026-07-15 ou que aderiram):
leva o ID numérico do dono e o do repositório, então o formato antigo, só com os nomes, não casa. O
environment `lab` só implanta a partir de `main` (`scripts/repo-guardrails.sh`).

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
--location=global`. Nenhum valor é segredo. O JSON tem exatamente estas 18 chaves (valores string):

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
| `dns/hostname` | hostname público do app (subdomínio da zona delegada) ou `disabled` quando `app_domain_name` está vazio |
| `dns/certificate-map` | `tx03v2-lab-app` (Certificate Map do Certificate Manager que o Gateway usa por anotação) ou `disabled` |
| `mesh/management` | `managed` quando `enable_managed_mesh = true` (Cloud Service Mesh gerenciado ativo no cluster), senão `disabled` |

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
sete categorias pré-configuradas do OWASP CRS 3.3 (`sqli`, `xss`, `lfi`, `rfi`, `rce`,
`methodenforcement` e `scannerdetection`, versão `v33-stable`) com sensibilidade 1 em modo
`deny(403)`, um limite de 600 requisições por minuto por IP de cliente (`throttle`, responde 429 acima
disso; o contrato exige no mínimo 300 por minuto), regra padrão `allow`,
`request_body_inspection_size = "64KB"` e análise JSON padrão. O Adaptive Protection está ligado na
camada 7: no tier Standard ele gera só alertas de detecção, não assinaturas nem mitigação automática
(isso é Enterprise). Corpos maiores que 64 KB não são bloqueados por tamanho (só os primeiros 64 KB são
inspecionados), então o corpo de 70 KB do smoke chega à API, que responde 413 ela mesma. Nenhuma regra
pode bloquear o smoke test.

## Camada de plataforma (instalada pelo `platform/install.sh` do tx03v2, nunca pelo Terraform)

- External Secrets Operator 2.12.0 no namespace `external-secrets`, ServiceAccount `external-secrets`
  (sem anotação: o próprio ServiceAccount é o principal do IAM), requests de CPU e memória definidos
  para o Autopilot; ClusterSecretStore `gcp-secret-manager` (provider `gcpsm`, `projectID` do
  contrato, sem bloco `auth`: usa a identidade do controller), utilizável só a partir do namespace
  `dx03v2`.
- Namespace `dx03v2`, Role e RoleBinding acima. O controlador de Gateway da GKE é gerenciado pelo
  Google (GatewayClass `gke-l7-global-external-managed`); nada a instalar.
- Traces (versão 2): OpenTelemetry Collector 0.162.0 (chart 0.176.0, SHA256 conferido) no namespace
  `observability` (mesmos labels de Pod Security), ServiceAccount `opentelemetry-collector` sem
  anotação (o principal
  `principal://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/<PROJECT_ID>.svc.id.goog/subject/ns/observability/sa/opentelemetry-collector`
  tem só `roles/cloudtrace.agent` no projeto; o Cloud Trace não tem IAM por recurso), requests para o
  Autopilot. O app manda OTLP/HTTP para `http://opentelemetry-collector.observability.svc:4318`; o
  Collector grava os spans no Cloud Trace do projeto. O app não recebe nenhum papel do IAM para isso.
- O perfil `full` não altera os nomes do serviço (as três chaves novas da versão 4 só dizem se o domínio e a malha existem): `platform/install.sh
  --profile full --github-owner <dono>` acrescenta os charts fixados, Gatekeeper, Trivy Operator,
  Velero e Argo CD. O namespace `dx03v2` recebe `policy.lab/enforce: "true"` e continua sujeito às
  constraints de imagem, recursos, probes, labels e portas.
- GitOps no perfil `full`: a Application `platform` (AppProject `platform`, namespace `argocd`) lê
  `platform/gitops` do tx e cria a Application `dx03v2` a partir de `deploy/k8s/overlays/gcp` na
  revisão `gitops/gcp`. O instalador injeta as URLs do fork; elas não são gravadas nos manifests
  públicos. A Role `dx03v2-gitops-sync`/RoleBinding usa os mesmos sujeitos `kind: User` do contrato
  (`dx03v2-gha-deploy` e `app_deployer_members`) e só permite `get`, `watch` e `patch` na
  Application chamada `dx03v2`, para pedir refresh; não permite alterar outras Applications.
- O workflow de deploy atualiza na Application viva o overlay, as imagens e os parâmetros de nuvem.
  A Application `platform` ignora apenas `spec.source.path`, `spec.source.kustomize.images` e
  `spec.source.kustomize.patches` da Application `dx03v2`, para o self-heal do pai preservar esses
  valores. A branch pública `gitops/gcp` recebe a revisão e parâmetros de exemplo; nomes de recursos,
  CIDRs e endereços reais permanecem no cluster.
- Velero no perfil `full`: ServiceAccount `velero` no namespace `velero`, sem chave nem Secret. O
  bucket regional chama-se `<LAB_NAME>-velero-<PROJECT_ID>` e não adiciona uma chave ao contrato. O
  principal WIF `principal://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/<PROJECT_ID>.svc.id.goog/subject/ns/velero/sa/velero`
  recebe `roles/storage.objectAdmin` só no bucket. O backup inclui objetos Kubernetes, não Cloud SQL
  nem snapshots de volumes; o ciclo de vida dos objetos é de 35 dias.
- Perfil `full` (R8), malha: o Cloud Service Mesh gerenciado (`enable_managed_mesh = true`, membership
  da frota e feature `servicemesh` com `MANAGEMENT_AUTOMATIC`, `mesh/management = managed`) é o único
  caminho de malha no Autopilot: ele não aceita o `istio-cni` e o `ztunnel` privilegiados do ambient
  (ADR 39). O instalador recusa o perfil `full` sem a malha `ACTIVE` (`gcloud container fleet mesh
  describe`) e sem o certificado `ACTIVE`. Só o namespace `dx03v2` recebe sidecars
  (`istio-injection: enabled` e a anotação `mesh.cloud.google.com/proxy: {"managed":"true"}`);
  `monitoring` e `observability` ficam fora da malha. `platform/manifests/full/app-security.yaml`:
  mTLS `STRICT` no namespace, exceções em texto claro com uma `PeerAuthentication` por workload e
  porta (`web` 8080, `api` 3000 e 9464: o `portLevelMtls` só vale com seletor de workload),
  `AuthorizationPolicy` por identidade (`*/ns/dx03v2/sa/web` → `api:3000`: o domínio de confiança
  do Cloud Service Mesh é `<projeto>.svc.id.goog`, não `cluster.local`) e três origens externas à
  malha, cada uma restrita a uma porta: os dois ranges do load balancer (`lb-source-ranges`), o
  Prometheus em `api:9464` (a NetworkPolicy do dx03v2 só admite o namespace `monitoring`) e a sonda
  sintética do Collector só em `/healthz` e `/readyz`.
- Perfil `full` (R8), domínio e HTTPS: com `dns_zone_name` e `app_domain_name` o Terraform cria a zona
  pública do Cloud DNS, o registro A do hostname (endereço do Gateway), a autorização DNS do
  Certificate Manager (registro CNAME na mesma zona), o certificado gerenciado e o Certificate Map
  `tx03v2-lab-app`. O Gateway `dx03v2` do perfil `full` usa o listener HTTPS 443 com a anotação
  `networking.gke.io/certmap` (nunca um Secret TLS do Kubernetes) e o listener HTTP 80 só redireciona
  (301) para HTTPS. A emissão pública só acontece depois que o dono do fork delega os servidores de nomes
  (saída `dns_name_servers`) no registrador: até lá o certificado fica `PROVISIONING` e o instalador
  recusa o `full`. `core` continua só em HTTP, sem domínio.
- Perfil `full` (R8), admissão: Kyverno 3.8.2 (controller v1.18.2, namespace `kyverno`) com a política
  `ImageValidatingPolicy` `dx03v2-release-signatures`: só sobem no namespace `dx03v2` imagens dos dois
  repositórios do Artifact Registry referenciadas por digest e com a atestação de promoção
  (`https://github.com/maringelix/tx00v2/attestations/promoted-image/v1`) assinada, sem chave (Sigstore),
  pelo workflow `deploy-gcp.yml` da `main` do fork, com emissor `https://token.actions.githubusercontent.com`.
  `failurePolicy: Fail` e `Deny`: se o Kyverno não responde, os pods do app não sobem. O dx03v2
  precisa assinar a mesma imagem que publicou e promoveu. O ServiceAccount
  `kyverno/kyverno-admission-controller` lê o repositório `dx03v2` como principal do Workload Identity
  Federation (`roles/artifactregistry.reader`, sem chave nem segredo de pull).
- Perfil `full` (R8), varredura: o Trivy Operator roda os jobs em `trivy-system` como o ServiceAccount
  `trivy-operator`, principal com `roles/artifactregistry.reader` só no repositório `dx03v2` (token
  federado de curta duração do servidor de metadados do GKE). Relatório ausente não significa imagem limpa.
- Perfil `full` (R8), webhooks: o control plane de um cluster privado só inicia conexões TCP nos nós e
  pods nas portas 443 e 10250. A regra de firewall `tx03v2-lab-control-plane-webhooks` (módulo `gke`)
  libera `control_plane_cidr` para os nós (conta de serviço `tx03v2-lab-nodes`) em `8443` (Gatekeeper)
  e `9443` (Kyverno e Chaos Mesh); sem ela o Gatekeeper não aplica as políticas e o Kyverno bloquearia
  todos os pods do app.
- Perfil `full` (R8), dados da observabilidade: Prometheus (7 dias, 8 GB), Alertmanager (72 h), Grafana,
  Loki (7 dias) e Tempo (72 h) usam PVCs `standard-rwo` (Persistent Disk); `platform/uninstall.sh`
  desinstala os releases e apaga os PVCs antes do `terraform destroy`, porque o disco não faz parte do
  state e continuaria cobrando. A sonda sintética (receiver `httpcheck` do Collector) alimenta o alerta
  `Dx03v2SyntheticProbeFailed`; o ServiceMonitor, as regras de SLO (disponibilidade 99,5 %, queima do
  orçamento de erro, latência p95, reinícios) e o dashboard `dx03v2 API SLO` vêm de
  `platform/manifests/full/app-monitoring.yaml`. Sem webhook do Slack o receiver é o `null`: a
  integração aparece como não configurada no Alertmanager.
- `platform/uninstall.sh` apaga o namespace `dx03v2` antes de qualquer destroy e espera o finalizer do
  Gateway e o sumiço dos NEGs `k8s1-*` do app: o load balancer criado pelo controlador fica fora do
  state do Terraform e vazaria se o cluster sumisse antes. Depois desinstala os releases do perfil
  `full` e apaga os PVCs do `monitoring`.

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
  (perfil `full`: listener HTTPS 443 com a anotação `networking.gke.io/certmap` = `dns/certificate-map` e o HTTP só redireciona para HTTPS; sem domínio, HTTP); HTTPRoute `dx03v2`: `/api` → `api:3000`, `/` → `web:8080`; HealthCheckPolicies
  `web` (`/healthz`, porta 8080) e `api` (`/readyz`, porta 3000); GCPBackendPolicies `api` e `web` com
  `securityPolicy` = `waf/security-policy` (omitidas quando é `none`, e as antigas são apagadas).
- NetworkPolicies no Google Cloud: entrada em web:8080 e api:3000 só a partir de `lb-source-ranges`;
  saída da api para `db/endpoint-ip`/32:5432; DNS (base) e a saída para o cache DNS do nó
  `169.254.20.10/32:53` (NodeLocal DNSCache do Autopilot).
  No perfil `full` o dx03v2 acrescenta a entrada do Prometheus (namespace `monitoring`) em `api:9464`, a
  entrada da sonda do Collector (namespace `observability`) em `/healthz` e `/readyz` e a saída dos sidecars
  para o plano de controle gerenciado do Cloud Service Mesh; as portas exatas desta última dependem do
  serviço gerenciado e só se confirmam na primeira rodada em nuvem (`não executado em nuvem (v2)`).

## Lab local (contrato local, versão 2)

O lab local (`docs/LAB_LOCAL.md`) é um contrato à parte, com versão própria (chave `version`), para o
deploy local do dx03v2 (`scripts/deploy-local.sh` lá, provado pelo job `e2e-platform`). Ele espelha o
contrato da nuvem com nomes do lab local; não
muda nada acima. As chaves são as mesmas do lab local do `tx01v2` (o app consome os dois do mesmo
jeito); só a coluna da nuvem muda. Publicado por `platform/local/install.sh` no ConfigMap
`lab-system/lab-contract`:

| Chave | Valor | Equivale na nuvem |
|---|---|---|
| `version` | `2` (2026-10-14: `tracing.otlp-endpoint`; a versão 1 não tinha traces) | versão deste arquivo |
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
| `tracing.otlp-endpoint` | `http://opentelemetry-collector.monitoring.svc:4318` (OTLP/HTTP do OpenTelemetry Collector; o app manda os spans por ele, pelo mesh, e os Gateways mandam os deles em OTLP/gRPC na porta 4317) | `http://opentelemetry-collector.observability.svc:4318` |

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
