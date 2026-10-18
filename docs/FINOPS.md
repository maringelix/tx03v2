# R10 — scaling, capacity and FinOps

## Status and prerequisites

Built for forks; no GCP v2 operation has run in the cloud.
CI runs Docker. The cloud commands below require a run authorized by the fork's
owner, using their own domain/account and budget. FinOps is opt-in with profile
`full`. The default local path still uses one node; the capacity experiment uses
three kind nodes and recommends 12 GiB available to Docker. Do not combine HA
with `LOCAL_SIZE=small`.

## Local lesson: HPA, PDB and interruption

On Linux/a devcontainer, run:

    make tools
    LOCAL_TOPOLOGY=ha LOCAL_FINOPS=1 make e2e

`scripts/local/capacity-drill.sh` creates an exclusive namespace and refuses to
adopt an existing one. A Node fixture pinned by digest generates CPU load in a
worker thread while HTTP stays responsive. The probe requires HPA 1 → 3 → 1
under bounded load, refusal to evict the last pod under its PDB, draining a worker
owned by kind and rescheduling the three pods onto the remaining nodes. The drain
selects only the fixture; it does not remove persistent platform pods.

The client accesses the Service during the drain and measures errors <=1% and
p99 <=1 s, without forwarding a pod port. Cleanup always uncordons the node and
removes the created namespace. Failures show pods/HPA/PDB/VPA/events without
printing Secrets. The JSON report contains measurements and acceptance criteria.
The preceding mesh, backup, PITR, observability, policy and Chaos probes remain
mandatory.

VPA must produce a recommendation while retaining `updateMode: Off` and the
original requests. OpenCost must return a measured positive cost for the fixture
namespace through `/allocation`. The probe retries for up to five minutes (seven
attempts, 30 s intervals and a 15 s HTTP timeout), because scrapes and allocation
model convergence are asynchronous. The first response without a positive cost
still fails the assertion; exhausting retries fails with diagnostics containing
only synthetic cost metadata. This correction ports the behavior already used
by the AWS pair after a pre-existing GCP R10 convergence failure. The dx03v2 local
pin must follow that commit after merge (`family-ref` guardrail).
Local rates are a deterministic simulation, explicitly identified in
`platform/finops/pricing/local.json`.

## GKE Autopilot and Spot

Autopilot provisions capacity from pod requests and already provides VPA. We do
not install another cloud VPA controller, only the Off object. HPA scales replicas;
VPA recommends requests; managed capacity remains a separate proof. Without cloud
validation, we claim neither scaling time nor savings.

`platform/finops/manifests/spot-job.yaml` is a finite lesson with requests, limits,
a deadline and TTL. It requires Spot; availability is not guaranteed. Never move
PostgreSQL, Argo CD, monitoring or the critical replica minimum into this Job.
During an authorized run, apply the Job and observe events, the chosen node and
completion. If Spot capacity leaves it Pending, cancel it and run the same task
in a differently named Job, removing Spot `nodeSelector`/tolerations. To require
on-demand capacity, add required nodeAffinity with key `cloud.google.com/gke-spot`
and operator `DoesNotExist`. Record the decision, deadline and cost; do not leave
the attempt pending. A kind result cannot establish real Spot interruption or
GKE node scaling behavior.

## Rates and installation

OpenCost chart 2.5.33 / app 1.121.3 and VPA chart 0.14.0 / app 1.8.0 have archive
SHA256 checksums and image pins in `platform/finops/versions.env` and values files.
The API is ClusterIP; UI/MCP/cloud billing ingestion are disabled. The exporter
uses configured rates and the existing Prometheus, without billing credentials.

For the cloud, provide `FINOPS_PRICING_FILE`: JSON with `cloud=gcp`, `region` equal
to the selected region, `currency=USD`, `mode=estimate`, an HTTPS `source`, `asOf`
reviewed within 31 days, `description`, and `cpuPerCoreHour`, `ramPerGiBHour` and
`storagePerGiBHour` as positive decimal strings. Consult current provider prices;
do not reuse the local simulation as a quote. Spot uses the on-demand rate as a
conservative upper bound.

During an authorized run, the installer accepts `--profile full --finops`.
The `platform` workflow has input `finops` and reads rates from variable
`LAB_FINOPS_PRICING_JSON`. Secondary requires rates for the secondary region.
Wrong/stale values fail. The Grafana "Lab FinOps" dashboard shows CPU/RAM by
namespace and explains idle/shared costs. Compare
`/allocation?window=1h&aggregate=namespace&includeIdle=true` and
`aggregate=label:cost_lab_owner` for showback. Owner/environment labels are
mandatory in lessons; each DX checks its own manifests and rightsizes under an SLO.

## Estimate before apply and expiry

`terraform-plan` and `terraform-apply` call `scripts/cost-workflow.sh` after saving
`tfplan`; apply occurs only if the gate passes. Configure `LAB_FINOPS_PRICING_JSON`,
`LAB_COST_BUDGET_USD`, `LAB_COST_HOURS` (<=24) and `LAB_COST_EXPIRES_AT` (UTC within
the next 24 hours). Update the deadline for each run. The deadline must fit inside
the budgeted duration. These public inputs contain no identifiers.

To prepare the review worksheet outside CI:

    umask 077
    terraform -chdir=terraform/envs/lab show -json tfplan > /tmp/plan-private.json
    bash scripts/cost-pricing-template.sh gcp us-central1 /tmp/plan-private.json /tmp/rates.json

The worksheet is deliberately incomplete: fill every type with a per-resource
hourly cost at the LARGEST planned configuration (HA/DR, maximum nodes, database
sizes). Use zero only for unbilled/already included types, with a justification.
The gate rejects unpriced types. It also requires external categories `backup`,
`controlPlane`, `database`, `dr`, `egress`, `loadBalancer`, `nat`, `storage` and
`waf`, including justified zeros to avoid double counting. This covers costs
created by controllers outside Terraform. OpenCost CPU/RAM/disk rates and the
plan inventory complement each other; do not add the reports as independent bills.

Plan JSON may contain secrets and must never become a public artifact. The report
shows only types, counts, rates, source/date, total, budget and expiry. CI fixtures
prove arithmetic and rejection of expensive scenarios, stale rates and unpriced
resources. They are not GCP prices.

A budget is an alert and this gate is an estimate; neither caps billing. Expiry
blocks new plans/applies after the deadline and requires destruction at lesson
end; it does not create a credentialed robot to destroy accounts. Use existing
teardown, inspect leftovers and record backup/state retention that continues to
incur charges. Stop load at the deadline even if the exercise fails.

## Diagnosis and limits

No HPA: inspect metrics-server, requests and `ScalingActive`. No rescheduling:
inspect cordon, PDB, affinity, quotas and events. VPA Off never changes requests
itself. No allocation: inspect ServiceMonitor, Prometheus targets, the sampling
window, exporter read permissions and rates. Without reviewed regional rates, the
gate fails. Compare load/SLO before and after; lowering requests alone is no proof
of savings.

Read [OpenCost Helm](https://opencost.io/docs/installation/helm/),
[allocation API](https://opencost.io/docs/integrations/api-examples/),
[GKE VPA](https://cloud.google.com/kubernetes-engine/docs/how-to/vertical-pod-autoscaling)
and [Autopilot Spot](https://cloud.google.com/kubernetes-engine/docs/how-to/autopilot-spot-pods).

### External cost, idle and owner in the dashboard

The rates file also requires `externalHourly` with `backup`, `controlPlane`,
`database`, `dr`, `egress`, `loadBalancer`, `nat`, `storage` and `waf` (USD/h).
Zero requires an inclusion/absence justification; avoid counting the same cost
in a Terraform resource and an external category. The installer creates recording
rule `lab_external_hourly_estimate`; the dashboard shows categories,
owner/environment, shared infrastructure and estimated idle. Kube-state-metrics
exposes only the two additional showback labels. Local simulation uses zero
external costs; the fork owner fills cloud rates.

LimitRange fills missing limits before quota admission (CPU 1, RAM 512Mi per
container; default requests 10m/64Mi). Explicit requests/limits, including proxy
resources, are preserved. Quotas remain enforcing.

For a DR plan, estimate the largest SKU and highest rate among the covered regions;
record that choice in the source description. In Autopilot, node idle is a capacity
model rather than idle VM billing: allocation uses pod requests.
