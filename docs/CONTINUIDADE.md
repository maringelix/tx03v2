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
3. O TX prova a restauração real de bytes do PVC com nova claim; o DX coordena a prova
   A/B do app, com fencing, troca de endpoint e retorno. Os CI de R9 registram ambos;
   a execução nos serviços gerenciados permanece não executada em nuvem (v2).

O Velero protege objetos e volumes Kubernetes conforme a configuração do app. O PostgreSQL gerenciado
usa o backup nativo da Cloud SQL; restaurar só ConfigMap pelo Velero não é prova de recuperação de dados.
No perfil DR, o bucket primário fica na multirregião US e o secundário tem destino próprio.
O standby importa a origem como somente leitura; snapshots nativos PD têm escopo global.
Um destino vazio não comprova recuperação: verificar backup, snapshot/dados e checksum
continua obrigatório na homologação gerenciada.

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

## PVC: restauração dos bytes pelo Velero

O CI local executa `scripts/local/volume-restore-drill.sh`: um Pod restrito grava um arquivo
num PVC ligado a um volume `local` no nó kind. O backup por Kopia deve terminar com um
`PodVolumeBackup Completed`. O ensaio remove namespace, PVC e PV, apaga os bytes originais e
restaura tudo. Só passa com um novo UID de PVC, `PodVolumeRestore Completed` e SHA256 idêntico.

O `node-agent` local precisa de root e dos hostPaths do kubelet para ler os volumes. Por isso
somente o namespace Velero local passa a `privileged`; o servidor continua non-root e a aplicação
continua com Pod Security `restricted`. O restore helper tem imagem fixada por digest, UID/GID
65532, capabilities removidas e filesystem raiz somente leitura. Não relaxe a segurança do app
para instalar o agente. Uma senha aleatória do repositório Kopia é criada antes do primeiro backup
e preservada nas reinstalações; perdê-la torna os dados antigos ilegíveis.

Este agente com hostPath é específico de kind; GKE Autopilot usa o caminho CSI. A prova local
não substitui o ensaio de snapshot/restore do driver CSI da cloud, que continua não executado.
Veja [FSB no Velero 1.18](https://velero.io/docs/v1.18/file-system-backup/).

## Preparar e operar o secundário

O caminho DR deste lab usa duas regiões dos EUA (`us-central1` e `us-east1` por padrão).
O backup primário passa a GCS multirregião `US`, com acesso independente da região
original. A identidade `velero-dr` lê esse bucket com `storage.objectViewer` e grava
somente no bucket próprio do secundário. Sua BSL `primary-recovery` é `ReadOnly`.
Considere a janela de replicação do GCS; multirregião não promete RPO zero para um
objeto recém-gravado. Antes de simular perda, confira a disponibilidade e o checksum
do último backup no destino de recuperação.

Antes do **primeiro bootstrap**, use `state_location = "US"` para manter também o
state remoto versionado em multirregião. O padrão regional do perfil barato continua
disponível. Um bucket existente não muda de localização: não aceite um plano que
substitua seu state; migre o backend de forma deliberada, guarde uma cópia privada e
confira lineage/serial/recursos antes de liberar outro apply. O bucket continua com
versioning, prevenção de acesso público, `force_destroy=false` e proteção de exclusão.
Para recuperar uma versão anterior, liste as gerações do objeto `envs/lab/default.tfstate`,
baixe a geração escolhida com acesso somente leitura para um diretório privado fora
do clone público, confira o JSON/lineage/serial e compare um plano de refresh.
Nunca publique o state em artifact, issue ou PR nem faça `state push` sem revisão.

O contrato DR mantém os mesmos 18 campos; TLS e WAF usam recursos globais do projeto.
O segundo cluster recebe sua própria associação ao Cloud Service Mesh gerenciado.
Os schedules usam nomes distintos (`lab-daily` e `lab-daily-dr`) para que o
catálogo importado do primário não colida com backups produzidos pelo secundário.
Depois de aplicar a IaC e de conferir a região, instale a plataforma com:

```bash
GCP_PROJECT_ID=tx03v2-lab-example \
  bash platform/install.sh --profile full --github-owner your-github-user --target secondary
```

O renderer usa `gitops/gcp-dr`. O deploy do par oferece `target=secondary`, lê os
segredos regionais e verifica HTTPS diretamente no endereço reservado antes do DNS.
Somente após fencing, promoção, aceite dos dados e smoke, `active_region=secondary`
(`LAB_ACTIVE_REGION`) troca o registro A. Esse input não promove o banco sozinho.
O destroy inventaria e desinstala ambos os clusters antes de remover a IaC; cada
uninstall espera apenas os NEGs de sua região.

No GKE, `EnableCSI` e a classe `lab-pd-snapshot` usam o driver gerenciado de PD,
sem hostPath de usuário. O schedule diário inclui app/monitoring com retenção de
35 dias. Antes do restore noutra região, confirme que o snapshot durável do Compute
Engine está disponível, restaure para volumes novos e compare o checksum do arquivo;
não confunda um objeto PVC restaurado com os dados. Confira e limpe snapshots
retidos depois do aceite; `deletionPolicy: Retain` evita que apagar uma referência
Kubernetes destrua sua cópia de recuperação. Estes passos gerenciados não rodaram na v2.

## Fontes

### Credenciais e sinais de recuperação

O apply protegido executa `scripts/sync-dr-secrets.sh` depois da IaC no perfil DR.
Ele lê os valores **atuais** do primário, altera somente o hostname do JSON do banco
para o FQDN da réplica e grava o secundário apenas se o conteúdo mudou. Isso também
funciona quando DR é habilitado depois do core/HA. Terraform cria os contêineres de
segredo DR, sem publicar uma senha efêmera nova que não pertence ao banco existente.
Somente a identidade de apply recebe acesso aos quatro segredos exatos; plan e
deploy continuam sem leitura de valores. Os arquivos temporários são privados,
apagados no término e nunca enviados como artifacts. No apply manual, execute o
mesmo script com `--db-host "$(terraform -chdir=terraform/envs/lab output -raw dr_db_hostname)"`.
Após rotação, repita o apply/sync antes de aceitar o standby.

O ServiceMonitor do Velero alimenta os alertas `LabBackupTooOldOrMissing` (30 h)
e `LabRestoreFailed`, encaminhados ao Slack quando o webhook da plataforma foi
configurado. A política nativa de Cloud Monitoring acompanha o lag da réplica
(mais de 60 s durante 5 min), independentemente do cluster primário. Para receber
notificação fora do console, informe nomes de canais existentes do próprio projeto
em `continuity_notification_channels` / `LAB_CONTINUITY_NOTIFICATION_CHANNELS`
(lista JSON). Não coloque tokens de canais no state. Um alerta saudável não
substitui os ensaios de restore: registre data, checksum, perda observada e RPO/RTO.

O ensaio de PVC local apaga o PV original e seus bytes; provisiona um PV local
vazio com outro nome, como um disco substituto, e exige um PVC novo vinculado a ele.
Velero/Kopia deve recuperar os bytes com o mesmo SHA256 e um PodVolumeRestore
Completed. A provisão do disco é separada da restauração do seu conteúdo.

## Referências operacionais

- [HA regional e seus limites](https://cloud.google.com/sql/docs/postgres/high-availability)
- [Replicação e custos de transferência](https://cloud.google.com/sql/docs/postgres/replication)
- [Promoção cross-region](https://cloud.google.com/sql/docs/postgres/replication/cross-region-replicas)
- [Preços da Cloud SQL](https://cloud.google.com/sql/pricing)
