# Local lab

v1 had a complete platform—Istio, Prometheus/Grafana/Alertmanager, Loki, Argo CD,
Gatekeeper, Trivy Operator, backup and Chaos Mesh—but only in the cloud, and much
never actually worked (`docs/LESSONS_LEARNED.md`). This lab builds that platform
in Docker with Terraform and proves each component through traffic or real API
calls. Nothing contacts Google Cloud. It uses the tx01v2 local platform with
tx03v2 names and the Google Cloud equivalents below.

Status: `verified in CI`, job `e2e`; `verified locally` on 2026-10-13 (complete
fresh full run with the then-current 26 probes) and 2026-10-14 (observability,
traces and Slack). `small` is `verified in CI` by dx03v2 `e2e-platform-small`:
full platform plus app, Docker limited to 7 GB. The executable probe list in
`platform/local/check.sh` is authoritative as later rounds add exercises.

v1 stopped at planned regional DR, FinOps, Chaos and OpenTelemetry. Here traces
are exercised through Collector, Tempo, Istio Gateway spans, spanmetrics/exemplars
and Grafana correlation; Chaos has explicit hypotheses for pod kill, latency,
CPU and memory. Slack alerting never stores a webhook in tracked files. Later
continuity/capacity exercises are described in CONTINUITY and FINOPS.

## What is created

`terraform/envs/local` uses `kreuzwerker/docker`4.6, `hashicorp/tls`4.4 and
`hashicorp/random`3.9, with local state outside the repo at
`~/.local/state/tx03v2-local`.

| Google Cloud | Local equivalent | Address |
| --- | --- | --- |
| VPC tx03v2-lab/node subnet | Docker tx03v2-local, 10.252.0.0/24, upper half for nodes/LBs | — |
| Autopilot 1.36REGULAR | kind tx03v2-local, Kubernetes 1.36, kindnet enforcing NetworkPolicy | random127.0.0.1 APIport |
| Artifact Registry dx03v2 | CNCFDistribution3.1.2 registry | localhost:5003 push, registry.tx03v2.local pull |
| Cloud SQL17 ENCRYPTED_ONLY/PSC | PostgreSQL 17 hostssl/SCRAM, plaintext rejected, lab CA certificate | 10.252.0.11, db.tx03v2.local |
| Shared regional Cloud SQLCA | Terraform tls ECDSA P256 lab CA, 30 days | — |
| Cloud Storage backups | VersityS3Gateway1.8.0, S3 API rather than GCS;buckets tx03v2-local-velero/tx03v2-local-db-backups |http://10.252.0.12:7070|
| Managed GKEGateway/globalALB/zonalNEGs | cloud-provider-kind0.12.0, oneEnvoy per LoadBalancerService | upper network half |
| GitHub GitOps source | SoftServe0.12.3, SSHpush/statekey, anonymousHTTPread | 10.252.0.13 |

Names, 10.252.0.0/24 and registry5003 differ from AWS10.250.0.0/24:5001 and
Azure10.251.0.0/24:5002, avoiding address collisions between pairs (memory aside).
Every container/volume has label `tx03v2.lab=local`. Only registry publishes a
host port, on loopback. Terraform generates DB/admin/object-store/Grafana/SSH
credentials into local state; they are machine-local and removed by destroy.

`platform/local/install.sh` installs in this order, with versions/SHA256 in
`platform/local/versions.env` and image digests in `platform/local/values/`:

| Layer | Components | Profile |
| --- | --- | --- |
| core | Gateway API1.6.3 experimental (mesh HTTPRoute retries), Istio1.31.1 ambient istiod/CNI/ztunnel, istio/istio-waypoint classes, cert-manager1.21.2/lab-ca, ESO2.12.0/local-secrets, metrics-server0.9.0, lab-system/lab-contract | all |
| observability | kube-prometheus-stack92.3.0:Prometheus3.15/exemplars, Alertmanager0.34/sink+Slack, Grafana13.2ClusterIP, kube-state-metrics, node-exporter;Loki3.6single-binary, Alloy1.20, Tempo3.1single-binary, Collector0.162OTLP→Tempo/spanmetrics, IstioTelemetry Gateway spans | observability, full |
| operations | ArgoCD3.5.5, Gatekeeper3.23.1/policies, TrivyOperator0.35, Velero1.18/AWS-S3plugin(local only), ChaosMesh2.8.4 | operations, full |

Pod Security is restricted except node/network components in istio-system,
monitoring-agents and chaos-mesh (privileged), trivy-system (baseline with
restricted warnings), and the local Velero node-agent namespace for filesystem
backup (CONTINUITY explains its narrow local requirement). App dx03v2 stays
restricted, ambient and Gatekeeper deny. DX declares its own istio-waypoint for
mesh-* traffic splitting/retries/ejection/identity authorization, the local twin
of managed Cloud Service Mesh sidecars (ADR47), since Autopilot cannot run ambient.

## Running it

Docker needs 8 GB for full, 7 GB for small (core fits3 GB), plus `make tools`.
Use Linux, WSL2 or devcontainer.

```bash
make e2e                          # up + probes + down, even after failure
LOCAL_PROFILE=core make local-up  # observability/operations/full also available
LOCAL_SIZE=small make local-up    # same platform with smaller memory budget
make local-check                  # probes for installed components
make local-down                   # destroy and leftovers-local
scripts/local-lab.sh status
export KUBECONFIG="$(scripts/local-lab.sh kubeconfig)"
```

Kubeconfig is `$LOCAL_STATE_DIR/kubeconfig`; `~/.kube/config` is never used or
modified. Local scripts refuse every context except kind-tx03v2-local, even when
invoked alone: uninstall removes all Gateways/LoadBalancer Services in its target
cluster (`policy-scripts`). Devcontainer has its own Docker daemon; commands need
no adjustment (core E2E locally verified2026-10-14). A container mounting host
docker.sock needs `LOCAL_KIND_INTERNAL=1` to enter the lab network/use internal API.

Grafana: `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80`,
user admin, password from `terraform -chdir=terraform/envs/local output -raw grafana_admin_password`
with local-lab.sh's TF_DATA_DIR. Explore/Tempo opens a trace by ID; "Logs for this
span" finds Loki trace_id lines; Prometheus exemplars open traces. Argo has no
local admin user; inspect Applications through kubectl.

For Slack, create an incoming webhook and set
`LOCAL_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/... make local-up`.
Warning/critical alerts go there; without it, Slack-shaped messages go to alert-sink
for CI assertions. kubectl stdin creates monitoring/alertmanager-slack; no webhook
file/log is written.

## Sizes (`LOCAL_SIZE`)

Small (default is `default`) uses the same components with less memory.
`helm_install` applies `platform/local/values/small/<chart>.yaml` last. App probes
need almost all components; defaults already use one replica each.

| Chart | Small size |
| --- | --- |
| kube-prometheus-stack | Prometheus2h retention(default6h), 20k exemplars(default100k), 640 MiB limit;omit cAdvisor/kubelet probes, apiserver histograms/default rule groups reading them, keep probe targets. Grafana unified alerting disabled (Alertmanager used), no startup plugins, 512 MiB |
| Loki/Tempo/Alloy | 320/320/200 MiB;Tempo1h retention(default6h) |
| Collector | 192 MiB;chart derives GOMEMLIMIT/memory_limiter |
| ArgoCD | 5status/2operation workers, one repo render at a time (one app);320/256/192 MiB |
| Gatekeeper | 5minute audit(default1), only constraint-used kinds to avoid listing everyAPItype;384 MiB |
| TrivyOperator | one scan job, 320 MiB operator |
| Velero | 256 MiB |

Go components get GOMEMLIMIT below their cgroup limit, allowing GC before OOM;
Prometheus3/Collector derive it already. `scripts/local/kind-cluster.sh` adds
kind-config-small.yaml with apiserver/controller-manager/etcd GOMEMLIMIT through
kubeadm v1beta4 extraEnvs. To resize an existing lab, first local-down; otherwise
the cluster is reused. helm-template-local renders all small overlays, retains
all normal checks, and rejects image overrides or unknown charts.

Full platform plus dx03v2, Docker memory without swap:

| Size | Docker | Result |
| --- | --- | --- |
| default | 16 GB CI runner | passes TX e2e/DX e2e-platform |
| small | 7 GB Docker-in-DockerCI, 2026-10-15 | then-current18 probes pass in~13 min, 4.40 GiB anonymous memory;kernel twice killed Velero plugin-copy BestEffort init container, which kubelet retried |

Pair01 also measured default7 GB failure by thrashing, small6 GB rollout request
loss, and small8 GB success (its LOCAL_LAB). Bruno selected7 GB on2026-10-15
(R1.8 originally targeted6 GB). DXsmall CI repeats proof perPR. Historical working-set
peaks2026-10-15:apiserver1279 MiB, Grafana309, ArgoController284, Prometheus250,
TrivyOperator190, etcd160, two Gatekeeper pods264 MiB.

## What the probes prove (`platform/local/check.sh`)

| Area | Probe |
| --- | --- |
| Database | verify-full/lab CA succeeds, plaintext rejected |
| Mesh | allowed identity reaches service throughztunnel mTLS;other identity denied;outside-mesh client denied bySTRICT |
| Edge | GatewayProgrammed/emulatedLBaddress, verified HTTPS/lab CA, external free-text/UUID X-Request-Id intact via gateway-preserve-request-id EnvoyFilter (DXlocal smoke expectation;Google behavior undocumented), HTTP301 |
| Secrets | DX ExternalSecret becomes five-key contractSecret |
| Metrics | kubectl top nodes/metrics-server |
| Observability | kube-state-metrics/node-exporter/apiserver/kubelet scraped;synthetic rule reaches sink/Slack-shaped receiver;configured real webhook checks delivered/no failed notifications;probe logs inLoki, Grafanahealthy/ClusterIP |
| Traces | OTLPHTTPspan toCollector appearsTempo;Gateway continues W3Ctraceparent, passes ownspan tobackend, reportsTempo;spanmetricsRED/trace IDexemplar inPrometheus;Grafana reachesTempo, logs→traces/metrics→traces |
| GitOps | first/second commit reconciled;deletedobject self-healed |
| Policies | badPod rejected by fivepodconstraints, goodPod accepted, NodePort denied |
| Registry/scan | pushedimage pulled bynode;ClientServerTrivyOperator/internalserver emits ConfigAuditReport/VulnerabilityReport |
| Backup | Velero namespace backup/delete/restore;later volume drill verifies actual restored bytes/checksum/new PVC |
| Chaos | two replicas/podkill >=38/40 requests;100ms NetworkChaos allpods >=19/20 and median+80ms;CPU/memory StressChaos eachcontainer >=38/40, no restart, CPUpeak visiblemetrics-server |

## Limits (what this lab does not prove)

- No Google IAM/WIF/GKE/serviceaccount/managedGateway/Cloud Armor/Secret Manager/
  Parameter Manager/Cloud SQL/PSC/quota/cloud-cost proof. All remain not run in the
  cloud(v2). Cloud core is ESO/Collector;full omits ambient, node-exporter, Trivy
  nodecollector, privileged Chaosdaemon (ARCHITECTURE). Google manages Gateway.
- kind does not emulate Autopilot request minima/CPU:memory ratios, privileged/
  hostPath restrictions or third-party webhook limitations. v1Warden rejected
  ztunnel, node-exporter hostPath and Trivy webhooks (lesson7). NetworkPolicy uses
  kindnet, not Dataplane V2.
- Local Istio/lab CA HTTPS is not GKEGateway:cloud coreHTTP80/fullmanagedHTTPS,
  Cloud Armor absent locally, managed issuance unrun.
- S3 object emulator exercises AWS/S3 Velero plugin locally, not actual GCSplugin.
- Default topology is one node and cannot prove HA/drain. Opt-in three-node
  LOCAL_TOPOLOGY=ha capacity/PDB exercise is covered separately in FINOPS.
- cloud-provider-kind requires Docker socket/createsEnvoy containers;use
  disposable machine/CI only.
- Trivymirror/registry.tx03v2.local mapping are local only.
- Local logs/metrics/traces/backups use hours of retention and disappear on destroy.
- Small was proved with DX's historical18 probes;TXfull probe suite runs default
  size inCI, so LOCAL_SIZE=small make e2e remains unverified.
- Without LOCAL_SLACK_WEBHOOK_URL, CI proves receiver/message shape, not delivery
  to a real Slack workspace.
