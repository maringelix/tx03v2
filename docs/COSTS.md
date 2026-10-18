# Lab costs

R9: `db_profile=dr` uses GCS multiregion `US` for primary backups and a recovery
identity with read access to that bucket. `state_location=US` is optional during
the first bootstrap. Include multiregion storage, retained CSI snapshots,
cross-region traffic and duplicated observability PVCs in the estimate. The
secondary uses its own bucket for new backups. Removing a Kubernetes object does
not automatically remove snapshots with `Retain`; inspect them during teardown.

Hourly, daily and forgotten-month estimates for the lab defaults in `us-central1`,
to support a decision before creating anything. All figures are **list prices
read from Google Cloud pricing pages on 2026-10-16** (USD, excluding taxes, credits
and data transfer): estimates, never verified against an invoice. Your billing
account may use a different currency; bootstrap budgets use that currency.
None of this has been measured: v2 has never run in the cloud
(`not run in the cloud (v2)`).

## Component estimate (core profile, us-central1)

| Component | Lab usage (default) | Reference price | USD/hour | USD/day | USD/forgotten month (730 h) |
|---|---|---|---|---|---|
| GKE cluster management fee | 1 Autopilot cluster | USD0.10/h; USD74.40/month free-tier credit per billing account (one Autopilot or zonal cluster) | 0.100 (0 with free tier) | 2.40 (0) | 73.00 (0) |
| Autopilot pods (general-purpose) | 550m CPU / 1280MiB requests: app (300m/512Mi), ESO (200m/512Mi), Collector (50m/256Mi) | USD0.0445 per vCPU-hour, USD0.0049225 per GiB-hour | ~0.031 | ~0.74 | ~22.36 |
| Cloud SQL `db-g1-small` (ENTERPRISE, zonal) | 1 instance | USD0.035/h | 0.035 | 0.84 | 25.55 |
| Cloud SQL SSD | 10 GB | USD0.000232877 per GiB-hour | 0.002 | 0.06 | 1.70 |
| Cloud SQL backup | 1 retained backup (up to ~10 GB) | USD0.000109589 per GiB-hour | up to 0.001 | up to 0.03 | up to 0.80 |
| Global external Application Load Balancer (Gateway) | 1 forwarding rule | first 5 rules: USD0.025/h; plus data processing per GiB | 0.025 | 0.60 | 18.25 |
| Cloud Armor Standard | 1 policy, 3 rules (two WAF rules and default) | USD0.006849315/h per policy, USD0.001369863/h per rule, USD0.75 per million requests | ~0.011 | ~0.26 | ~8.00 |
| Cloud NAT | 2–3 nodes, 1 NAT IP | USD0.0014/h per VM (up to 32), USD0.045/processed GiB, NAT IP USD0.005/h | ~0.009 | ~0.22 | ~6.70 |
| Private Service Connect endpoint (Cloud SQL) | 1 endpoint | ~USD0.01/h plus data processing | 0.010 | 0.24 | 7.30 |
| Static external IP `tx03v2-lab-gateway` | 1 global address | no charge while attached to a forwarding rule; charged when reserved but unused | small | small | small (between apply and deploy) |
| Cloud DNS (private zone), Secret Manager, Parameter Manager, Artifact Registry, Cloud Logging | 1 zone, 2 secrets, 1 parameter, 2 images per commit, GKE logs | cents/month for DNS; free allowances: 6 secret and 6 parameter versions, 0.5 GB registry, 50 GiB logs per project | ~0 | ~0 | cents |
| Cloud Trace (app traces through OpenTelemetry Collector, contract v2) | lab volume (thousands of spans per run) | USD0.20 per million spans beyond 2.5 million/month per billing account ([Google Cloud Observability pricing](https://cloud.google.com/products/observability/pricing), checked 2026-10-14) | ~0 | ~0 | ~0 |
| State bucket, VPC, Cloud Router, IAM, Workload Identity Federation, budget | — | no material charge | 0.000 | 0.00 | 0.00 |
| **Total with GKE free tier** | | | **~0.12** | **~2.98** | **~91** |
| **Total without free tier** | | | **~0.22** | **~5.38** | **~164** |
| Without WAF (`enable_waf = false`) | | | (~0.011 less) | (~0.26 less) | (~8 less) |

## Full profile and managed alternative (R4.2 and R4.7)

`platform-sizing` downloads and renders charts pinned in `platform/full/charts.txt`,
includes core External Secrets Operator and sums `requests` from
Deployments/StatefulSets and Prometheus/Alertmanager resources. The platform total
**excludes the dx03v2 app**. App requests come from current dx03v2 values: two API
replicas (100m/128Mi each) and two web replicas (50m/64Mi each). Pricing uses GKE
Autopilot general-purpose rates in us-central1 without discounts, checked
2026-10-16 on the [official GKE pricing page](https://cloud.google.com/kubernetes-engine/pricing).

| Profile | Platform, including ESO and Collector | App dx03v2 | Estimated total requests | Pods per hour | Lab total with free tier | Total without free tier |
|---|---:|---:|---:|---:|---:|---:|
| core | 250m CPU / 768MiB RAM | 300m CPU / 512MiB RAM | 550m CPU / 1280MiB RAM | ~USD0.031 | ~USD0.12 | ~USD0.22 |
| full | 1360m CPU / 3856MiB RAM | 300m CPU / 512MiB RAM | 1660m CPU / 4368MiB RAM | ~USD0.095 | ~USD0.18 | ~USD0.28 |

The `full` total keeps the other components from the main table and replaces only
core pod cost. R8 adds items outside the harness request sum:

| R8 item (`full` profile) | Assumption | USD/hour |
|---|---|---:|
| Cloud Service Mesh sidecars in 4 app pods | 100m CPU / 128MiB per sidecar (Istio default; managed proxy value unconfirmed) = 400m / 512MiB | ~0.020 |
| `standard-rwo` PVCs (balanced Persistent Disk) | 36 GiB (Prometheus 12, Alertmanager 2, Grafana 2, Loki 10, Tempo 10) at ~USD0.10/GiB-month | ~0.005 |
| Public Cloud DNS zone, managed certificate and Certificate Map | 1 zone (~USD0.20/month plus queries); no confirmed public managed-certificate list charge | ~0.000 |
| Managed Cloud Service Mesh | **price unconfirmed**: its pricing page could not be read during this review; check <https://cloud.google.com/service-mesh/pricing> before enabling `enable_managed_mesh` | excluded |

Including these items except mesh, `full` is roughly **USD0.21/hour with available
cluster credit and USD0.31 without**. A three-hour run is about USD0.64 or USD0.94;
730 hours is about USD155 or USD228. These request estimates exclude taxes,
traffic, Velero backup storage and Autopilot adjustments for minimum CPU/memory
ratios. GKE Autopilot manages node count and size; this profile accepts neither
`node_instance_types` nor `node_desired_size`. The request-summing script's node
argument does not change the GCP result because its render has no DaemonSet.

The example/bootstrap monthly budget changed from USD10 to **5** (billing-account
currency). At the dollar rates above, `full` reaches 50%/100% alerts after about
8/16 hours without free tier or 12/23 hours with it. Budgets alert; they do not
stop resources.

### In-cluster versus managed observability

`full` chooses in-cluster Prometheus/Alertmanager/Grafana, Loki/Alloy and Tempo.
The four backend renders sum to 175m CPU / 1056MiB RAM, about USD0.013/hour or
USD0.039/three hours at the Autopilot rates above. OpenTelemetry Collector and
other components remain in the platform sum. This path can prove scrapes, rules
and Alertmanager delivery, Loki log queries, Tempo traces/spanmetrics and Grafana
correlation.

For a comparable Google-managed scenario, assume three hours, 100 Prometheus
series sampled every 15 seconds (72,000 samples), 100MiB logs and 100,000 spans.
Managed Service for Prometheus costs about USD0.00432 at USD0.06/million samples;
logs remain below 50GiB/month/project and traces below the first 2.5 million
spans/billing account, if those allowances remain unused. Managed ingestion in
this scenario costs about **USD0.004/run**, plus the required collectors' requests.
It proves arrival and queries in Cloud Monitoring, Cloud Logging and Cloud Trace,
but does not prove Loki, Tempo, Grafana or the local Alertmanager receiver.
Rates/allowances were checked 2026-10-16 on the
[official Cloud Observability pricing page](https://cloud.google.com/products/observability/pricing).
This volume is a reproducible assumption, not a lab measurement.

Assumptions: dx03v2 app with two API and web replicas (API HPA may reach four);
2–3 node VMs to estimate Cloud NAT (Autopilot chooses the count); lab traffic
(cents of data processing and Cloud Armor requests); logs within allowance.
If Cloud Armor's default rule is unbilled, the policy costs ~USD7/month rather
than ~USD8.

Quick estimates:

- A three-hour `core` run is about USD0.37 with free tier or USD0.67 without;
  `full` is USD0.64 or USD0.94, plus data, backup storage and excluded mesh pricing.
- Left running, `core` costs about USD2.98/day with free tier or USD5.38 without;
  `full` costs USD5.11 or USD7.51. Over 730 hours, `full` is roughly USD155 or
  USD228. With a USD5 budget, the 50% alert arrives in hours, not days.
- Without free tier, cluster fees dominate (~45%), followed by Cloud SQL (~17%)
  and load balancing (~11%). With free tier, Cloud SQL (~32%), pods (~22%) and
  load balancing (~21%) dominate.
- Budgets never stop spending: destroy the same day.

## GKE free tier

The GKE pricing page read on 2026-10-16 lists a USD0.10/hour cluster management
fee and USD74.40/month credit per billing account, sufficient for one Autopilot
or zonal cluster all month (regional Standard clusters are excluded). The lab's
regional Autopilot cluster qualifies **provided no other cluster on that billing
account already consumes the credit**. Only an invoice confirms this: on the
first cloud run, group costs by SKU in Cloud Billing, record the cluster fee and
corresponding credit in `cloud_run_report`, then update this section.

## Cloud SQL sizing

### Optional continuity profiles (R9)

`db_profile=core` preserves the main table. `ha` defaults to `db-custom-1-3840`
with one dedicated vCPU and 3.75 GiB RAM. At undiscounted `us-central1` prices,
HA compute costs **USD0.0826 + 3.75 × USD0.014 = USD0.1351/h**, versus USD0.035/h
for zonal shared-core. Regional 10 GiB SSD is approximately
10 × USD0.000465753 = **USD0.00466/h**, versus USD0.00233/h zonal. Seven backups
do not mean seven complete copies: usage depends on changed blocks. As a teaching
upper bound of 70 GiB stored, 70 × USD0.000109589 = **USD0.00767/h**; WAL, traffic
and restore operations depend on actual use. Compute and SSD alone add about
**USD0.1024/h** or **USD74.75/730 h** over `core`.

`dr` adds a zonal `db-custom-1-3840` replica in `us-east1`. Using `us-central1`
rates as a planning assumption, compute is 1 × USD0.0413 + 3.75 × USD0.007 =
**USD0.06755/h**, plus SSD, PSC endpoint, NAT, bucket, registry and replication
egress. The **second** Autopilot management fee is **USD0.10/h** (USD73/730 h);
the billing account's USD74.40/month credit may already be consumed by the primary.
Even with no app pods, estimate at least **~USD0.19/h above `ha`** for cluster,
replica, SSD, PSC and NAT. Standby pod CPU/memory, logs, backups, registry, egress
and taxes are excluded. A forgotten 730-hour `dr` adds **~USD139 or more** to `ha`.

These figures are reference calculations, not invoices or cloud validation. Check
regional/currency rates at [Cloud SQL pricing](https://cloud.google.com/sql/pricing),
[GKE pricing](https://cloud.google.com/kubernetes-engine/pricing) and
[Cloud SQL replication](https://cloud.google.com/sql/docs/postgres/replication)
before apply. `db_deletion_protection=true` prevents destroy until reverted;
backups retained by `db_retain_backups_on_delete=true` keep incurring charges.

The default is ENTERPRISE `db-g1-small`: PostgreSQL 16+ defaults to Enterprise
Plus, while shared-core tiers exist only in Enterprise (`docs/LESSONS_LEARNED.md`,
lesson 12). The assumed default `max_connections` for `db-g1-small` is 50, based
on the Cloud SQL quotas page (recheck quarterly), enough for up to four API
replicas × `DB_POOL_MAX` 10 plus migrations. `db_tier` validation rejects
`db-f1-micro` (25 connections) and Enterprise Plus tiers (`rejects_db_f1_micro`,
`rejects_an_enterprise_plus_tier`); it accepts Enterprise `db-custom-*` and
`db-n1-*`, which cost several times more: recalculate before changing. A 10 GB
disk without autoresize, zonal placement, one retained backup and no PITR keep
other costs low.

## v1 scenarios (GCP, tx03 notes)

The v1 notes (`docs/LESSONS_LEARNED.md`, lessons 2–5 and 12) are comparisons, not
current budgets; several were fixed text unsupported by billing data:

| v1 scenario | Figure in the notes |
|---|---|
| "Current" cost generated by the cost workflow | USD60–70/month, "65% of USD100 budget" (the budget did not exist) |
| Load balancers | ~34% of cost, ~USD18/month per forwarding rule, 3 forwarding rules |
| Prometheus, Grafana and Alertmanager | USD26–40/month plus 17 Gi PVC |
| Orphans after destroy | USD15–25/month if forgotten |
| Cloud SQL `db-perf-optimized-N-2` (Enterprise Plus) | ~USD150/month |
| Savings "quick wins" | −USD38–48/month (60%), never measured |

The lesson still applies: every forwarding rule and add-on costs money each
month. v2 has one Gateway; core uses ESO and OpenTelemetry Collector, while full
adds the Autopilot-compatible add-ons above, persistent observability disks
(removed during uninstall) and managed mesh. Destroy ends with a leftovers check.

## Tips

- Destroy the same day and run `scripts/leftovers.sh` locally as project Owner
  until nothing is `BILLABLE` (`docs/RUNBOOK.md`). Deleting the dedicated project
  is the strongest final cleanup.
- `enable_waf = false` saves ~USD0.011/h but leaves the app without WAF; dx03v2
  deploys without GCPBackendPolicies when `waf/security-policy` is `none`.
- Autopilot bills pod requests: more replicas or larger requests change the bill
  (ESO uses limits equal to requests).
- GKE free tier belongs to the entire billing account; another cluster may use it.
- The reserved global address is charged while unattached to a forwarding rule
  (between apply and dx03v2 deploy); `terraform destroy` deletes it.
- Trial credits obscure the invoice: inspect Cloud Billing reports within the
  first hours of each run and retain budget alerts.

## R10: capacity and FinOps

See [FinOps and scaling](FINOPS.md) for kind HA, load/HPA/PDB, OpenCost, VPA Off,
opt-in Spot, regional rates, budget/expiry and cleanup. Built for forks; not run
in the cloud (v2).
