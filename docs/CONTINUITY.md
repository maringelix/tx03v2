# Data continuity — R9 (Google Cloud)

This chapter is a runbook for a **fork**. Infrastructure code and Terraform tests
use mock providers; no apply, restore or failover has run in Google Cloud v2.
The local Docker exercise tests physical PostgreSQL recovery, but does not prove
Cloud SQL HA, cross-region replication or actual promotion time. Read
[costs](COSTS.md) before changing profiles.

## Profiles and limits

| `db_profile` | Primary database | Secondary region | Use |
|---|---|---|---|
| `core` (default) | Cloud SQL Enterprise `db-g1-small`, zonal, 1 backup, no PITR | none | learn at the lowest cost |
| `ha` | `db-custom-1-3840`, regional, PITR, 7 backups and 7 days of WAL | none | zone failure and isolated restore |
| `dr` | same as `ha` | asynchronous Cloud SQL replica, VPC, GKE Autopilot, Artifact Registry, secrets, Parameter Manager and Velero bucket in another region | regional-loss exercise and promotion with human approval |

`dr_region` defaults to `us-east1` and must differ from `region`. Secondary CIDR
ranges are private and separate within the secondary VPC. The secondary cluster
starts incurring costs on apply even before deploying the app. `ha_db_tier` must
use dedicated CPU; shared-core instances have no HA SLA. `db_backup_count`
selects retention (1 for `core`, 7 for HA/DR unless a valid explicit value is set).
`db_deletion_protection` and `db_retain_backups_on_delete` are opt-in: both improve
protection but require deliberate disabling or billing review before destroy.

Cloud SQL HA replicates across zones within one region. The DR replica crosses
regions **asynchronously**; failover may lose recent transactions. The second
region's cluster and secrets are independent resources, but promotion and traffic
switching are **not** automatic. `dr` creates the replica and isolated PSC endpoint.
After promotion, validate backups/PITR on the new primary before reopening writes.

## Proofs without the cloud

1. `terraform -chdir=terraform/envs/lab init -backend=false -lockfile=readonly` and
   `terraform -chdir=terraform/envs/lab test`: `continuity.tftest.hcl` verifies
   that `core` does not pay for a second region, `ha` does not create DR and `dr`
   connects the replica to the primary and publishes independent resources.
   `validations.tftest.hcl` rejects equal regions, shared-core HA, short retention
   and invalid secondary CIDRs.
2. `make e2e` in GitHub Actions creates local PostgreSQL with separate base-backup
   and WAL volumes. `scripts/local/pitr-drill.sh` writes proof records, produces
   a physical backup with a manifest, rejects corruption with `pg_verifybackup`,
   deletes a record after a restore point, restores into an isolated instance
   and verifies records and recovery time. This proof does not replace the app's
   database. CI records its result, including failure.
3. TX proves actual PVC-byte recovery onto a new claim; DX coordinates the A/B
   application proof with fencing, endpoint changes and failback. R9 CI records
   both; managed-service execution remains not run in the cloud (v2).

Velero protects Kubernetes objects and volumes according to app configuration.
Managed PostgreSQL uses native Cloud SQL backups; restoring only a ConfigMap with
Velero is not data-recovery evidence. In DR, the primary bucket uses multiregion
US and the secondary has its own destination. Standby imports the source read-only;
native PD snapshots have global scope. An empty destination proves no recovery:
backup, snapshot/data and checksum verification remain mandatory during managed
validation.

## Isolated Cloud SQL restore (when the operator enables the account)

1. Record project, region, instance name, PITR window start/end, last full backup
   and temporary-instance cost. Stop writes if the current database is also affected.
2. Restore through PITR into a **new** instance instead of overwriting the primary.
   Consult [official PITR instructions](https://cloud.google.com/sql/docs/postgres/backup-recovery/pitr)
   for the installed version's command/API. Recovery creates a separate instance
   with its own endpoint.
3. Connect through TLS/PSC and check `pg_isready`, counts, keys and app transaction
   markers. Compare the last accepted record with the chosen recovery point;
   record observed loss (RPO) and seconds to the first valid transaction (RTO).
   Do not claim zero RPO without evidence.
4. Change the secret/address only after checking migrations and app-version
   compatibility. The write-only credential and contract must not appear in logs.
   If validation fails, retain the original endpoint and remove the temporary
   instance after reviewing its data.

## Regional failover and failback

The operator needs explicit human approval, an incident number and a record of
who controls the sole writer. Before promotion, confirm that the app can no
longer write to the primary: stop primary deployments and write ingress, stop
or isolate the old writer through a verifiable mechanism and observe replica
state and lag. **If fencing cannot be proven, do not promote**: divergent writers
have no safe failback.

After fencing, follow the official
[cross-region replica promotion](https://cloud.google.com/sql/docs/postgres/replication/cross-region-replicas)
procedure. Confirm that the replica has left read-only mode, record its last
replicated marker, enable backup/PITR on the new primary and review the Terraform
plan **before** applying. Never blindly reapply the original replica configuration
after promotion. DX03v2 uses `tx03v2-lab-dr-contract`, the regional registry and
`tx03v2-lab-dr-*` secrets to deploy the secondary app. Release traffic only after
health checks, reads and an idempotent proof write. Measure RPO/RTO and transfer cost.

For failback, treat the old primary as stale; never enable both writers. Create a
new replica of the promoted primary in the original region, wait until
`replica_lag` meets the accepted bound, perform a planned switchover with frozen
writes, validate data and restore routing. Retain the incident record, restored
volume hashes and final topology. Destroy temporary resources only after data
acceptance and a leftovers/cost review.

## PVC: restoring bytes with Velero

Local CI runs `scripts/local/volume-restore-drill.sh`: a restricted Pod writes a
file into a PVC backed by a `local` volume on the kind node. Kopia backup must
produce `PodVolumeBackup Completed`. The exercise removes the namespace, PVC and
PV, deletes the original bytes and restores everything. It passes only with a
new PVC UID, `PodVolumeRestore Completed` and identical SHA256.

The local `node-agent` needs root and kubelet hostPaths to read volumes. Therefore
only the local Velero namespace becomes `privileged`; the server remains non-root
and the application retains Pod Security `restricted`. The restore helper is
pinned by digest, runs as UID/GID 65532, drops capabilities and has a read-only
root filesystem. Do not relax app security to install the agent. A random Kopia
repository password is created before the first backup and preserved on reinstall;
losing it makes older data unreadable.

This hostPath agent is kind-specific; GKE Autopilot uses CSI. Local proof does not
replace the cloud CSI driver's snapshot/restore exercise, which remains unrun.
See [Velero 1.18 FSB](https://velero.io/docs/v1.18/file-system-backup/).

## Preparing and operating the secondary

This lab's DR path uses two US regions (`us-central1` and `us-east1` by default).
The primary backup uses GCS multiregion `US`, independently accessible from the
original region. Identity `velero-dr` reads that bucket with `storage.objectViewer`
and writes only its own secondary bucket. Its `primary-recovery` BSL is `ReadOnly`.
Account for GCS replication delay; multiregion storage does not promise zero RPO
for a newly written object. Before simulating loss, verify the latest backup's
availability and checksum at the recovery destination.

Before the **first bootstrap**, use `state_location = "US"` to retain versioned
remote state in multiregion storage too. The inexpensive profile's regional
default remains available. An existing bucket cannot change location: do not
accept a plan replacing your state bucket. Deliberately migrate the backend,
keep a private copy and verify lineage/serial/resources before allowing another
apply. The bucket retains versioning, public-access prevention,
`force_destroy=false` and deletion protection. To recover an older version, list
generations of `envs/lab/default.tfstate`, download the chosen generation read-only
to a private directory outside the public clone, inspect JSON/lineage/serial and
compare a refresh plan. Never publish state in artifacts, issues or PRs, or run
`state push` without review.

The DR contract retains the same 18 fields; TLS and WAF use project-global
resources. The second cluster gets its own managed Cloud Service Mesh membership.
Schedules use distinct names (`lab-daily` and `lab-daily-dr`) so the imported
primary catalog does not collide with secondary backups. After applying IaC
and verifying the region, install the platform with:

```bash
GCP_PROJECT_ID=tx03v2-lab-example \
  bash platform/install.sh --profile full --github-owner your-github-user --target secondary
```

The renderer uses `gitops/gcp-dr`. Paired deployment offers `target=secondary`,
reads regional secrets and checks HTTPS directly at the reserved address before
DNS changes. Only after fencing, promotion, data acceptance and smoke does
`active_region=secondary` (`LAB_ACTIVE_REGION`) switch the A record. This input
does not promote the database itself. Destroy inventories and uninstalls both
clusters before removing IaC; each uninstall waits only for its region's NEGs.

On GKE, `EnableCSI` and class `lab-pd-snapshot` use the managed PD driver without
user hostPaths. The daily schedule includes app/monitoring with 35-day retention.
Before restoring in another region, confirm that the durable Compute Engine
snapshot is available, restore onto new volumes and compare the file checksum;
a restored PVC object is not restored data. Inspect and clean retained snapshots
after acceptance; `deletionPolicy: Retain` prevents deleting a Kubernetes reference
from destroying the recovery copy. These managed steps have not run in v2.

## Credentials and recovery signals

Protected apply runs `scripts/sync-dr-secrets.sh` after IaC in the DR profile.
It reads the primary's **current** values, changes only the database JSON hostname
to the replica FQDN and writes the secondary only when content changed. This also
works when enabling DR after core/HA. Terraform creates DR secret containers
without publishing a new ephemeral password unrelated to the existing database.
Only apply identity receives access to the four exact secrets; plan and deploy
still cannot read values. Temporary files are private, removed on exit and never
uploaded as artifacts. For manual apply, run the same script with
`--db-host "$(terraform -chdir=terraform/envs/lab output -raw dr_db_hostname)"`.
After rotation, repeat apply/sync before accepting standby.

Velero's ServiceMonitor feeds `LabBackupTooOldOrMissing` (30 h) and
`LabRestoreFailed`, routed to Slack when the platform webhook is configured.
Native Cloud Monitoring watches replica lag (>60 s for 5 min), independently of
the primary cluster. To receive notifications outside the console, supply names
of existing channels in the same project through
`continuity_notification_channels` / `LAB_CONTINUITY_NOTIFICATION_CHANNELS`
(JSON list). Do not put channel tokens in state. Healthy alerts do not replace
restore exercises: record date, checksum, observed loss and RPO/RTO.

The local PVC exercise deletes the original PV and bytes, provisions an empty
local PV under another name as a replacement disk, and requires a new bound PVC.
Velero/Kopia must recover bytes with identical SHA256 and
`PodVolumeRestore Completed`. Disk provisioning is separate from content restoration.

## Operational references

- [Regional HA and limits](https://cloud.google.com/sql/docs/postgres/high-availability)
- [Replication and transfer costs](https://cloud.google.com/sql/docs/postgres/replication)
- [Cross-region promotion](https://cloud.google.com/sql/docs/postgres/replication/cross-region-replicas)
- [Cloud SQL prices](https://cloud.google.com/sql/pricing)
