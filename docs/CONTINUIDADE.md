# Continuidade de dados — R9 (Google Cloud)

Este capítulo é um roteiro para o **fork**. O código de infraestrutura e os testes Terraform usam
provedores simulados; nenhum apply, restore ou failover foi executado no Google Cloud na v2. O
exercício Docker do perfil local testa PostgreSQL físico, mas não prova HA da Cloud SQL, replicação
entre regiões ou o tempo real de uma promoção. Consulte [custos](CUSTOS.md) antes de mudar de perfil.

## Perfis e limites

| `db_profile` | Banco principal | Região secundária | Uso |
|---|---|---|---|
| `core` (padrão) | Cloud SQL Enterprise `db-g1-small`, zonal, 1 backup, sem PITR | nenhuma | aprender com o menor custo |
| `ha` | `db-custom-1-3840`, regional, PITR, 7 backups e 7 dias de WAL | nenhuma | falha de zona e restore isolado |
| `dr` | como `ha` | réplica Cloud SQL assíncrona, VPC, GKE Autopilot, Artifact Registry, segredos, Parameter Manager e bucket Velero em outra região | ensaio de perda regional e promoção com aprovação humana |

`dr_region` é `us-east1` por padrão e deve diferir de `region`. As faixas CIDR secundárias são
privadas e separadas dentro da VPC secundária. O custo do cluster secundário começa no apply mesmo
sem o app implantado. `ha_db_tier` deve ter CPU dedicada; instâncias shared-core não têm SLA de HA.
`db_backup_count` seleciona a retenção (1 em `core`, 7 nos perfis HA/DR, salvo valor explícito válido).
`db_deletion_protection` e `db_retain_backups_on_delete` são opt-in: ambos aumentam a proteção, mas
exigem desativação deliberada ou revisão de cobrança antes do destroy.

Cloud SQL HA replica entre zonas de uma região. A réplica DR atravessa regiões de forma **assíncrona**;
um failover pode perder transações recentes. O cluster e os segredos da segunda região são recursos
independentes, mas a promoção e a troca de tráfego **não** são automáticas. O `dr` cria a réplica e
o endpoint PSC isolado. Após promoção, valide backups/PITR na nova principal antes de reabrir escrita.

## Provas sem nuvem

1. `terraform -chdir=terraform/envs/lab init -backend=false -lockfile=readonly` e
   `terraform -chdir=terraform/envs/lab test`: os casos `continuity.tftest.hcl` conferem que `core`
   não paga segunda região, `ha` não cria DR, e `dr` conecta a réplica à principal e publica os
   recursos independentes. `validations.tftest.hcl` recusa região igual, shared-core no perfil HA,
   retenção curta e CIDRs secundários inválidos.
2. `make e2e` no GitHub Actions cria o PostgreSQL local com volume de base backup e WAL separado.
   `scripts/local/pitr-drill.sh` grava registros de prova, produz backup físico com manifesto,
   rejeita cópia corrompida com `pg_verifybackup`, apaga um registro depois de um restore point,
   restaura numa instância isolada e confere os registros e o tempo de recuperação. O banco do app
   não é trocado durante essa prova. O CI registra o resultado, inclusive falha.
3. O DX03v2 coordena a prova do app, do PVC do Velero e a simulação local A/B com fencing, troca de
   endpoint e retorno. Consulte o PR R9 do par antes de considerar R9 completo.

O Velero protege objetos e volumes Kubernetes conforme a configuração do app. O PostgreSQL gerenciado
usa o backup nativo da Cloud SQL; restaurar só ConfigMap pelo Velero não é prova de recuperação de dados.
Os buckets Velero são regionais. Um bucket secundário vazio não significa que os objetos do primário
tenham sido replicados: o runbook do app precisa provar a cópia e o checksum na região de destino.

## Restore isolado de Cloud SQL (quando o operador habilitar a conta)

1. Anote projeto, região, nome da instância, início/fim da janela PITR, último backup completo e
   custo de uma instância temporária. Pare gravações se o problema também afetar o banco atual.
2. Restaure por PITR para uma **nova** instância em vez de sobrescrever a principal. Consulte
   [PITR oficial](https://cloud.google.com/sql/docs/postgres/backup-recovery/pitr) para o comando/API
   da versão instalada. O processo de recuperação cria uma instância separada e seu próprio endpoint.
3. Conecte por TLS/PSC, cheque `pg_isready`, contagens, chaves e marcadores de transação do app.
   Compare o último registro aceito com o ponto escolhido; registre perda observada (RPO) e segundos
   até a primeira transação válida (RTO). Não declare RPO zero sem evidência.
4. Faça a troca do segredo/endereço apenas após migrações e compatibilidade da versão do app. A
   credencial write-only e o contrato não devem aparecer em logs. Se a validação falhar, mantenha o
   endpoint original e remova a instância temporária após revisar os dados.

## Failover regional e retorno

O operador precisa de aprovação humana explícita, número de incidente e registro de quem controla
o único escritor. Antes de promover, confirme que o app não consegue mais gravar na principal:
interrompa deploys e entradas de escrita do primário, desligue ou isole o escritor antigo por um
mecanismo verificável e observe o estado da réplica e o atraso. **Se não for possível comprovar o
fencing, não promova**: dois escritores divergentes não têm failback seguro.

Depois do fencing, siga o procedimento oficial de
[promoção de réplica cross-region](https://cloud.google.com/sql/docs/postgres/replication/cross-region-replicas).
Confirme que a réplica saiu do modo read-only, registre o último marcador replicado, habilite o
backup/PITR da nova principal e revise o plano Terraform **antes** de aplicar: a configuração
original da réplica não pode ser reaplicada cegamente depois da promoção. O DX03v2 usa o contrato
`tx03v2-lab-dr-contract`, o registry regional e os segredos `tx03v2-lab-dr-*` para implantar o app
na região secundária. Libere tráfego só após health check, consultas e uma escrita idempotente de
prova. Meça RPO/RTO e o custo de transferência.

Para voltar, trate a antiga principal como origem obsoleta; nunca ligue os dois escritores. Crie
uma réplica nova da principal promovida na região original, espere `replica_lag` ficar dentro do
limite aceito, faça switchover planejado com escrita congelada, valide dados e restaure o roteamento.
Mantenha o registro do incidente, os hashes dos volumes restaurados e a topologia final. Destrua
recursos temporários somente após o aceite dos dados e a conferência de sobras/custos.

## Fontes

- [HA regional e seus limites](https://cloud.google.com/sql/docs/postgres/high-availability)
- [Replicação e custos de transferência](https://cloud.google.com/sql/docs/postgres/replication)
- [Promoção cross-region](https://cloud.google.com/sql/docs/postgres/replication/cross-region-replicas)
- [Preços da Cloud SQL](https://cloud.google.com/sql/pricing)
