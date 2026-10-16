# Custos do lab

Estimativa do custo por hora, por dia e de um mês esquecido com os padrões do lab em `us-central1`,
para decidir antes de criar qualquer coisa. Todos os valores são **preços de tabela lidos nas páginas
de preço do Google Cloud em 2026-10-16** (US$, sem impostos, sem créditos e sem transferência de
dados): são estimativas, não verificadas numa fatura. A sua conta de faturamento pode usar outra
moeda, e o budget do bootstrap usa essa moeda. Nada disto foi medido: a v2 nunca rodou em nuvem
(`não executado em nuvem (v2)`).

## Estimativa por componente (perfil core, us-central1)

| Componente | Uso no lab (padrão) | Preço de referência | US$/hora | US$/dia | US$/mês esquecido (730 h) |
|---|---|---|---|---|---|
| Taxa de gerenciamento do cluster GKE | 1 cluster Autopilot | US$0,10/h; free tier de US$74,40/mês por conta de faturamento (um cluster Autopilot ou zonal) | 0,100 (0 com o free tier) | 2,40 (0) | 73,00 (0) |
| Pods do Autopilot (general-purpose) | 550m CPU / 1280MiB de requests: app (300m/512Mi), ESO (200m/512Mi) e Collector (50m/256Mi) | US$0,0445 por vCPU-hora, US$0,0049225 por GiB-hora | ~0,031 | ~0,74 | ~22,36 |
| Cloud SQL `db-g1-small` (ENTERPRISE, zonal) | 1 instância | US$0,035/h | 0,035 | 0,84 | 25,55 |
| SSD do Cloud SQL | 10 GB | US$0,000232877 por GiB-hora | 0,002 | 0,06 | 1,70 |
| Backup do Cloud SQL | 1 backup retido (até ~10 GB) | US$0,000109589 por GiB-hora | até 0,001 | até 0,03 | até 0,80 |
| Application Load Balancer externo global (Gateway) | 1 forwarding rule | primeiras 5 regras: US$0,025/h; mais o processamento de dados por GiB | 0,025 | 0,60 | 18,25 |
| Cloud Armor Standard | 1 política, 3 regras (as duas de WAF e a padrão) | US$0,006849315/h por política, US$0,001369863/h por regra, US$0,75 por milhão de requisições | ~0,011 | ~0,26 | ~8,00 |
| Cloud NAT | 2–3 nós, 1 IP de NAT | US$0,0014/h por VM (até 32), US$0,045/GiB processado, IP de NAT US$0,005/h | ~0,009 | ~0,22 | ~6,70 |
| Endpoint do Private Service Connect (Cloud SQL) | 1 endpoint | ~US$0,01/h + processamento de dados | 0,010 | 0,24 | 7,30 |
| IP externo estático `tx03v2-lab-gateway` | 1 endereço global | sem cobrança enquanto preso a uma forwarding rule; cobrado enquanto reservado sem uso | pequeno | pequeno | pequeno (entre o apply e o deploy) |
| Cloud DNS (zona privada), Secret Manager, Parameter Manager, Artifact Registry, Cloud Logging | 1 zona, 2 segredos, 1 parâmetro, 2 imagens por commit, logs da GKE | centavos por mês na zona DNS; franquias gratuitas: 6 versões de segredo e 6 de parâmetro, 0,5 GB de registry, 50 GiB de logs por projeto | ~0 | ~0 | centavos |
| Cloud Trace (traces do app pelo OpenTelemetry Collector, contrato v2) | volume do lab (milhares de spans por rodada) | US$0,20 por milhão de spans depois de 2,5 milhões por mês por conta de faturamento ([preços do Google Cloud Observability](https://cloud.google.com/products/observability/pricing), verificado em 2026-10-14) | ~0 | ~0 | ~0 |
| Bucket do state, VPC, Cloud Router, IAM, Workload Identity Federation, budget | — | sem cobrança relevante | 0,000 | 0,00 | 0,00 |
| **Total com o free tier da GKE** | | | **~0,12** | **~2,98** | **~91** |
| **Total sem o free tier** | | | **~0,22** | **~5,38** | **~164** |
| Sem WAF (`enable_waf = false`) | | | (~0,011 a menos) | (~0,26 a menos) | (~8 a menos) |

## Perfil full e alternativa gerenciada (R4.2 e R4.7)

O check `platform-sizing` baixa e renderiza os charts fixados em `platform/full/charts.txt`, inclui o
External Secrets Operator do perfil core e soma `requests` dos Deployments/StatefulSets e dos
recursos Prometheus e Alertmanager. O total da plataforma **não inclui o app dx03v2**. Os requests do
app vêm dos valores atuais do dx03v2: duas réplicas da API (100m/128Mi cada) e duas da web
(50m/64Mi cada). A conta de preço usa as tarifas do GKE Autopilot general-purpose em us-central1,
sem desconto, conferidas em 2026-10-16 na [página oficial de preços da GKE](https://cloud.google.com/kubernetes-engine/pricing).

| Perfil | Plataforma, com ESO e Collector | App dx03v2 | Requests totais estimados | Pods por hora | Total do lab com free tier | Total sem free tier |
|---|---:|---:|---:|---:|---:|---:|
| core | 250m CPU / 768MiB RAM | 300m CPU / 512MiB RAM | 550m CPU / 1280MiB RAM | ~US$0,031 | ~US$0,12 | ~US$0,22 |
| full | 840m CPU / 3280MiB RAM | 300m CPU / 512MiB RAM | 1140m CPU / 3792MiB RAM | ~US$0,069 | ~US$0,16 | ~US$0,26 |

O total `full` mantém os demais componentes da tabela principal e substitui apenas o custo dos pods
do `core`. Em uma rodada de três horas, o `full` fica em cerca de US$0,49 com o crédito do cluster
disponível ou US$0,79 sem ele; ligado por 730 horas, cerca de US$119 ou US$192. São estimativas de
requests, sem impostos, tráfego, armazenamento de backup do Velero ou reajustes que o Autopilot faça
para atender mínimos e proporções de CPU/memória. O GKE Autopilot administra a quantidade e o tamanho
dos nós; este perfil não aceita `node_instance_types` nem `node_desired_size`. O argumento de nós do
script de soma não muda o resultado GCP, pois o render não tem DaemonSet.

O orçamento mensal do exemplo/bootstrap foi ajustado de US$10 para **US$5** (na moeda da conta).
Com as tarifas em dólares, os alertas de 50%/100% do `full` chegam depois de aproximadamente 10/19
horas sem o free tier ou 15/31 horas com ele. O budget avisa, não interrompe recursos.

### In-cluster versus observabilidade gerenciada

O `full` escolhe Prometheus/Alertmanager/Grafana, Loki/Alloy e Tempo no cluster. Os quatro renders
de backend somam 175m CPU / 1056MiB RAM, aproximadamente US$0,013 por hora ou US$0,039 em três horas
nas tarifas de Autopilot acima. O OpenTelemetry Collector e os demais componentes permanecem na soma
da plataforma. Esse caminho permite provar scrapes, regras e entrega do Alertmanager, consulta de
logs no Loki e consulta de traces/spanmetrics no Tempo, além da correlação em Grafana.

Como cenário comparável para os serviços gerenciados do Google, considere uma rodada de três horas,
100 séries Prometheus amostradas a cada 15 segundos (72 mil amostras), 100MiB de logs e 100 mil
spans. O Managed Service for Prometheus custa cerca de US$0,00432 pelas amostras a US$0,06 por
milhão; os logs ficam abaixo da franquia mensal de 50GiB por projeto e os traces abaixo dos primeiros
2,5 milhões de spans por conta de faturamento, se esses limites ainda não tiverem sido usados.
Nesse cenário a ingestão gerenciada custa cerca de **US$0,004 por rodada**, mais os requests dos
coletores necessários. Ela prova a chegada e a consulta de dados no Cloud Monitoring, Cloud Logging
e Cloud Trace, mas não prova Loki, Tempo, Grafana ou o receiver local do Alertmanager. Tarifas e
franquias foram conferidas em 2026-10-16 na [página oficial de preços do Cloud Observability](https://cloud.google.com/products/observability/pricing).
O volume acima é uma hipótese reproduzível, não uma medição do lab.

Hipóteses: o app do dx03v2 com 2 réplicas de API e web (o HPA pode subir as da API até 4); 2–3 VMs
de nó para estimar a linha do Cloud NAT (o Autopilot escolhe quantas usa); tráfego de laboratório
(centavos de processamento de dados e de requisições ao Cloud Armor); logs dentro da franquia. Se a
regra padrão do Cloud Armor não for cobrada, a política custa ~US$7/mês em vez de ~US$8.

Leituras rápidas:

- Uma rodada de 3 horas do `core` custa cerca de US$0,37 com o free tier e US$0,67 sem; o `full`,
  US$0,49 ou US$0,79, mais dados e armazenamento dos backups.
- Esquecido ligado, o `core` custa cerca de US$2,98/dia com o free tier e US$5,38 sem; o `full`,
  US$3,90 ou US$6,30. Em 730 horas, o `full` fica em cerca de US$119 ou US$192. Com o budget de
  US$5, o alerta de 50% chega em horas, não em dias.
- Sem o free tier, a taxa do cluster é o maior item (~45 % do total), seguida do Cloud SQL (~17 %) e
  do load balancer (~11 %). Com o free tier, o Cloud SQL (~32 %), os pods (~22 %) e o load balancer
  (~21 %) dominam.
- O budget nunca para os gastos: destrua no mesmo dia.

## O free tier da GKE

O que foi lido em 2026-10-16 na página de preços da GKE: a taxa de gerenciamento é de US$0,10/h por
cluster, e cada conta de faturamento recebe US$74,40 por mês de crédito, o bastante para um cluster
Autopilot ou zonal o mês inteiro (clusters Standard regionais não são cobertos). O cluster do lab é
Autopilot regional, então está coberto, **desde que nenhum outro cluster da mesma conta de
faturamento já use o crédito**. Isso só se confirma numa fatura: na primeira rodada em nuvem,
agrupe o custo por SKU nos relatórios do Cloud Billing, registre se a taxa do cluster apareceu e o
crédito correspondente no `cloud_run_report` e atualize esta seção.

## Tamanho do Cloud SQL

O padrão é `db-g1-small` na edição ENTERPRISE: o PostgreSQL 16+ cria Enterprise Plus por padrão, e os
tiers de núcleo compartilhado só existem na Enterprise (`docs/LICOES_APRENDIDAS.md`, lição 12). O
`max_connections` padrão do `db-g1-small` é 50 (assumido a partir da página de cotas do Cloud SQL;
confira na revisão trimestral), o bastante para até 4 réplicas da API × `DB_POOL_MAX` 10 mais a
migração. A validação de `db_tier` recusa `db-f1-micro` (25 conexões) e os tiers da Enterprise Plus
(`rejects_db_f1_micro`, `rejects_an_enterprise_plus_tier`); aceita tiers `db-custom-*` e
`db-n1-*` da Enterprise, que custam várias vezes mais: refaça a conta antes de trocar. Disco de 10
GB sem crescimento automático, zonal, 1 backup retido e sem PITR mantêm o resto do custo baixo.

## Cenários do v1 (GCP, notas do tx03)

Das notas do v1 (detalhes em `docs/LICOES_APRENDIDAS.md`, lições 2 a 5 e 12), para comparação; não
servem como orçamento atual e vários eram texto fixo, sem dado de faturamento:

| Cenário do v1 | Valor nas notas |
|---|---|
| Custo "atual" gerado pelo workflow de custos | US$60-70/mês, "65 % do budget de US$100" (o budget não existia) |
| Load balancers | ~34 % do custo, ~US$18/mês por forwarding rule, 3 forwarding rules |
| Prometheus, Grafana e Alertmanager | US$26-40/mês + 17 Gi de PVC |
| Recursos órfãos depois do destroy | US$15-25/mês, se esquecidos |
| Cloud SQL `db-perf-optimized-N-2` (Enterprise Plus) | ~US$150/mês |
| "Quick wins" de economia | -US$38-48/mês (60 %), nunca medidos |

A lição continua valendo: cada forwarding rule e cada add-on custa todo mês. A v2 tem um único
Gateway; o core usa ESO e OpenTelemetry Collector, enquanto o full acrescenta os add-ons compatíveis
com Autopilot descritos acima. O destroy termina com a checagem de sobras.

## Dicas

- Destrua no mesmo dia e rode `scripts/leftovers.sh` localmente, como Owner do projeto, até não
  haver nada `BILLABLE` (`docs/RUNBOOK.md`). Apagar o projeto dedicado é a limpeza final mais forte.
- `enable_waf = false` economiza ~US$0,011/h, mas o app fica sem WAF; o dx03v2 faz o deploy sem as
  GCPBackendPolicies quando `waf/security-policy` é `none`.
- O Autopilot cobra os requests dos pods: mais réplicas ou requests maiores mudam a conta (o ESO usa
  limits = requests).
- O free tier da GKE é da conta de faturamento inteira: outro cluster na mesma conta o consome.
- O endereço global reservado é cobrado enquanto não estiver preso a uma forwarding rule (entre o
  apply e o deploy do dx03v2); o `terraform destroy` o apaga.
- Créditos de avaliação escondem a fatura: confira os relatórios do Cloud Billing nas primeiras horas
  de cada rodada e mantenha os alertas do budget.
