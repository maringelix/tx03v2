# tx03v2 <-> dx03v2 contract — version 5 (2026-10-17)

Version5(R9):db_profile=dr publishes tx03v2-lab-dr-contract with the same18keys,
but secondary region, cluster, VPC, PSC, registry, secrets and Gateway address. App
selects DR explicitly only after primary fencing/manual PostgreSQL promotion.
Primary tx03v2-lab-contract retains v4core values. ha enables HA/PITR without
changing the app interface. [CONTINUITY.md](CONTINUITY.md) distinguishes local
proof from managed-service validation.

CLI --target secondary/workflow target=secondary selects only tx03v2-lab-dr and
gitops/gcp-dr;primary uses gitops/gcp. Secondary supports full, its own mesh and
project-global TLSmap/WAF. BSL primary-recovery reads multiregion backup as
velero-dr, distinct from its bucket for new copies. LAB_ACTIVE_REGION changes
only the A record after authorized recovery acceptance, never fencing/promotion.

Version4(R8):optional public Cloud DNS/Certificate Manager/CertificateMap HTTPS,
managed Autopilot sidecars only in app namespace, Kyverno promotion-attestation
admission, Trivy/Kyverno registry reads, persistent observability, seven CRS WAF
categories/IP rate limit;18keys, three new. Version3 added full Argo Application
dx03v2 tracking gitops/gcp and named-Application refresh. Version2(2026-10-14)
added observability Collector/Cloud Trace. Version1(2026-10-11) had no traces.

This infrastructure repository owns the interface;DX CONTRACT repeats its consumed
portion and links here. Changes require coordinated PRs/version increment. Each
harness checks its own side. AWS/Azure pairs use equivalent service contracts.

## How this repository verifies the contract

| What | Where | Status |
| --- | --- | --- |
| WIFissuer/mapping/condition, CIaccounts, exact subject per binding | bootstrap/tests/identities.tftest.hcl | verified locally |
| Plan/apply roles, conditional projectIamAdmin list equals lab-root grants | bootstrap/tests/roles.tftest.hcl, envs/lab/tests/roles.tftest.hcl | verified locally |
| Deploy/members/ESO/Collector cloudtrace.agent/node/Trivy/Kyverno registry roles, direct WIF principals/no key | envs/lab/tests/roles.tftest.hcl | verified locally |
| observability Collector/googlecloud exporter, local image digest, chartSHA256 | contract-platform, helm-template | verified locally |
| 18parameter keys, fixed values and origins;Terraform=harness=table | lab.tftest.hcl, contract-parameter | verified locally |
| Write-only secrets, PSC/TLS/sharedCA Cloud SQL, Artifact Registry | data_stores.tftest.hcl | verified locally |
| Autopilot channel/private nodes/DNS/Gateway, network/NAT/PSC/privateDNS | gke/network tests | verified locally |
| Seven CRS categories, 600/min/IP, Standard Adaptive Protection, 64 KB, none without WAF | waf.tftest.hcl | verified locally |
| PublicDNS/DNSauth/cert/map, managed mesh membership/feature;none in core | edge_mesh/validations tests | verified locally |
| Private control-plane range/firewall8443Gatekeeper/9443Kyverno+Chaos | gke/validations tests | verified locally |
| Kyverno fork promotionattestation/digest/Kubernetesmode, STRICTmesh/workload-port exceptions/identity, full install order | image-admission-policy, image-admission-fixtures, full-install-order, contract-platform-full | verified locally |
| Namespace/Role/RoleBinding/ClusterSecretStore | contract-platform, kubeconform | verified locally |
| Real Google Cloud behavior | RUNBOOK | not run in the cloud (v2) |

## Equivalent AWS and Azure services

| AWS | Azure | Google Cloud |
| --- | --- | --- |
| EKS/access entries | AKS/Entra | Autopilot/IAM DNS/KubernetesRBAC |
| Pod Identity | Workload ID | GKEWIF/directServiceAccount, no Google account |
| RDSPostgreSQL 17 | FlexibleServer17 | Cloud SQL17Enterprise/PSC |
| SecretsManager | KeyVaultRBAC | Secret Manager |
| SSM | AppConfigurationFree | Parameter ManagerJSON |
| ECR | ACR | immutableArtifact Registry |
| ALB/WAF | AGC/WAFDRS2.1 | GKEGateway/globalexternalALB/Cloud Armor |
| IAMOIDC | federated managedidentity | GitHubWIFserviceaccount |
| AWSBudgets | CostManagement | Cloud Billingprojectbudget |

## Identifiers

| Item | Value |
| --- | --- |
| Google Cloud project | billing-linked dedicated project created by the operator; Terraform project_id and GitHub variable `GCP_PROJECT_ID`; examples `tx03v2-lab-example`, number `000000000000` |
| Region | tx03v2 `region`, default `us-central1` (key below) |
| Project/environment/prefix | `tx03v2` / `lab` / `tx03v2-lab` |
| GKE cluster | `tx03v2-lab`, regional Autopilot, `REGULAR` (Kubernetes 1.36), private nodes, public IP endpoint disabled, IAM-only authorized DNS endpoint, standard Gateway API, Dataplane V2 enforcing NetworkPolicy |
| Nodes | x86-64, Autopilot general-purpose; images `linux/amd64` |
| App namespace | `dx03v2`, created by TX platform with `pod-security.kubernetes.io/enforce=restricted`, `pod-security.kubernetes.io/enforce-version=latest`; `gcp*` overlays do not create it, `local` creates an equivalent for kind |
| Deployer Kubernetes RBAC | Role `dx03v2-deployer`, RoleBinding `dx03v2-deployers` in `dx03v2`; `kind: User` subjects for `dx03v2-gha-deploy` service-account email and tx03v2 `app_deployer_members` emails |
| Artifact Registry | regional Docker repository `dx03v2`, immutable tags; `<region>-docker.pkg.dev/<project_id>/dx03v2/api` and `.../web`, tag full 40-character DX git SHA; node service account reads it |
| Deploy service account | `dx03v2-gha-deploy@<project_id>.iam.gserviceaccount.com`, example `dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com` |
| Traces (OpenTelemetry, version 2) | `http://opentelemetry-collector.observability.svc:4318`, OTLP/HTTP `OTEL_EXPORTER_OTLP_ENDPOINT` in `gcp`; TX installs Collector, whose ServiceAccount has `roles/cloudtrace.agent`; app receives no IAM role for traces |

Role `dx03v2-deployer` in namespace `dx03v2` limits kinds in `gcp*` overlays.
`contract-app` rejects other kinds; deployment checks each verb with
`kubectl auth can-i` before promotion/apply:

- `apps`: deployments → get/list/watch/create/update/patch/delete;
  replicasets → get/list/watch.
- core: services/configmaps/serviceaccounts → get/list/watch/create/update/patch/delete;
  pods/pods/log/events/endpoints → get/list/watch; secrets → get/list/watch
  (ESO writes secrets; deployer never writes them).
- `networking.k8s.io`: networkpolicies → full CRUD.
- `networking.istio.io`: destinationrules/virtualservices and `security.istio.io`:
  authorizationpolicies → full CRUD only in `dx03v2` (full mesh exercise; inert
  without Istio CRDs).
- `gateway.networking.k8s.io`: gateways/httproutes → full CRUD.
- `networking.gke.io`: healthcheckpolicies/gcpbackendpolicies → full CRUD;
  `gcp-waf` writes and `gcp` deletes GCPBackendPolicies, so both are always required.
- `autoscaling`: horizontalpodautoscalers → full CRUD;
  `policy`: poddisruptionbudgets → full CRUD.
- `external-secrets.io`: externalsecrets → full CRUD.

GatewayClasses are cluster-scoped, outside this Role. Deploy checks the class
when readable; otherwise Gateway `Programmed` is the proof.

`deploy-gcp` accepts `platform_profile=core|full` and `deploy_mode=auto|gitops|push`.
`auto` chooses GitOps when Application `dx03v2` exists, direct apply otherwise;
permission/connection errors fail closed. With GitOps (`tx03v2` full, Argo CD owns
app manifests), deployment configures path, images and actual address/ranges/
Cloud SQL endpoint/hostname/Certificate Map in Application `dx03v2`
`spec.source.kustomize`, namespace `argocd`. It then publishes the app commit and
example-derived `params.env` to `gitops/gcp` and requests refresh. The parent
ignores only `spec.source.path`/`spec.source.kustomize` on that Application and
uses `RespectIgnoreDifferences=true`. `push` (no Argo CD or local script
`DEPLOY_MODE=push`) applies the overlay directly. The public branch receives no
real account/project IDs.

For full, the workflow runs from `main`, promotes verified digests to Artifact
Registry without rebuilding, attests each promoted digest (predicate
`https://github.com/maringelix/tx00v2/attestations/promoted-image/v1`, keyless
identity `deploy-gcp.yml` on `main`), verifies with `gh attestation verify`, then
deploys. TX Kyverno `ImageValidatingPolicy` requires that app signature. Managed
Google proxies have a separate narrow Gatekeeper exception; they are outside
the app repository's signature scope.

Additional infrastructure identifiers:

| Item | Value |
| --- | --- |
| Provider default_labels | project=tx03v2, environment=lab, managed-by=terraform, repository=<owner>_tx03v2 (label values forbid /) |
| Global suffix | substr(sha1(project_id), 0, 8), deterministic;example00000000 |
| State bucket | tx03v2-tfstate-<suffix>, bootstrap/versioned/uniform/public-access prevention |
| Network | customVPC tx03v2-lab;tx03v2-lab-nodes default10.30.0.0/20, Private Google Access;pods10.32.0.0/16, services10.33.0.0/20;Cloud Router/NAT tx03v2-lab |
| Private control plane | control_plane_cidr default172.31.255.240/28, no publicIP;DNS externally reachable with IAMonly |
| Nodes | bootstrap tx03v2-lab-nodes service account |
| CI service accounts | tx03v2-gha-plan, tx03v2-gha-apply, dx03v2-gha-deploy |
| Cloud SQLinstance | tx03v2-lab-<4randomhex>, deleted name reserved up to one week, PostgreSQL 17ENTERPRISE/defaultdb-g1-small |

## GitHub Workload Identity Federation

Pool tx03v2-github, provider github, issuer https://token.actions.githubusercontent.com.
Mapping:google.subject=assertion.sub, attribute.repository=assertion.repository,
attribute.repository_owner=assertion.repository_owner. Condition:
assertion.repository_owner_id == '<ownerID>' && assertion.repository_id in
['<TXrepoID>', '<DXrepoID>']. github_owner and all three numeric IDs have no defaults;
reclaimed names have different IDs and cannot inherit. workloadIdentityUser uses
exact principal://iam.googleapis.com/projects/<number>/locations/global/workloadIdentityPools/tx03v2-github/subject/<subject>.

| Service account | Exact subjects |
| --- | --- |
| tx03v2-gha-plan | repo:<owner>@<owner id>/tx03v2@<repo id>:pull_request and repo:<owner>@<owner id>/tx03v2@<repo id>:ref:refs/heads/main |
| tx03v2-gha-apply | repo:<owner>@<owner id>/tx03v2@<repo id>:environment:lab |
| dx03v2-gha-deploy | repo:<owner>@<owner id>/dx03v2@<repo id>:environment:lab |

This is immutable GitHub sub (repos created after2026-07-15 or opted in);old name-only
subjects do not match. repo-guardrails restricts lab environment to main.

Lab root grants deploy registry writer only on dx03v2, project clusterViewer
(GKEcredentials/DNS, IAM has no cluster scope), project parameterAccessor
(provider8.6.0 has no parameter IAM;project contains only lab contracts), noSecret Manager.
Kubernetes access only through RoleBinding. app_deployer_members user:<email>/
serviceAccount:<email> gets same three scopes and User subjects by email;group:
is rejected by Terraform/installer because GoogleGroupsRBAC is not configured.

## Contract parameter: Parameter Manager tx03v2-lab-contract

Global JSON with one live version read through latest. Version ID c-<first16hex
of JSONsha256>;create_before_destroy publishes new before deleting old. DXgets
GCP_PROJECT_ID from GitHub and calls gcloud parametermanager parameters versions
render latest --parameter=tx03v2-lab-contract --location=global. No secret values.
Exactly18string keys:

| Key | Value | dx03v2 use |
| --- | --- | --- |
| `project-id` | lab project ID | must equal `GCP_PROJECT_ID` |
| `region` | region | format checked; `get-credentials --location`, registry host, Cloud SQL CA bundle |
| `cluster-name` | `tx03v2-lab` | fixed value checked; `get-credentials --dns-endpoint` |
| `network-name` | `tx03v2-lab` | fixed value checked |
| `nodes-subnet-cidr` | node subnet CIDR | RFC1918 checked; must contain `db/endpoint-ip` |
| `db/endpoint-ip` | internal Cloud SQL PSC endpoint IP | `api-egress-to-cloudsql`: `<ip>/32`, port 5432 (`DB_ENDPOINT_IP`) |
| `lb-source-ranges` | fixed `35.191.0.0/16,130.211.0.0/22` | `web-ingress-from-lb`/`api-ingress-from-lb`, one ipBlock/range (`LB_SOURCE_RANGES`) |
| `artifact-registry/repository` | `<region>-docker.pkg.dev/<project_id>/dx03v2` | checked against region/project; `api`/`web` images (`API_IMAGE`, `WEB_IMAGE`) |
| `db/secret-name` | `tx03v2-lab-db-app` | checked against ExternalSecret `db-credentials` |
| `app/admin-token-secret-name` | `tx03v2-lab-app-admin-token` | checked against ExternalSecret `app-secrets` |
| `eso/cluster-secret-store` | `gcp-secret-manager` | checked against ExternalSecret `secretStoreRef` |
| `gateway/address-name` | `tx03v2-lab-gateway` | Gateway `spec.addresses`, `type: NamedAddress` (`GATEWAY_ADDRESS_NAME`) |
| `gateway/address` | reserved IPv4 | format checked; programmed Gateway must match; core smoke URL |
| `dns/hostname` | public app subdomain or `disabled` | `DNS_HOSTNAME`, required in full; Gateway listeners, HTTPS/redirect routes, full smoke URL |
| `dns/certificate-map` | Certificate Map name `tx03v2-lab-app` or `disabled` | `CERT_MAP`, Gateway `networking.gke.io/certmap`; disabled iff hostname disabled |
| `mesh/management` | `managed` or `disabled` | full requires managed Cloud Service Mesh, sidecars only in `dx03v2` |
| `waf/security-policy` | `tx03v2-lab-waf`, or `none` when TX `enable_waf=false` | GCPBackendPolicies `api`/`web`, `WAF_SECURITY_POLICY`, `gcp-waf`; none selects `gcp` and deletes old policies |
| `deploy/service-account` | `dx03v2-gha-deploy` email | must equal `dx03v2-gha-deploy@<GCP_PROJECT_ID>.iam.gserviceaccount.com` |

## Secret Manager

User-managed regional replication, secret_data_wo;values never enter plan/state.

- tx03v2-lab-db-app:JSONstrings username/app, password, host, port/5432, dbname/app.
  host is PSC dns_name without trailing dot:<uid>.<projectlabel>.<region>.sql.goog,
  verified by verify-full.
- tx03v2-lab-app-admin-token:plain48random alphanumeric characters.
- ESO external-secrets/external-secrets direct principal
  principal://iam.googleapis.com/projects/<number>/locations/global/workloadIdentityPools/<project_id>.svc.id.goog/subject/ns/external-secrets/sa/external-secrets
  gets secretAccessor on owned secrets only. DRcreates regional containers and
  protected apply synchronizes current primary values;plan/deploy have no value access.

## Cloud SQL

- Core:PostgreSQL 17ENTERPRISE (16+defaultsPlus, shared-core onlyEnterprise),
  db-g1-small/default50 connections, enough4API×pool10+migration;f1-micro25rejected.
  Zonal10 GBSSD/noautoresize, automatic backups/1retained, no retention afterdelete,
  deletion protectionoff. HA/DR optional overrides:CONTINUITY.
- No publicIP/private-services-access peering;allowed_consumer_projects=[project_id].
  Internal address/forwarding rule tx03v2-lab-db in node subnet targets instance
  psc_service_attachment_link. PrivateDNS tx03v2-lab-sql, <region>.sql.goog., labVPC
  only, instance dns_name A to PSCIP.
- ENCRYPTED_ONLY, GOOGLE_MANAGED_CAS_CA shared regional root, DNS SAN, automatic
  maintenance rotation.
- app DB/user, password_wo, both ABANDON:deleting object-owning user first fails;
  they disappear with instance.

## Cloud Armor

Global Standard tx03v2-lab-waf when enable_waf=true(default). Seven sensitivity1
CRS3.3 v33-stable categories:sqli, xss, lfi, rfi, rce, methodenforcement, scannerdetection
in deny403. throttle600 requests/min/clientIP, 429above;contractminimum300. Default
allow, 64 KBinspection, standardJSON parsing. L7Adaptive Protection detection alerts
only;signatures/automatic mitigation requireEnterprise. Oversize bodies are not
size-blocked;70 KBsmoke reaches API413. Rules must preserve smoke.

## Platform (platform/install.sh, never Terraform)

- ESO2.12.0/external-secrets, SAexternal-secrets/no annotation (directIAMprincipal),
  CPU/memoryrequests forAutopilot;gcp-secret-manager gcpsm store/projectID/no auth,
  controlleridentity, usable onlydx03v2. Namespace/Role/RoleBinding as above.
  Google manages gke-l7-global-external-managed controller;no installation.
- Collector0.162.0/chart0.176.0, verifiedSHA256, inobservability/restricted labels,
  SAopentelemetry-collector/no annotation, Autopilotrequests. Directprincipal
  principal://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/<PROJECT_ID>.svc.id.goog/subject/ns/observability/sa/opentelemetry-collector
  gets only project cloudtrace.agent (no per-resourceTraceIAM). App OTLP/HTTP
  endpoint http://opentelemetry-collector.observability.svc:4318;no app IAMrole.
- Full keeps service names;v4keys indicate domain/mesh. --profile full
  --github-owner <owner> adds pinned charts, Gatekeeper, Trivy, Velero, ArgoCD.
  dx03v2 policy.lab/enforce:true retains image/resource/probe/label/port constraints.
- GitOps platform Application/AppProject inargocd reads TXplatform/gitops and
  creates DXApplication at deploy/k8s/overlays/gcp, gitops/gcp. Installer injects
  fork URLs without recording real values publicly. dx03v2-gitops-sync Role/
  binding uses same contractUsers, get/watch/patch only namedApplicationdx03v2;
  cannot modify others.
- Deploy updates liveApplication overlay/images/cloud params. Parent ignores only
  spec.source.path, kustomize.images, kustomize.patches with RespectIgnoreDifferences;
  public GitOps branch has revision/exampleparams, real names/CIDRs/addresses staycluster-side.
- Velero full SAvelero/velero, no Google key/Secret;bucket <LAB_NAME>-velero-<PROJECT_ID>,
  no extra contractkey. DirectWIF principal
  principal://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/<PROJECT_ID>.svc.id.goog/subject/ns/velero/sa/velero
  gets bucket-onlyobjectAdmin.35day objects/schedules plus PD CSI snapshots(R9);
  Cloud SQL native backups separate. DRmultiregion/read-only recovery inCONTINUITY.
- Managedmesh:enable_managed_mesh=true, fleetmembership/servicemesh
  MANAGEMENT_AUTOMATIC, mesh/management=managed. Upstream ambient privileged
  istio-cni/ztunnel unsupported(ADR39). Installer requires fleetmeshACTIVE and
  certificateACTIVE. Only app namespace gets istio-injection:enabled and
  mesh.cloud.google.com/proxy:{"managed":"true"};monitoring/observability outside.
  app-security defaultSTRICT, workload-selected plaintext exceptions web8080,
  API3000/9464 (portLevelMtls requires selector);webidentity toAPI3000, trust
  <project>.svc.id.goog, not cluster.local. ExternalLB ranges perport, Prometheus
  API9464 restricted tonamespace monitoring, Collectoronlyhealthz/readyz.
- HTTPS:dns_zone_name/app_domain_name create publicCloud DNS, A record, DNSauthCNAME,
  Certificate Manager cert/maptx03v2-lab-app. Full Gateway443 uses certmapannotation,
  neverKubernetesTLSSecret;HTTP80redirect301. Owner must delegate dns_name_servers
  at registrar;otherwisePROVISIONING, full refuses. CoreHTTP/no domain remains.
- Admission:Kyvernochart3.8.2/controller1.18.2, in kyverno, ImageValidatingPolicy
  dx03v2-release-signatures requires digest appapi/web and keyless Sigstore
  promotionpredicate https://github.com/maringelix/tx00v2/attestations/promoted-image/v1
  from forkmain deploy-gcp.yml, GitHub issuer https://token.actions.githubusercontent.com.
  Fail/Deny blocks app if controller unavailable. DXattests same promoted bytes.
  kyverno-admission-controller directWIF gets registry-only reader, no key/pullSecret.
  Kubernetesmode verifies images.containers/initContainers/ephemeralContainers,
  each filtered by matchImageReferences beforeCEL ([v1.18.2 implementation](https://github.com/kyverno/kyverno/blob/v1.18.2/pkg/image/verification/evaluator/policy.go)).
  Google proxy outsideforkattestation. Cloud-only LabGcpAllowedImages permits only
  contractapi/web SHA25664, plus istio-proxy/istio-validation containers at exact
  gcr.io/gke-release/asm/proxyv2 with explicit tag/digest. Similar names/paths
  receive noexception. [Managed injector](https://docs.cloud.google.com/service-mesh/v1.25/docs/onboarding/provision-control-plane)
  chooses version;[official registry](https://gcr.io/v2/gke-release/asm/proxyv2/tags/list)
  supplies digestfixture without changing cluster-managedversion. Gator covers
  injectedPod and deniedregular/init/ephemeral images;real signature/subresource
  admission remains cloud-validation work.
- Trivyjobs in trivy-system use SAtrivy-operator/directWIFregistryreader, short-lived
  GKEmetadata token. Missing report does not mean clean image.
- Privatecontrolplane ordinarily initiates TCP443/10250;fixed /28 firewall
  tx03v2-lab-control-plane-webhooks to node SA allows8443Gatekeeper/9443Kyverno+Chaos.
  Without it Gatekeeper cannot enforce and fail-closedKyverno blocks app.
- Persistent standard-rwo observability:Prometheus7 days/8 GB, Alertmanager72h,
  Grafana, Loki7 days, Tempo72h. Uninstall releases/PVCs beforedestroy;disks outside
  state continuebilling. Collectorhttpcheck triggers Dx03v2SyntheticProbeFailed;
  app-monitoring.yaml supplies ServiceMonitor, 99.5%availability/errorburn/p95/
  restart rules and dx03v2 API SLOdashboard. AbsentSlackwebhook uses nullreceiver,
  visibly unconfigured in Alertmanager.
- Uninstall removes app namespace, waits Gatewayfinalizers/k8s1-*NEGs whilecluster
  exists, then full releases/monitoringPVCs. OtherwisecontrollerLB leaks outsideTFstate.

## Application runtime (dx03v2)

- Secret `db-credentials`: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`.
  Cloud ExternalSecret maps each `tx03v2-lab-db-app` JSON property; kind/Compose
  generate random values at runtime with `scripts/e2e-kind.sh`/`scripts/dev-env.sh`.
- Secret `app-secrets`, key `ADMIN_TOKEN`, from cloud ExternalSecret
  `tx03v2-lab-app-admin-token`.
- Cloud database TLS: `DB_SSL_MODE=verify-full`,
  `DB_SSL_CA_FILE=/etc/cloudsql-ca/ca.pem`, ConfigMap `cloudsql-ca` built from
  `https://storage.googleapis.com/cloudsql-ca-bundles/<region>.pem`. Deploy
  **rejects** non-certificate PEM blocks, absence of exactly one self-signed root
  with the SHA256 below, or a non-CA/certificate not issued by it (`openssl verify
  -x509_strict`, only this root, no system trust). openssl rewrites certificates
  into the ConfigMap. The bundle is never pinned because regional subordinate
  CAs rotate.

  | Root | SHA-256 (contract) | SHA-1 | Expiry |
  | --- | --- | --- | --- |
  | `CN=Google Cloud SQL Root Server CA 0b29df` (ECDSA P-384) | `C7B0FCD282B346F1FCC45EE8A79ECF6EF6FAEF2D669BEEC664293B93D83E59BE` | `9E0DDEC1969957360315A0B849CD609E6FC0905C` | 2049-06-27 |

  Local: `DB_SSL_MODE=disable`. `APP_ENV=lab` rejects anything except `verify-full`.
- `TRUST_PROXY_HOPS=2`: global external Application Load Balancer appends
  `<client IP>,<load balancer IP>` to `X-Forwarded-For`; connection comes from a
  Google Front End (`rate-limit` integration test).
- Services: `api` HTTP 3000, metrics 9464; `web` 8080.
- Cloud traffic: Gateway `dx03v2`, class `gke-l7-global-external-managed`,
  NamedAddress `gateway/address-name`. Core listens only HTTP 80. Full serves
  HTTPS 443 for `dns/hostname` using `dns/certificate-map` annotation
  `networking.gke.io/certmap` (no listener `tls` block/Secret). HTTP only sends a
  same-host/path 301 via `dx03v2-http-redirect`. HTTPRoute `dx03v2`: `/api` →
  `api:3000`, `/` → `web:8080`; HealthCheckPolicies web `/healthz`:8080 and API
  `/readyz`:3000; GCPBackendPolicies use `waf/security-policy`, omitted with `none`.
- TX Cloud Armor: preconfigured `sqli-v33-stable`/`xss-v33-stable` in `deny(403)`,
  inspect first 64 KB without size blocking, so API itself returns 413 for the
  70 KB smoke body. Rules must not block smoke; any rate limit must permit
  >=300 requests/minute/client.
- Cloud NetworkPolicies: web:8080/API:3000 ingress only from `lb-source-ranges`;
  API egress to `db/endpoint-ip`/32:5432; base DNS plus node cache
  `169.254.20.10/32:53` (Autopilot NodeLocal DNSCache). Full additionally allows
  pod egress to public 443 for managed control plane/Mesh CA and metadata server
  `169.254.169.254:80` (private ranges remain closed), Collector synthetic-probe
  ingress only to web:8080/API:3000, and mesh exercise traffic among
  `mesh-probe`, `mesh-intruder`, `mesh-stable`, `mesh-canary` only on 3000.
- Full mesh (`components/mesh-csm`): managed Cloud Service Mesh injects only in
  `dx03v2`, with TX mTLS STRICT/identity authorization (trust domain
  `<project>.svc.id.goog`, principals `*/ns/dx03v2/sa/<account>`). Both backends
  use API image; VirtualService splits `/variant` 80/20, permits at most two
  `/fail` retries (`5xx`, 1 s/try), DestinationRule ejects after three consecutive
  5xx and AuthorizationPolicy permits only `mesh-probe` (`mesh-intruder`:403).
  Each pod requests a small proxy (`sidecar.istio.io/proxyCPU: 50m`, memory
  96 MiB, limit192 MiB). API excludes the Cloud SQL endpoint with
  `traffic.sidecar.istio.io/excludeOutboundIPRanges` because migration connects
  before sidecar startup and the database is outside mesh.
- Cloud SQL PostgreSQL 17 Enterprise, port5432, PSC only,
  `ssl_mode=ENCRYPTED_ONLY`, `server_ca_mode=GOOGLE_MANAGED_CAS_CA`.

## Local lab (independent local contract, version 2)

The local lab has its own versioned contract for DXdeploy-local (proved by
e2e-platform), mirroring cloud names without changing the cloud interface. Same
keys as TX01local contract, only cloud-equivalent column differs. Published by
platform/local/install.sh as ConfigMap lab-system/lab-contract:

| Key | Value | Cloud equivalent |
| --- | --- | --- |
| version | 2, 2026-10-14 tracing.otlp-endpoint;v1had no traces | this document version |
| cluster-name | tx03v2-local | cluster-name |
| network-cidr | 10.252.0.0/24 or subnet_cidr | nodes-subnet-cidr |
| registry | registry.tx03v2.local, in-cluster image name | artifact-registry/repository prefix |
| registry-push | localhost:5003, machine push | — |
| db.endpoint-ip, db.hostname, db.port | 10.252.0.11, db.tx03v2.local, 5432 | db/endpoint-ip and PSCsecret host |
| db.secret-name | tx03v2-lab-db-app, host/port/dbname/username/password | db/secret-name |
| db.ca-configmap | lab-system/lab-ca, ca.crt | deploy-created cloudsql-ca, regional bundle/contractroot |
| app.admin-token-secret-name | tx03v2-lab-app-admin-token, keytoken | cloud plain string/app/admin-token-secret-name |
| eso.cluster-secret-store | local-secrets, dx03v2only | gcp-secret-manager |
| gateway.class | istio | gke-l7-global-external-managed/NamedAddress |
| tls.cluster-issuer | lab-ca/cert-manager | fullCertificate Manager, not Kubernetesissuer |
| gitops.push-url, gitops.read-url |ssh://10.252.0.13:23231/dx03v2-gitops,http://10.252.0.13:23232/dx03v2-gitops.git|—|
| gitops.push-key-secret | lab-secrets/gitops-push-key, kubernetes.io/ssh-auth | dx03v2-gha-deploy serviceaccount |
| argocd.project | dx03v2, only own Git/namespace/deploykinds, noSecrets/clusterresources | dx03v2-deployerRole |
| monitoring.prometheus-service-account | monitoring/kube-prometheus-stack-prometheus, meshidentity | — |
| tracing.otlp-endpoint |http://opentelemetry-collector.monitoring.svc:4318,appOTLP/HTTP throughmesh;GatewayOTLP/gRPC4317 |http://opentelemetry-collector.observability.svc:4318|

Same-named DB/adminSecrets live in lab-secrets, the local Secret Manager equivalent.
Localapp namespace restricted, ambient, policy.lab/enforce:true, Gatekeeperdeny/
registry.tx03v2.local-only images;monitoring Prometheus scrapes app. DXwritesGit,
Argo applies. Local Gateway preserves external X-Request-Id, where cloudSMOKE_EDGE=gke
checks only security property becauseLBbehavior undocumented. Local DB TLS-only
with lab CA;DB_SSL_MODE=disable applies only DXstandalone Compose/kind.

## Changing the contract

1. Cross-linked PRs in both repos, increment both CONTRACT titles.
2. Update covering tests/checks above. New parameterkey changes envs/lab/contract.tf,
   harnessCONTRACT_KEYS and this table together.
3. Merge publisherTX before consumerDX, except removals reverse order.
