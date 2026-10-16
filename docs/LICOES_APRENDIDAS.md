# Lições aprendidas do lab GCP v1 (tx03 e dx03)

Este documento resume o que falhou no lab GCP v1 (repositórios tx03 e dx03, branch `master`), por
que falhou e o que a v2 faz no lugar. Serve de referência para operar e evoluir o tx03v2/dx03v2 sem
repetir os mesmos erros. Os repositórios v1 são privados ou arquivados e não são linkados.

Fontes: 28 notas apagadas do histórico git (25 do tx03, 3 do dx03; ~11.800 linhas), os arquivos
atuais dos dois repositórios (branch `master`) e os specs e o contrato da v2. Identificadores reais
foram substituídos por placeholders (`<PROJECT_ID>`, `<owner>`, `203.0.113.x`, `example.com`,
`<sufixo>`); nenhuma senha, token ou ID de execução foi copiado.

Cada lição segue **O que aconteceu na v1 → Lição → Na v2**. As linhas "Na v2" descrevem o código
deste repositório (`verificado no CI` pelo harness, `não executado em nuvem (v2)`); quando citam
o dx03v2, descrevem o repositório dele (o deploy em nuvem é `não executado em nuvem (v2)`).

## Custos e faturamento

### 1. Budget existia como módulo, nunca como recurso

- O que aconteceu na v1: `terraform/modules/billing-budget` (5 limiares, Pub/Sub, alerta de "cost spike") nunca foi chamado pelo root `dev`; a nota de sessão marca "Budget alerts ativados no GCP: pendente". O módulo também era inválido: alerta com filtro `resource.type = "global"` sem métrica, canais de e-mail criados mas não ligados ao budget, `currency_code = "USD"` fixo e conta de faturamento buscada por nome de exibição.
- Lição: budget é o primeiro recurso do lab, aplicado e testado, não documentação.
- Na v2: `google_billing_budget` no bootstrap (escopo do projeto, `budget_amount` padrão 5 sem `currency_code`, limiares 0.5/0.9/1.0 + 1.0 previsto, e-mail via `google_monitoring_notification_channel`), coberto por `terraform test` do bootstrap.

### 2. Números de custo inventados

- O que aconteceu na v1: o workflow `cost-management.yml` gerava "Custo atual $60-70/mês, 65% do budget de $100" e previsão de 3 meses a partir de faixas escritas à mão; o próprio relatório mostrava o tier do Cloud SQL vazio e o budget de $100 não existia. "Quick wins de -$38-48/mês (60%)" nunca foram medidos.
- Lição: custo só vem do Cloud Billing; estimativa precisa dizer que é estimativa.
- Na v2: fora do escopo (sem workflow de custo); o controle é o budget do bootstrap e o `scripts/leftovers.sh` (BILLABLE/ORPHANED); o `docs/CUSTOS.md` rotula todo valor como estimativa.

### 3. Load balancers são o maior custo fixo

- O que aconteceu na v1: a nota de custos atribui ~34% ao LB (~$18/mês por forwarding rule); havia 3 forwarding rules: HTTP e HTTPS do Ingress e um Service `LoadBalancer` só para o ArgoCD (segundo IP público).
- Lição: um único ponto de entrada; cada forwarding rule é custo e superfície de ataque.
- Na v2: um Gateway (`gke-l7-global-external-managed`, criado pelo dx03v2) com o endereço global reservado `tx03v2-lab-gateway`, listener HTTP 80; sem ArgoCD.

### 4. Destroy deixava órfãos criados pelo Kubernetes

- O que aconteceu na v1: o relatório de validação do destroy listou 10+ recursos fora do state (3 forwarding rules, 3 backend services, URL map, 2 target proxies, 2 certificados gerenciados, 3 regras de firewall `k8s-*`, discos de PVC de 5 e 10 GB), estimados em $15-25/mês se esquecidos.
- Lição: apagar primeiro o que os controladores criaram e só então o Terraform; conferir o que sobrou.
- Na v2: `platform/uninstall.sh` apaga o namespace `dx03v2`, espera o finalizer do Gateway e o sumiço dos NEGs `k8s1-*` do app; o destroy termina com `scripts/leftovers.sh --retry-for 900`.

### 5. Add-ons do cluster custavam mais que o app

- O que aconteceu na v1: Prometheus/Grafana/Alertmanager estimados em $26-40/mês + 17 Gi de PVC, Istio com 5 pods ociosos ("instalado mas inativo") e ArgoCD com 7 pods, num app de 4 pods que usava ~10m de CPU cada.
- Lição: em lab, cada add-on precisa de um motivo e de um custo aceito.
- Na v2: só o External Secrets Operator 2.12.0 (requests definidos); logs do GKE `SYSTEM_COMPONENTS` + `WORKLOADS`; observabilidade in-cluster, Istio e ArgoCD fora do escopo da v2.

## GKE e rede

### 6. Control plane exposto

- O que aconteceu na v1: `modules/gke` não tem `private_cluster_config` nem `master_authorized_networks_config` (endpoint IP público aberto); o `terraform.tfvars.example` cita `master_authorized_cidrs`, `enable_private_nodes` e `enable_private_endpoint`, mas nenhuma dessas variáveis existe no root.
- Lição: variável de exemplo que o código ignora é pior que nenhuma; o endpoint tem de ser fechado no código e provado por teste.
- Na v2: nós privados, endpoint IP público desligado, redes autorizadas sem CIDR, endpoint DNS com autorização só pelo IAM (`get-credentials --dns-endpoint`), provado em `gke.tftest.hcl`.

### 7. O Autopilot recusa o que precisa de privilégio

- O que aconteceu na v1: o GKE Warden recusou `NET_ADMIN` (sidecar e ztunnel do Istio), `patch` em `kube-system`, hostPath do node-exporter e webhooks com regra `('*','*')`/`nodes/proxy` do Trivy Operator (`GKE Admission Webhook Controller: the following (group,resource) pairs are not allowed`).
- Lição: verificar a compatibilidade com Autopilot de cada chart antes de escrever workflow e documentação.
  - Na v2, o perfil `core` instala ESO e Collector; o `full` acrescenta charts que cabem no Autopilot. Istio ambient, node-exporter, Trivy node collector e o daemon do Chaos Mesh ficam fora do perfil GCP. `helm-template-full` e `kubeconform` validam os renders; a admissão em nuvem permanece não verificada.

### 8. Ingress sem IP por mais de 3 horas

- O que aconteceu na v1: o Ingress apontava para a porta do contêiner (3000) em vez da porta do Service (80), faltava a anotação NEG e havia uma anotação de ManagedCertificate para um recurso que não existia; nenhum forwarding rule era criado.
- Lição: roteamento por porta de Service e health check explícito; o deploy tem de esperar o LB ficar pronto e falhar se não ficar.
- Na v2: HTTPRoute `/api` → `api:3000`, `/` → `web:8080`; HealthCheckPolicies `/readyz` e `/healthz`; o deploy espera o Gateway `Programmed` e confere o endereço contra `gateway/address` (dx03v2).

### 9. Cloud Armor anexado por script, depois do deploy

- O que aconteceu na v1: um passo do workflow do app listava backend services `k8s1-*` por nome e anexava `tx03-waf-policy` a cada um; a política tinha rate limit de 100 req/min e "adaptive protection".
- Lição: a associação WAF ⇄ backend deve ser declarativa e versionada; limites não podem derrubar o próprio smoke test.
- Na v2: GCPBackendPolicies `api` e `web` com o `securityPolicy` do contrato, omitidas quando `none` (dx03v2); regras `sqli-v33-stable`/`xss-v33-stable` em `tx03v2-lab-waf`; limite de taxa, se existir, >= 300 req/min (contrato).

### 10. Rede plana dentro do cluster

- O que aconteceu na v1: firewall `allow-internal` liberava TCP/UDP 0-65535 e os manifests começaram sem NetworkPolicy; o banco era alcançado por peering (faixa /16 reservada).
- Lição: segmentar por destino exato, não por faixa.
- Na v2: Dataplane V2 (Autopilot); NetworkPolicies do dx03v2 fixadas no contrato: entrada em web/api só de `35.191.0.0/16,130.211.0.0/22`; saída da api só para `db/endpoint-ip`/32:5432; DNS para `169.254.20.10`.

### 11. Timeouts e esperas no Autopilot

- O que aconteceu na v1: pods levavam 5-10 min para subir, Helm estourou `context deadline exceeded` em 10 min (passou a 20 min sem `--wait`), e um `kubectl delete pod --all` deixou o app com 0 pods por ~17 h sem alarme.
- Lição: toda espera com prazo explícito e falha visível.
- Na v2: o `platform/install.sh` usa `helm --wait=watcher --rollback-on-failure` (15 min) e espera o ClusterSecretStore; o `platform/uninstall.sh` falha alto no timeout (900 s para o namespace e para os NEGs); o deploy do dx03v2 espera ExternalSecrets Ready, rollouts e Gateway (`SMOKE_WAIT_SECONDS` 900; `não executado em nuvem (v2)``).

## Cloud SQL

### 12. PostgreSQL 16 cria Enterprise Plus

- O que aconteceu na v1: três applies falharam com `Invalid Tier (db-f1-micro) for (ENTERPRISE_PLUS) Edition`, depois `db-custom-1-3840` e `db-perf-optimized-N-2` (~$150/mês). A correção foi rebaixar para PostgreSQL 14; hoje o root voltou a `POSTGRES_16` com `db-g1-small` e sem `edition`, ou seja, o erro original volta num ambiente novo.
- Lição: a edição é parte da configuração; nunca depender do padrão da versão.
- Na v2: PostgreSQL 17, `edition = ENTERPRISE`, tier padrão `db-g1-small`, validação recusa `db-f1-micro` (25 conexões, abaixo de 4 réplicas × pool 10 + migração) e os tiers da Enterprise Plus.

### 13. Criação parcial e nomes fixos

- O que aconteceu na v1: uma criação que falhou deixou a instância `tx03-postgres-<sufixo>` fora do state (import manual); o workflow de apply passou a checar esse nome fixo com `gcloud sql instances describe`.
- Lição: nomes vêm do código, nunca de scripts; após falha, inventariar antes de repetir.
- Na v2: sufixo `random_id` de 2 bytes (o nome de instância apagada fica bloqueado até uma semana); `leftovers.sh` lista instâncias e backups retidos.

### 14. Senha com caracteres especiais e senha em documento

- O que aconteceu na v1: uma senha de 32 caracteres com símbolos quebrou no pipeline (`FATAL 28P01`, autenticação recusada para o usuário do app); foi trocada à mão por 24 alfanuméricos, gravada como secret do GitHub e as duas senhas foram coladas em claro em `APPLICATION_DEPLOYMENT.md` e `STATUS.md` (<REDACTED>).
- Lição: senha nunca passa por shell nem por documento; um único gerador alimenta banco e cofre.
- Na v2: `random_password` efêmero (40 alfanuméricos) envia o mesmo valor ao Cloud SQL e ao Secret Manager pelos argumentos write-only (`*_wo`), fora de state e plan; o ESO entrega ao pod.

### 15. Chaves de Secret divergentes

- O que aconteceu na v1: o workflow criava `host/port/name/user/password` e o Deployment esperava `database/username` (`CreateContainerConfigError`); antes disso `kubectl create secret --dry-run | kubectl apply` falhava com `error: no objects passed to apply`.
- Lição: nomes de chaves são contrato, conferido por máquina.
- Na v2: JSON `username,password,host,port,dbname` no segredo (`terraform/envs/lab/secrets.tf`) e Secret `db-credentials` com `DB_*`, ambos fixados no contrato; o `contract-parameter` confere as 15 chaves do parâmetro, e o lado do app é conferido pelo `contract-app` do dx03v2 (CI verde lá).

### 16. TLS sem verificação do servidor

- O que aconteceu na v1: IP privado via peering e `ssl_mode = ENCRYPTED_ONLY`, mas o app conectava sem CA e sem conferir o nome do servidor.
- Lição: criptografar sem verificar não autentica o banco.
- Na v2: só Private Service Connect + zona DNS privada e CA compartilhada (o nome DNS da instância no certificado); o dx03v2 usa `DB_SSL_MODE=verify-full` com o bundle da região, aceito só se a raiz tiver o SHA-256 do contrato (`não executado em nuvem (v2)`).

### 17. Backup "production-ready" nunca restaurado

- O que aconteceu na v1: 30 backups retidos + PITR de 7 dias e um workflow diário que exportava Secrets do K8s em base64 como artifact; o item "teste de restore" ficou desmarcado.
- Lição: backup sem restore testado é suposição; nunca exportar segredos para artifacts.
- Na v2: lab com 1 backup retido e `retain_backups_on_delete = false`; workflow de backup/restore fora do escopo da v2.

## IAM, WIF e CI

### 18. WIF criado à mão e aberto ao dono inteiro

- O que aconteceu na v1: pool e provider criados por `gcloud` (fora do Terraform) com condição `assertion.repository_owner == '<owner>'`; o vínculo era `principalSet` por repositório e o dx03 precisou de um vínculo extra feito à mão depois de falhar.
- Lição: identidade federada em código, restrita a repositório e sujeito.
- Na v2: pool `tx03v2-github` no bootstrap, condição dono + lista de 2 repositórios, um `roles/iam.workloadIdentityUser` por sujeito exato (PR, `main`, `environment:lab`), provado em `identities.tftest.hcl`.

### 19. Uma conta de serviço para tudo, com papéis crescendo por tentativa

- O que aconteceu na v1: `github-actions-sa` servia plan, apply, deploy, Istio e custos; os papéis cresceram a cada erro (`artifactregistry.repositories.create denied`, `iam.serviceAccounts.getAccessToken denied`) até `compute.admin`, `container.admin`, `serviceAccountTokenCreator` sobre si mesma, `serviceusage.serviceUsageAdmin` e `resourcemanager.projectIamAdmin` sem condição; o ASM ainda pedia `gkehub.admin`.
- Lição: uma conta por função e o poder de conceder IAM sempre condicionado.
- Na v2: `tx03v2-gha-plan` (leitura, `-lock=false`), `tx03v2-gha-apply` (`projectIamAdmin` com `modifiedGrantsByRole hasOnly([...])` igual à lista do root) e `dx03v2-gha-deploy` (AR writer no repo, `clusterViewer`, `parameterAccessor`); `roles.tftest.hcl` nos dois roots.

### 20. Cada workflow novo repetia os mesmos três erros de auth

- O que aconteceu na v1: `must specify exactly one of 'workload_identity_provider' or 'credentials_json'` (secrets ausentes), `$ACTIONS_ID_TOKEN_REQUEST_TOKEN` não injetado (faltava `id-token: write`) e `executable gke-gcloud-auth-plugin not found`, em infra, app, observabilidade e Istio (3 falhas seguidas em alguns).
- Lição: um padrão de job validado, não cópia manual.
- Na v2: primeiro passo valida `vars.*`; `id-token: write` só nos jobs com `environment: lab` (e no plan, atrás da guarda de variável e de mesmo repositório); `auth` e `setup-gcloud` 588.0.0 com `gke-gcloud-auth-plugin`, fixados por SHA; `policy-workflows` no harness.

### 21. CI que só rodava `ls`

- O que aconteceu na v1: `ci.yml` listava `*.md`, workflows e `terraform/` e imprimia "Repository is valid!"; nenhum fmt, validate, lint ou teste.
- Lição: CI verde precisa significar algo.
- Na v2: `scripts/harness.sh` (static + test), `HARNESS_STRICT=1` com zero SKIP, `terraform test` com mock provider, tflint google, trivy config, shellcheck.

### 22. Plan disparava em `main`, o repositório era `master`

- O que aconteceu na v1: `terraform-plan.yml` escutava `pull_request` em `main`; o branch padrão era `master`, então nenhum PR teve plan.
- Lição: gatilhos e branch padrão precisam ser testados juntos.
- Na v2: branch `main` com ruleset versionado; o sujeito do plan cobre `pull_request` e `refs/heads/main`.

## Terraform e state

### 23. Apagar o lock antes de todo apply

- O que aconteceu na v1: locks órfãos (cancelamento/timeout) bloquearam 5+ execuções; a "correção" foi `gsutil rm .../default.tflock` com `continue-on-error` antes de cada apply, removendo também locks legítimos.
- Lição: nunca apagar lock automaticamente; `force-unlock <ID>` é decisão manual.
- Na v2: plan sem lock e só leitura no bucket; apply com `storage.objectUser` atrás do environment `lab`; nenhum passo remove lock (o `policy-workflows` recusa `gsutil rm`, `gcloud storage rm` e `force-unlock`).

### 24. Plan e apply no mesmo job, sem revisão

- O que aconteceu na v1: `terraform-apply.yml` fazia `plan -detailed-exitcode` e aplicava em seguida; oferecia `prod` sem diretório; o destroy usava `-refresh=false` + `-auto-approve`; um apply travou 16+ min esperando uma variável interativa (`service_account_email`).
- Lição: apply só de um plano revisado, variáveis validadas e nenhuma entrada interativa.
- Na v2: o `terraform-plan` (PR ou dispatch) mostra o plano antes; o apply roda só no environment `lab` (sujeito `environment:lab`, revisor obrigatório) e aplica o plano salvo do próprio job; `TF_INPUT=0` e variáveis com `validation`; destroy com confirmação digitada, uninstall da plataforma e leftovers.

### 25. Execução local misturada com CI

- O que aconteceu na v1: plan/apply locais com credencial pessoal criaram o cluster fora do pipeline (`Error 409: Already exists`); seguiram 2 imports manuais e o workflow deixou de ser idempotente.
- Lição: cada root tem um único executor definido.
- Na v2: bootstrap só pelo Owner a partir do laptop (state local documentado); root `lab` pelos workflows com as contas de plan/apply.

### 26. Backend e versões soltos

- O que aconteceu na v1: bucket fixo no `backend "gcs"` e sobrescrito por `-backend-config`; o destroy podia apagar o bucket com todas as versões; provider `~> 6.50`, `required_version >= 1.9.0` e nenhum `.terraform.lock.hcl` no histórico.
- Lição: state protegido e build reproduzível.
- Na v2: `backend "gcs" {}` + `backend.hcl.example`; bucket `tx03v2-tfstate-<sufixo>` versionado, `force_destroy = false` e `deletion_policy = "PREVENT"` até o teardown, fora do destroy do lab; google 8.6.0 e random 3.9.1 travados no lock multiplataforma (restrições `~> 8.6` e `~> 3.9`).

### 27. `destroy.yml` quebrado por merge

- O que aconteceu na v1: o passo de limpeza tem `echo "... Check GCP Console for details` sem fechar aspas, seguido de um trecho colado de outra versão; o bash do passo não faz parse e o `continue-on-error` escondia a falha.
- Lição: lógica de shell fora do YAML, com análise estática.
- Na v2: lógica em `scripts/` e `platform/`, shellcheck no harness (falha em erro de sintaxe) e actionlint com shellcheck nos blocos `run`; `leftovers.sh` com códigos de saída.

## Malha de serviço e GitOps (Istio/ArgoCD)

### 28. README dizia mTLS; a malha estava em PERMISSIVE e sem sidecars

- O que aconteceu na v1: `k8s/istio/security.yaml` usa `PeerAuthentication` `PERMISSIVE` e a injeção nunca funcionou (0% dos pods com sidecar), então não havia mTLS algum.
- Lição: documentação só afirma o que foi verificado.
- Na v2: fora do escopo da v2 (sem malha); o contrato marca cada item como `verificado localmente` ou `não executado em nuvem (v2)`.

### 29. Três rotas de malha, todas bloqueadas

- O que aconteceu na v1: sidecar terminou em `Init:CrashLoopBackOff` (`iptables validation failed; workload is not ready for Istio`, `NET_ADMIN` fora da lista do Autopilot); Ambient foi recusado (`NET_ADMIN` no ztunnel, `patch` em `kube-system`); ASM falhou por falta de `serviceusage.services.enable` e `gkehub.memberships.create`. Foram 5+ tentativas e ~2.400 linhas de documentação.
- Lição: provar a viabilidade num spike pequeno antes de criar workflows e guias; os workflows de reparo que vieram depois (`troubleshoot-pods.yml`, `istio-fix-sidecar.yml`, `delete pod --force --grace-period=0`) só tratavam o sintoma.
- Na v2: fora do escopo da v2; segmentação por NetworkPolicy (Dataplane V2).

### 30. ArgoCD apontava para um caminho inexistente

- O que aconteceu na v1: a Application `dx03-app` sincronizava `k8s/application` do repositório de infra em `HEAD` com `prune`/`selfHeal`, mas esse caminho nunca existiu no histórico; o deploy real era o workflow do app (dois "donos" do mesmo namespace); servidor exposto por LoadBalancer com `server.insecure: "true"`.
- Lição: um único caminho de deploy por namespace.
- Na v2: fora do escopo da v2; só o deploy do dx03v2 escreve no namespace, limitado pela Role `dx03v2-deployer` (`contract-platform`).

## Aplicação e deploy

### 31. Dependências do client que não instalam

- O que aconteceu na v1: primeiro `npm ci` com `EUSAGE` (sem lockfile; Dockerfiles trocados para `npm install`), depois `.gitignore` com `*.json` escondendo `package.json` (`failed to calculate checksum ... '/package.json': not found`); hoje o client fixa `eslint ^8.55` com `eslint-plugin-react-refresh ^0.5.2`, que exige eslint 9, e o `npm ci` falha com `ERESOLVE`.
- Lição: lockfile versionado, `npm ci` no CI e build do mesmo jeito local e remoto.
- Na v2: `api/` e `web/` vão ser copiados do dx02v2 (CI verde lá), com versões fixadas e `make verify`/`make build` no container de desenvolvimento (dx03v2).

### 32. `NODE_ENV: "dev"` derruba o backend

- O que aconteceu na v1: o ConfigMap foi de `production` para `dev` só para mudar o rótulo na UI; o config atual aceita apenas `development|test|staging|production` e encerra com `Invalid NODE_ENV "dev"`.
- Lição: ambiente lógico separado do modo de execução do Node.
- Na v2: o rótulo de ambiente é `APP_ENV=lab` no app-config (overlay `gcp`), sem reaproveitar `NODE_ENV` (dx03v2).

### 33. Probe que depende de `sed`

- O que aconteceu na v1: a readiness do backend envia `Authorization: Bearer METRICS_TOKEN_PLACEHOLDER` e o Secret tem o mesmo literal; sem o `sed` no deploy, `/health/ready` responde 401 e o pod nunca fica pronto.
- Lição: probes e health checks sem segredo; segredo só por Secret.
- Na v2: health checks `/readyz` (api) e `/healthz` (web) no contrato; `ADMIN_TOKEN` só via ExternalSecret `app-secrets` (dx03v2).

### 34. UI lendo campos que a API removeu

- O que aconteceu na v1: `/health` passou a responder só `{status: "alive"}` (os dados foram para `/health/ready`, com token), mas `App.tsx` ainda lê `health.memory.used` e `health.database.*`; é o mesmo `TypeError: Cannot read 'used'` já visto no deploy #42.
- Lição: API e UI mudam juntas, com teste de ponta a ponta.
- Na v2: o mesmo app do dx02v2, com testes de integração, smoke 12/12 e e2e no kind lá; `SMOKE_EDGE=gke` cobre o caminho pelo Gateway (dx03v2).

### 35. URL da API resolvida no build

- O que aconteceu na v1: `VITE_API_URL=""` não era substituído e o browser chamava `localhost:3000`; a saída foi `window.location.origin`, com um comentário no código citando o IP público.
- Lição: mesma origem atrás do LB; nada de endereço real no código.
- Na v2: `/api` e `/` no mesmo HTTPRoute (dx03v2); `policy-identifiers` só aceita placeholders e as faixas documentadas.

### 36. Imagens mutáveis e credenciais em secrets do GitHub

- O que aconteceu na v1: push de `:latest` e `:<sha>`, bases `node:20-alpine`/`nginx:alpine` flutuantes; `DB_PASSWORD` e `DB_HOST` como secrets do GitHub e `kubectl create secret` no workflow; 20 execuções (19 falhas) até o primeiro deploy e 44 deploys até a UI funcionar.
- Lição: imagem imutável e endereçada pelo commit; o pipeline de deploy não manipula segredos.
- Na v2: Artifact Registry com tags imutáveis (este repositório); SHA de 40 caracteres (tag existente é reutilizada), `linux/amd64` e gate trivy no dx03v2; a conta de deploy não tem nada no Secret Manager (`repository_and_secret_grants`).

## Processo e documentação

### 37. Status escrito antes da evidência

- O que aconteceu na v1: notas declaravam "PRODUCTION READY", "100% HEALTHY", "uptime 99.9%" e "Lighthouse 95+" sem medição; a mesma nota dava o banco como "Conectado" com usuário diferente do Terraform.
- Lição: status só com evidência reproduzível.
- Na v2: tabela "Como o contrato é verificado aqui" com status explícito, matriz de status no README; `docs/RUNBOOK.md` para o comportamento em nuvem.

### 38. Identificadores e segredos em Markdown

- O que aconteceu na v1: as notas tinham ID e número do projeto, e-mail da conta de serviço, nomes de bucket, IPs públicos, domínio e duas senhas do banco; uma nota do dx03 trazia o ID do projeto sem redação.
- Lição: o repositório só aceita placeholders, verificado por máquina.
- Na v2: `policy-identifiers` no harness, com allowlist de placeholders e faixas documentadas; `gitleaks` no harness e no pre-commit.

### 39. Depuração por tentativa e erro no CI

- O que aconteceu na v1: infra em 11 execuções (10 falhas, ~4 h), app em 20 (19 falhas, ~3 h), Istio com 10+ falhas e um commit por tentativa; as 25 notas do tx03 somavam ~10.000 linhas e foram apagadas depois.
- Lição: validar localmente antes do push; documentação curta e mantida.
- Na v2: harness no dev container antes de qualquer push; o deploy do dx03v2 foi testado offline com stubs de `gcloud`/`kubectl`/`docker` (13 cenários); README, CHANGELOG, CONTRATO e RUNBOOK no lugar de notas de sessão.

## Afirmações das notas que não puderam ser confirmadas

- Custos ($60-70/mês, previsões, economias): nenhum dado de faturamento nas notas; os números do workflow eram texto fixo.
- Alertas de budget e do Slack "ativos": o budget nunca foi chamado no root; o webhook é um secret não verificável.
- HTTPS com certificado gerenciado e redirect 301: os manifests existem no dx03, o funcionamento em nuvem não é verificável aqui.
- Backups diários com PITR e restore "testado": a configuração existe no módulo; nenhum restore está registrado.
- Cloud Armor associado a todos os backend services: dependia de um passo de workflow, sem estado em código.
- "Teste final idempotente em 1m25s" e pods "4/4 healthy": sem log versionado.
- Notas contraditórias sobre o Ambient Mesh ("compatível com Autopilot" e depois "bloqueado"); a última versão diz bloqueado.
- `destroy.yml` atual nunca poderia ter rodado o passo de limpeza inteiro; as notas descrevem limpezas bem-sucedidas de uma versão anterior.
