# Guardrails do tx03v2

Um guardrail é uma regra mais o mecanismo que a faz valer — automático sempre que possível. Este
documento lista as regras do repositório, onde cada uma é aplicada e o que elas não garantem.
Tipos: `bloqueante` (falha o harness/CI ou o plan), `alerta` (notifica), `processo` (disciplina
humana/agente). Os testes citados ficam em `terraform/*/tests/` e rodam com `make test`.

## Regras

| ID | Regra | Por quê | Onde é aplicada | Tipo |
|---|---|---|---|---|
| SEC-01 | Nenhum segredo no repositório | repositório público; histórico é para sempre | `gitleaks` (harness, pre-commit) | bloqueante |
| SEC-02 | Sem identificadores reais: projeto `tx03v2-lab-example` (e dois placeholders de teste), número `000000000000`, conta de faturamento `000000-000000-000000`, e-mails `example.com` ou contas de serviço do projeto placeholder, IPs privados, RFC 5737 ou as duas faixas do load balancer (`35.191.0.0/16`, `130.211.0.0/22`), GUIDs de um dígito repetido | evita expor projetos, contas de faturamento e pessoas | check `policy-identifiers` (todo arquivo visível ao git, também os caminhos `projects/<id>/`) | bloqueante |
| SEC-03 | Segredos gerados por `ephemeral "random_password"` e gravados só com argumentos write-only (`password_wo`, `secret_data_wo`); nenhum `random_password`/`random_string` como recurso (exceto no lab local, LOC-01), nenhum `password` ou `secret_data` em texto | o valor nunca entra no plan nem no state | `policy-terraform`; testes `secrets_are_regional_and_write_only`, `cloudsql_postgres_17_enterprise_psc_only` | bloqueante |
| SEC-04 | GitHub → Google Cloud só por Workload Identity Federation: pool `tx03v2-github`, condição do provider = dono + os dois repositórios, um `roles/iam.workloadIdentityUser` por sujeito exato (sem `principalSet`), nenhuma chave de conta de serviço | sem segredos; nenhum outro repositório, branch ou environment obtém as contas | `identities.tftest.hcl` (`pool_and_provider_follow_the_contract`, `one_grant_per_exact_subject`); `policy-terraform` (proíbe `google_service_account_key` e `principalSet://`) | bloqueante |
| SEC-05 | `id-token: write` só em jobs de nuvem com `environment: lab` (o plan, atrás da guarda); nunca no `ci.yml`; sem `credentials_json`, `secrets.GCP*`/`secrets.GOOGLE*` ou arquivos de credencial nos workflows; `google-github-actions/auth` só com `workload_identity_provider` e `service_account` de `vars.*` | limita quem obtém credenciais | `policy-workflows` | bloqueante |
| SEC-06 | Plano de controle: nós privados, endpoint IP público desligado, redes autorizadas sem CIDR e sem IPs públicos do Google Cloud, endpoint DNS só com IAM (tokens e certificados do Kubernetes pelo DNS desligados); nenhum `0.0.0.0/0` no Terraform da nuvem (bootstrap, envs/lab, módulos; o `pg_hba.conf` do lab local vale só dentro da rede Docker privada) | o cluster não tem porta aberta por IP; quem chega precisa do IAM | `policy-terraform`; teste `autopilot_private_dns_endpoint_gateway` | bloqueante |
| SEC-07 | Nada acima do projeto (sem recursos de organização ou pasta); `roles/owner` nunca concedido; IAM autoritativo (`*_iam_binding`, `*_iam_policy`) proibido | o lab não alcança o resto da organização nem apaga concessões de outros | `policy-terraform`; `nothing_for_the_deployer_and_no_owner` | bloqueante |
| SEC-08 | O apply só concede no projeto os 3 papéis de `modules/project-roles` (condição `modifiedGrantsByRole`), e o root do lab concede exatamente esses (precondition no `roles.tf`) | o apply não consegue se promover | testes `apply_identity_grants_only_the_lab_project_roles`, `project_grants_follow_the_contract`; precondition de `google_project_iam_member.lab` | bloqueante |
| SEC-09 | Plan só leitura: Viewer, Security Reviewer e Parameter Viewer no projeto, `storage.objectViewer` no bucket; nenhum papel de escrita, personificação ou acesso a segredo | o plan roda em PRs | `plan_identity_is_read_only` | bloqueante |
| SEC-10 | Cloud SQL só por Private Service Connect (sem IP público, sem private services access), `allowed_consumer_projects` = o projeto, só conexões criptografadas, CA compartilhada, rotação automática do certificado | o banco não tem porta na Internet e o app consegue verificar o nome | `policy-terraform` (proíbe `ipv4_enabled = true`); `cloudsql_postgres_17_enterprise_psc_only` | bloqueante |
| SEC-11 | Deployers não recebem nada no Secret Manager; o principal do ESO só tem `secretAccessor` nos dois segredos do lab | menor privilégio sobre segredos | `repository_and_secret_grants`, `project_grants_follow_the_contract` | bloqueante |
| SEC-12 | Plan só para PRs do próprio repositório (guarda `head.repo.full_name == github.repository`) e só com `GCP_PLAN_SERVICE_ACCOUNT` configurada | forks nunca recebem credenciais | `terraform-plan.yml`; `policy-workflows` | bloqueante |
| SEC-13 | Nada público: sem `allUsers`/`allAuthenticatedUsers`; bucket do state com acesso uniforme e prevenção de acesso público | nenhum dado do lab fica aberto | `policy-terraform`; `state_bucket_is_private_versioned_and_protected` | bloqueante |
| SEC-14 | Os nós rodam como `tx03v2-lab-nodes` (`container.defaultNodeServiceAccount` e leitura no repositório), nunca como a conta padrão do Compute Engine | a conta padrão tem Editor | `cluster_follows_the_contract`, `project_grants_follow_the_contract` | bloqueante |
| SEC-15 | O bootstrap não tem dono padrão: `github_owner` é obrigatório e o placeholder `your-github-user` é recusado; `budget_alert_emails` recusa o placeholder `you@example.com` | um fork que esquecesse de trocar o dono confiaria nos repositórios de outra pessoa, e sem um e-mail lido o alerta de custo não chega (`FORK.md`) | validações das variáveis; `placeholder_owner_is_refused`, `placeholder_alert_email_is_refused` | bloqueante |
| SUP-01 | Ferramentas do harness com versão e SHA256 fixados; divergência é erro fatal | cadeia de suprimentos | `scripts/install-tools.sh`, `tools/checksums.txt`; `tool-versions` | bloqueante |
| SUP-02 | Toda action fixada por SHA de 40 caracteres com comentário `# vX.Y.Z`; um SHA por action | tags podem ser movidas | `policy-workflows`, `version-consistency` | bloqueante |
| SUP-03 | Providers com `.terraform.lock.hcl` gerado para 4 plataformas (o check exige pelo menos 4 hashes `h1:` por provider); roots iniciam com `-lockfile=readonly` | builds reprodutíveis | `terraform-lockfiles`, `terraform-validate:*` | bloqueante |
| SUP-04 | Chart do ESO baixado por tag e digest do manifest OCI e conferido por SHA256; as três imagens do ESO e a do devcontainer por digest | nada muda sem um diff | `helm-template`, `contract-platform`, `version-consistency`, `repo-structure`; `platform/install.sh` | bloqueante |
| SUP-05 | trivy só via `scripts/install-tools.sh` (nunca `trivy-action`/`setup-trivy`, GHSA-69fq-xp46-6x23) | incidente de cadeia de suprimentos de março de 2026 | `policy-workflows` | bloqueante |
| SUP-06 | Versões coerentes entre arquivos (ruleset do tflint, hook do gitleaks, digests do ESO, `required_version`, restrição do google em todos os `versions.tf`, a mesma versão do google travada nos dois roots, minor do Kubernetes nos schemas e no `docs/CONTRATO.md`, `GCLOUD_VERSION` = `version:` do `setup-gcloud`) | uma atualização não fica pela metade | `version-consistency` | bloqueante |
| SUP-07 | Dependabot mensal, minor+patch agrupados, majors separados; majors do google e o hook do gitleaks ignorados de propósito (ver os comentários no arquivo) | nada apodrece em silêncio | `.github/dependabot.yml` | alerta |
| IAC-01 | Terraform não fala com o Kubernetes: sem providers `kubernetes` ou `helm`; só o provider GA `google` (sem `google-beta`) | separação de camadas; atributos beta mudam sem aviso | `policy-terraform` | bloqueante |
| IAC-02 | Nada de credencial no código: o provider `google` sem `credentials`, `access_token` ou personificação; backend `gcs {}` sem argumentos (bucket e prefixo vêm do `backend.hcl`) | credenciais vêm do ADC ou do `google-github-actions/auth` | `policy-terraform` | bloqueante |
| IAC-03 | Labels do contrato: o provider de cada root define `default_labels` com exatamente os quatro labels e `add_terraform_attribution_label = false`; módulos não configuram provider; `local.project = "tx03v2"` e `local.environment = "lab"` | todo recurso que aceita labels fica identificado | `policy-labels` | bloqueante |
| IAC-04 | `timestamp()`/`plantimestamp()` só em recurso com `lifecycle.ignore_changes` do atributo | diff perpétuo | `policy-terraform` | bloqueante |
| IAC-05 | Todo input não booleano validado: ID do projeto, região, dono do GitHub, e-mail do deploy (no projeto certo), membros (`user:`/`serviceAccount:`, minúsculos, sem repetição, sem `group:`), CIDRs RFC 1918 canônicos e sem sobreposição, tamanhos de prefixo, `db_tier` (sem `db-f1-micro` nem Enterprise Plus), versões inteiras positivas, conta de faturamento, valor do budget, e-mails do budget | erro cedo, antes de qualquer chamada ao Google Cloud | `validations.tftest.hcl` (26 casos) e os `rejects_*` do bootstrap | bloqueante |
| IAC-06 | `trivy config` sem achados HIGH/CRITICAL (simples e com `--tf-vars` do exemplo) | segurança da IaC | `trivy-config`, `trivy-config-tfvars` | bloqueante |
| IAC-07 | tflint (preset recommended + ruleset google 0.40.0) sem nenhum issue; ignore inline só com motivo (o motivo é conferido na revisão) | qualidade da IaC | `tflint`; revisão de PR | bloqueante |
| IAC-08 | HCL formatado e válido em todos os roots e módulos (3 roots com o lab local, 8 módulos) | revisões legíveis | `terraform-fmt`, `terraform-validate:*` | bloqueante |
| IAC-09 | Só Autopilot: `enable_autopilot = true`, nenhum `google_container_node_pool`, nenhum `min_master_version` (o canal decide), ABAC legado desligado | sem nós para dimensionar; versões pelo canal | `policy-terraform`; `autopilot_private_dns_endpoint_gateway` | bloqueante |
| IAC-10 | APIs nunca desligadas no destroy; bucket do state sem `force_destroy` e com `deletion_policy = "PREVENT"` até `state_protection = false` | o teardown não quebra o projeto nem apaga o state | `policy-terraform`; `apis_are_enabled_and_never_disabled`, `state_bucket_is_private_versioned_and_protected`, `final_teardown_lifts_the_protection` | bloqueante |
| IAC-11 | Ampliação de IAM, rede, RBAC ou CORS só com justificativa no PR | revisões conscientes | template de PR | processo |
| K8S-01 | Manifests da plataforma validados com kubeconform estrito e schemas fixados por commit | manifest inválido não chega ao cluster | `kubeconform` | bloqueante |
| K8S-02 | Namespace `dx03v2` com Pod Security `restricted` (`enforce` + `enforce-version=latest`), Role com as regras exatas do contrato (inclusive `healthcheckpolicies` e `gcpbackendpolicies` de `networking.gke.io`), RoleBinding com um `User` por e-mail (sem repetição) e ClusterSecretStore `gcpsm` com o `projectID` do contrato, sem bloco `auth`, só para `dx03v2`; o renderizador recusa entradas inválidas | menor privilégio no cluster | `contract-platform` | bloqueante |
| K8S-03 | Values do ESO: ServiceAccount `external-secrets` sem anotação (o próprio ServiceAccount é o principal), três imagens por digest, requests nos três contêineres (Autopilot) | o principal do IAM depende desses nomes | `contract-platform`, `helm-template` | bloqueante |
| K8S-04 | Antes do destroy, o `platform/uninstall.sh` apaga o namespace `dx03v2` e espera o finalizer do Gateway e o sumiço dos NEGs do app; falha alto no timeout | o load balancer do Gateway fica fora do state | ordem em `terraform-destroy.yml`; `policy-workflows` exige o passo | bloqueante |
| K8S-05 | Membros `group:` recusados (o Google Groups for RBAC não está configurado: um grupo nunca casaria com um sujeito `User`) | ninguém recebe IAM sem acesso equivalente no cluster | validação de `app_deployer_members` (`rejects_a_group_member`); `emails_from_members` em `scripts/lib/gcp.sh` | bloqueante |
| APP-01 | Contrato com o dx03v2 versionado: as 15 chaves de `contract.tf`, a lista `CONTRACT_KEYS` do harness e a tabela de `docs/CONTRATO.md` são iguais; valores fixos (`eso/cluster-secret-store`, `lb-source-ranges`); o parâmetro se chama `tx03v2-lab-contract` no Terraform e nos scripts; mudanças em PRs coordenados | os dois lados evoluem juntos | `contract-parameter`; `contract_keys_in_the_parameter` | bloqueante |
| APP-02 | `dx03v2-gha-deploy` e cada `app_deployer_members` recebem exatamente `artifactregistry.writer` no repositório `dx03v2`, `container.clusterViewer` e `parametermanager.parameterAccessor` | quem faz deploy tem o mesmo acesso, nada além | `project_grants_follow_the_contract`, `repository_and_secret_grants`, `no_extra_deployer_by_default` | bloqueante |
| APP-03 | Cloud Armor com só as duas regras pré-configuradas e a regra padrão `allow`, inspeção de 64 KB; sem WAF, o contrato publica `none` | nenhuma regra derruba o smoke test | `waf_policy_follows_the_contract`, `no_waf_publishes_none`, `root_wiring_of_enable_waf` | bloqueante |
| CUSTO-01 | Budget mensal do projeto (padrão 10 na moeda da conta de faturamento) com alertas de 50/90/100 % do gasto e 100 % da previsão, para os administradores da conta e e-mails opcionais validados | quem paga é você | `terraform/bootstrap/budget.tf` + `budget.tftest.hcl` | alerta |
| CUSTO-02 | Padrões baratos: Autopilot (cobrança por request de pod), Cloud SQL `db-g1-small` zonal com 10 GB sem crescimento automático, 1 backup e sem PITR, NAT com logs só de erros, Artifact Registry com limpeza e sem varredura, logs da GKE só `SYSTEM_COMPONENTS` + `WORKLOADS` | custo por hora mínimo | `defaults_are_lab_friendly` e testes dos módulos | bloqueante |
| CUSTO-03 | Destroy falha alto (sem `\|\| true`/`continue-on-error`) e termina com `scripts/leftovers.sh` | erro do v1: destroy que engolia erros | ordem em `terraform-destroy.yml`; `policy-workflows` proíbe engolir erros e exige o passo | bloqueante |
| CUSTO-04 | Rodada em nuvem termina com destroy no mesmo dia, `leftovers.sh` local como Owner e relatório `cloud_run_report` | evita custo esquecido | `docs/RUNBOOK.md` | processo |
| CI-01 | O CI é o harness: jobs só chamam `make <alvo>` | o que passa local passa no CI | revisão de PR; `ci.yml` | processo |
| CI-02 | Sem `continue-on-error: true`, `\|\| true`, `\|\| echo` ou `\|\| :` em workflows; sem `sed` em arquivos Terraform; nenhum workflow apaga state ou lock (`gsutil rm`, `gcloud storage rm`, `force-unlock`) | gates honestos; erro do v1 | `policy-workflows` | bloqueante |
| CI-03 | `permissions: contents: read` no topo, `timeout-minutes`, `concurrency`, `ubuntu-24.04`, `persist-credentials: false` | menor privilégio e previsibilidade | `policy-workflows` | bloqueante |
| CI-04 | `HARNESS_STRICT=1` no CI: todo SKIP vira FAIL | nada é pulado em silêncio | `ci.yml`, `scripts/harness.sh` | bloqueante |
| CI-05 | Workflows de nuvem: só `workflow_dispatch` (o plan também em PR, com guarda), environment `lab`, primeiro passo `Check ...` que valida as variáveis (o check exige o passo; o conteúdo é revisão), login só por Workload Identity Federation, confirmação digitada no destroy | ações caras exigem intenção | `policy-workflows` | bloqueante |
| CI-06 | Plans com `-lock=false` (a identidade do plan só lê o state); apply e destroy mantêm o lock | o plan não consegue gravar o objeto de lock | `policy-workflows` | bloqueante |
| CI-07 | O resumo e o artefato do plan e o resumo do apply trocam o ID e o número do projeto e o sufixo por `<PROJECT_ID>`, `<PROJECT_NUMBER>` e `<SUFFIX>`; os workflows e os scripts mascaram esses valores e os e-mails dos deployers | logs de repositório público | `terraform-plan.yml`, `terraform-apply.yml`, `scripts/lib/gcp.sh` (`mask`) | processo |
| CI-08 | CI semanal agendado (segunda 06:00 UTC) | detecta charts e URLs que mudaram e achados novos | `ci.yml` | alerta |
| CI-09 | O job `e2e` (lab local) roda em todo PR e precisa estar verde antes do merge | a plataforma local é provada, não só renderizada | `ci.yml`; check obrigatório do ruleset | bloqueante |
| LOC-01 | O lab local nunca fala com uma nuvem: sem provider de nuvem nem backend remoto em `terraform/envs/local`; Docker só por socket local; `random_password` e o backend `local` só nesse root (credenciais descartáveis desta máquina, state fora do repositório) | o lab é grátis e seguro de rodar | `policy-terraform`; validação de `docker_host` (`terraform-test:envs/local`) | bloqueante |
| LOC-02 | Contêineres do lab local com o label `tx03v2.lab=local`; só o registry publica porta, e em 127.0.0.1 (`5003`); nada privilegiado | nada fica exposto nem esquecido | `terraform-test:envs/local`, `policy-terraform`, `scripts/leftovers-local.sh` | bloqueante |
| LOC-03 | Charts do lab local fixados por versão e SHA256 do `.tgz`; imagens por digest; Services só ClusterIP (exceto os Gateways, criados em runtime) | supply chain e nenhuma UI exposta (erro do v1: Grafana e Argo CD públicos) | `helm-template-local`, `local-versions`, `platform/local/install.sh` (recusa SHA256 diferente) | bloqueante |
| LOC-04 | Políticas do Gatekeeper em `deny`, webhook `Fail` para o app, cada política com casos aceitos e recusados | no v1 as políticas ficavam em `dryrun` sem audit | `policy-gator`; sonda `policies` do `e2e` | bloqueante |
| LOC-05 | Toda peça da plataforma local tem uma sonda com tráfego ou chamada real; o `e2e` sempre destrói e confere sobras | só se afirma o que foi provado | `platform/local/check.sh`, `scripts/local-lab.sh e2e` | bloqueante (no job `e2e`) |
| MUD-01 | `main` protegido por ruleset: PR obrigatório, checks `static` e `test` estritos, sem force-push | toda mudança passa pelo harness | `.github/rulesets/main.json` + `scripts/repo-guardrails.sh`; `policy-workflows` confere os contextos | bloqueante (depois de publicado) |
| MUD-02 | Ignore de scanner só com `statement` e `expired_at` em até ~7 meses | exceções revisadas | `trivyignore-policy` | bloqueante |
| MUD-03 | Scripts de entrada com bit executável no índice do git | commits do Windows perdem o bit | `repo-structure` (antes do primeiro commit, só um aviso com o comando `git add --chmod=+x`) | bloqueante (depois do primeiro commit) |
| MUD-04 | Conventional Commits; um assunto por PR; CHANGELOG `[Unreleased]` atualizado | histórico legível | `CONTRIBUTING.md`; template de PR (CHANGELOG) | processo |
| DOC-01 | README e docs só afirmam o que é verificado, com os rótulos exatos; sem auto-elogios, emojis ou links para os repositórios v1; README com até 250 linhas; finais de linha LF | honestidade (erro do v1) | `repo-structure`; revisão | bloqueante |
| DOC-02 | Docs atualizadas na mesma mudança do código | docs não envelhecem | template de PR | processo |
| AGT-01 | Agentes de IA nunca executam ações que alteram a nuvem sem pedido humano explícito na tarefa | dinheiro e segurança | `AGENTS.md` | processo |
| AGT-02 | Agentes não enfraquecem gates nem adicionam ignores sem justificativa e validade | o harness só vale se for respeitado | `AGENTS.md`; checks acima | processo |
| AGT-03 | Agentes param e perguntam nos casos listados em `AGENTS.md` | decisões caras são humanas | `AGENTS.md` | processo |

## Exceções

Uma exceção é um ignore de scanner. Para adicionar uma:

1. Confirme que o achado é uma escolha deliberada do lab (não um defeito a corrigir).
2. Adicione a entrada em `.trivyignore.yaml` com `id`, `paths` (o mais restrito possível),
   `statement` (por que é aceitável e o que compensa o risco) e `expired_at` em até ~7 meses.
3. Explique a exceção no PR. O check `trivyignore-policy` rejeita entradas sem justificativa, sem
   validade, vencidas ou longas demais; o trivy deixa de aplicar uma entrada vencida.

Exceções atuais: nenhuma (`misconfigurations: []`, verificado em 2026-10-11). Achados MEDIUM/LOW
conhecidos e aceitos, que não falham o scan (trivy 0.75.0, `--severity LOW,MEDIUM`):

- `GCP-0011` (MEDIUM): `roles/iam.serviceAccountUser` no nível do projeto para `tx03v2-gha-apply`. A
  GKE precisa dele para rodar os nós como `tx03v2-lab-nodes`, conta que só nasce no apply do lab
  (`docs/ARQUITETURA.md`, ADR 15).
- `GCP-0014`, `GCP-0016`, `GCP-0020`, `GCP-0022`, `GCP-0025` (MEDIUM): flags de log do PostgreSQL
  (arquivos temporários, conexões, esperas de lock, desconexões, checkpoints) não definidas; logs do
  Cloud SQL têm custo e o lab é descartável.
- `GCP-0029` (LOW) e `GCP-0076` (MEDIUM): flow logs da subnet desligados (cobrados por GB).
- `GCP-0051` (LOW): labels no cluster. Os labels vêm do `default_labels` do provider no root, que o
  trivy não enxerga ao ler o módulo.
- `GCP-0066` (LOW): bucket do state sem chave gerenciada pelo cliente (CMEK); os dados ficam com a
  criptografia padrão do Google (ADR 23).

## Limites (o que NÃO é garantido)

- Nada do v2 rodou no Google Cloud: os testes usam um provider google mockado e provam a
  configuração, não que o Google Cloud aceita cada chamada nem que os recursos funcionam juntos.
- `tx03v2-gha-apply` é poderoso dentro do projeto (Editor, os papéis de admin de Kubernetes Engine,
  Secret Manager, Artifact Registry e Parameter Manager, Service Account User). A condição IAM limita
  só as concessões no nível do projeto: concessões em recursos (segredos, repositório, parâmetro)
  dependem dos papéis de admin e da revisão de PR. Por isso: projeto dedicado, environment `lab` com
  revisor obrigatório e deploy só a partir de `main`.
- `tx03v2-gha-plan` lê a configuração do projeto, as políticas IAM e o payload do parâmetro do
  contrato (nada secreto). Ele roda em PRs do próprio repositório: quem pode criar branches nele pode,
  em tese, alterar o workflow numa PR e usar essa leitura. Forks não recebem a credencial.
- O ID e o número do projeto ficam nas variáveis de repositório que os workflows usam. O Google não
  os trata como segredo; os workflows os mascaram e os resumos os substituem, mas use um projeto
  dedicado.
- Variáveis de repositório (`GCP_*`, `LAB_*`, `TF_STATE_BUCKET`) aparecem nos logs. Não coloque nelas
  nada privado.
- O endpoint DNS do plano de controle aceita tráfego da Internet: toda requisição precisa do IAM do
  Google (`container.clusters.connect`) e depois do RBAC do Kubernetes, mas o nome é alcançável.
- O Gateway atende só HTTP na porta 80 (HTTPS `planejado`): o tráfego entre o cliente e o load
  balancer não é criptografado.
- O Cloud Armor inspeciona só os primeiros 64 KB de cada corpo; corpos maiores passam sem bloqueio
  por tamanho (a API responde 413).
- Os plurais de RBAC `healthcheckpolicies` e `gcpbackendpolicies` e os mínimos de recursos do
  Autopilot são assumidos (não conferidos num cluster); o preflight do deploy do dx03v2
  (`kubectl auth can-i`, `planejado`) é o que pegaria uma divergência.
- O `max_connections` padrão do `db-g1-small` (50) é assumido a partir da página de cotas do Cloud
  SQL.
- O budget só avisa; ele não para recursos.
- `scripts/leftovers.sh` cobre os tipos de recurso que o lab usa. No workflow, a identidade do apply
  pode não conseguir ler alguma lista (`UNCHECKED`, com aviso, sem mudar o código de saída); a
  checagem completa é local, como Owner do projeto.
- Um pool de Workload Identity Federation apagado fica em soft delete por 30 dias e o ID não pode
  ser reutilizado nesse tempo (`docs/ARQUITETURA.md`, "Nomes que ficam presos").
- O schema do ClusterSecretStore no kubeconform é de 2026-06-02 (`docs/HARNESS.md`).
- O lab local prova a plataforma num nó kind, não no Google Cloud nem no Autopilot; o
  cloud-provider-kind usa o socket do Docker (cria contêineres): rode o lab local só numa máquina
  descartável ou no CI (`docs/LAB_LOCAL.md`). A rodada `e2e` ainda não foi executada neste repositório.
- Os namespaces `istio-system`, `monitoring-agents` e `chaos-mesh` do lab local são `privileged` por
  necessidade dos componentes (o Autopilot recusaria esses componentes); o webhook do Gatekeeper não
  avalia os namespaces da plataforma (para que ela suba mesmo com o Gatekeeper fora do ar).

## Como verificar

```bash
make tools                 # ferramentas fixadas em .tools/
HARNESS_STRICT=1 make verify
scripts/harness.sh list    # todos os checks e estágios
scripts/leftovers.sh       # depois de um destroy (gcloud auth login como Owner, GCP_PROJECT_ID definido)
```
