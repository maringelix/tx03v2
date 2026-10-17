#!/usr/bin/env bash
# Installs the platform layer on the lab cluster (never done by Terraform):
#   1. External Secrets Operator (namespace external-secrets, ServiceAccount external-secrets,
#      Workload Identity Federation for GKE) from the OCI chart pinned by digest and SHA256 in
#      platform/versions.env
#   2. platform/manifests (namespaces dx03v2 and observability, deployer RBAC, ClusterSecretStore
#      gcp-secret-manager)
#   3. OpenTelemetry Collector (namespace observability, contract v2): OTLP from the app, traces to
#      Cloud Trace (its ServiceAccount is the IAM principal with roles/cloudtrace.agent)
# The GKE Gateway controller (GatewayClass gke-l7-global-external-managed) is managed by Google:
# nothing to install for it. The optional full profile adds the cloud-safe charts of the local lab.
# CLOUD-MUTATING: run it only when you mean to (docs/RUNBOOK.md). Needs gcloud logged in (gcloud
# auth login, or google-github-actions/auth + setup-gcloud in the platform workflow) with the
# gke-gcloud-auth-plugin component, kubectl and helm (scripts/install-tools.sh kubectl helm), jq,
# and an identity with roles/container.admin (tx03v2-gha-apply) or Kubernetes cluster-admin.
# Reads the contract from Parameter Manager; nothing comes from the Terraform state. Environment:
#   GCP_PROJECT_ID        project of the lab (required; the script never guesses it)
#   APP_DEPLOYER_MEMBERS  JSON list of extra deployers (the Terraform variable app_deployer_members,
#                         e.g. ["user:you@example.com"]), default []; they become RoleBinding
#                         subjects by e-mail, without the user:/serviceAccount: prefix
#   SLACK_WEBHOOK_URL     optional Slack incoming webhook for warning/critical alerts (full only)
# Re-running it upgrades in place. It installs only on the contract cluster tx03v2-lab, and only when
# that cluster carries the label project=tx03v2; the kubeconfig is a temporary file (~/.kube/config
# and its current context stay as they were).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/../scripts/lib/common.sh"
# shellcheck source=scripts/lib/gcp.sh
source "$REPO_ROOT/scripts/lib/gcp.sh"
# shellcheck source=scripts/lib/platform.sh
source "$REPO_ROOT/scripts/lib/platform.sh"
export PATH="$REPO_ROOT/.tools/bin:$PATH"

ESO_NAMESPACE=external-secrets
OTEL_NAMESPACE=observability
OTEL_CHART_REPO="https://open-telemetry.github.io/opentelemetry-helm-charts"
SECRET_STORE=gcp-secret-manager
WORK_DIR=""
PROFILE=core
OWNER=""
OWNER_RE='^[A-Za-z0-9]([A-Za-z0-9-]{0,38})$'
CONTRACT_PROJECT=""
DEPLOYERS=""
VELERO_BUCKET=""
ARTIFACT_REPOSITORY=""

cleanup() {
  [[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
}

# load_platform_versions -> reads platform/versions.env (KEY=VALUE lines) without executing it.
load_platform_versions() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue
    [[ "$line" =~ ^([A-Z0-9_]+)=([A-Za-z0-9._:/@-]+)$ ]] || die "invalid line in platform/versions.env: $line"
    printf -v "${BASH_REMATCH[1]}" '%s' "${BASH_REMATCH[2]}"
  done <"$HERE/versions.env"
}

# connect_cluster PROJECT REGION CLUSTER -> temporary kubeconfig for the DNS-based control plane
# endpoint (IAM-authenticated; the IP endpoint is private); the user's own kubeconfig is never touched.
connect_cluster() {
  local project=$1 region=$2 cluster=$3
  export KUBECONFIG="$WORK_DIR/kubeconfig"
  gcloud container clusters get-credentials "$cluster" --location "$region" --project "$project" --dns-endpoint --quiet ||
    die "cannot fetch the credentials of $cluster (this identity needs container.clusters.get and container.clusters.connect)"
  kubectl get --raw /readyz >/dev/null ||
    die "the DNS endpoint of $cluster does not answer, or this identity has no Kubernetes access"
}

# pull_eso_chart -> path of the ESO chart archive, pulled by tag and manifest digest and checked
# against the archive SHA256 of platform/versions.env.
pull_eso_chart() {
  local tgz
  helm pull "$ESO_CHART_OCI:$ESO_CHART_VERSION@sha256:$ESO_CHART_DIGEST" --destination "$WORK_DIR" >&2
  tgz="$(find "$WORK_DIR" -maxdepth 1 -name 'external-secrets*.tgz' -print -quit)"
  [[ -n "$tgz" && -f "$tgz" ]] || die "helm pull did not produce the external-secrets chart archive"
  [[ "$(sha256_of "$tgz")" == "$ESO_CHART_SHA256" ]] ||
    die "refusing the external-secrets chart $ESO_CHART_VERSION: its SHA256 differs from platform/versions.env"
  printf '%s' "$tgz"
}

install_external_secrets() {
  local tgz
  tgz="$(pull_eso_chart)"
  log "installing the external-secrets chart $ESO_CHART_VERSION (digest and SHA256 verified)"
  helm upgrade --install external-secrets "$tgz" \
    --namespace "$ESO_NAMESPACE" --create-namespace \
    --values "$HERE/values/external-secrets.yaml" \
    --wait=watcher --rollback-on-failure --timeout 15m
}

# The Collector, from the chart archive checked against platform/versions.env; the project of the lab
# is the one setting that comes from here.
install_otel_collector() {
  local project=$1 tgz
  tgz="$WORK_DIR/opentelemetry-collector-$OTEL_COLLECTOR_CHART_VERSION.tgz"
  helm pull opentelemetry-collector --repo "$OTEL_CHART_REPO" --version "$OTEL_COLLECTOR_CHART_VERSION" --destination "$WORK_DIR" >&2
  [[ -f "$tgz" && "$(sha256_of "$tgz")" == "$OTEL_COLLECTOR_CHART_SHA256" ]] ||
    die "refusing the opentelemetry-collector chart $OTEL_COLLECTOR_CHART_VERSION: missing, or its SHA256 differs from platform/versions.env"
  log "installing the opentelemetry-collector chart $OTEL_COLLECTOR_CHART_VERSION (SHA256 verified; traces to Cloud Trace)"
  helm upgrade --install opentelemetry-collector "$tgz" \
    --namespace "$OTEL_NAMESPACE" \
    --values "$HERE/values/otel-collector.yaml" \
    --set-string "config.exporters.googlecloud.project=$project" \
    --wait=watcher --rollback-on-failure --timeout 15m
}

apply_manifests() {
  local file=$1 attempt
  # The ESO admission webhook can need a few seconds after `helm --wait` to serve its certificate.
  for attempt in 1 2 3 4 5; do
    if kubectl apply -f "$file"; then
      return 0
    fi
    log "kubectl apply failed (attempt $attempt/5); retrying in 15 s"
    sleep 15
  done
  die "could not apply platform/manifests"
}

usage() {
  echo "usage: $0 [--profile core|full] [--github-owner OWNER]" >&2
  exit 2
}

# apply_full FILE -> apply one rendered full-profile manifest after its CRDs have been installed.
apply_full() {
  local file=$1 attempt
  for attempt in 1 2 3 4 5; do
    if "$HERE/render-manifests.sh" "$CONTRACT_PROJECT" "$DEPLOYERS" --full "$OWNER" \
      --artifact-registry-repository "$ARTIFACT_REPOSITORY" --only "$file" | kubectl apply -f - >/dev/null; then
      return 0
    fi
    log "kubectl apply of platform/manifests/$file failed (attempt $attempt/5); retrying in 15 s"
    sleep 15
  done
  die "could not apply platform/manifests/$file"
}

# install_chart CHART [HELM_ARG...] -> installs a SHA256-verified archive from the full-profile table.
install_chart() {
  local chart=$1 repo_key version_key sha_key name release ns values tgz f out content n=0
  local -a files=() args=() post_renderer=()
  shift
  read -r repo_key version_key sha_key name release ns values <<<"$(chart_entry "$chart")"
  IFS=, read -ra files <<<"$values"
  mkdir -p "$WORK_DIR/values/$chart"
  for f in "${files[@]}"; do
    [[ -f "$HERE/$f" ]] || die "platform/full/charts.txt: platform/$f does not exist"
    n=$((n + 1))
    out="$WORK_DIR/values/$chart/$n-$(basename "$f")"
    content="$(<"$HERE/$f")"
    content="${content//__VELERO_BUCKET__/$VELERO_BUCKET}"
    printf '%s\n' "$content" >"$out"
    args+=(--values "$out")
  done
  tgz="$(pull_chart "$WORK_DIR/charts" "${!repo_key}" "$name" "${!version_key}" "${!sha_key}")"
  if [[ "$chart" == chaos-mesh ]]; then
    post_renderer=(--post-renderer chaos-mesh-no-daemon)
  fi
  log "installing $release ($name ${!version_key}, SHA256 verified) in $ns"
  BASH="$BASH" HELM_PLUGINS="$HERE/full/helm-plugins" helm upgrade --install "$release" "$tgz" --namespace "$ns" "${args[@]}" "${post_renderer[@]}" "$@" \
    --wait=watcher --rollback-on-failure --timeout 10m >/dev/null
}

install_observability() {
  local hook="${SLACK_WEBHOOK_URL:-}"
  local -a slack=()
  if ! kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
    openssl rand -hex 16 | tr -d '\n' | kubectl -n monitoring create secret generic grafana-admin \
      --from-literal=admin-user=admin --from-file=admin-password=/dev/stdin >/dev/null
  fi
  if [[ -n "$hook" ]]; then
    [[ "$hook" =~ ^https://[A-Za-z0-9.-]+/[A-Za-z0-9/_-]+$ ]] || die "SLACK_WEBHOOK_URL must be an https Slack incoming webhook URL"
    printf '%s' "$hook" | kubectl -n monitoring create secret generic alertmanager-slack \
      --from-file=webhook-url=/dev/stdin --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    slack=(--values "$HERE/values/full/kube-prometheus-stack-slack.yaml")
  fi
  # Prometheus Operator validates PrometheusRules with an admission webhook from its own release.
  if ! helm -n monitoring status kube-prometheus-stack >/dev/null 2>&1; then
    install_chart kube-prometheus-stack "${slack[@]}" --set defaultRules.create=false
  fi
  kubectl -n monitoring rollout status deployment/kube-prometheus-stack-operator --timeout=300s >/dev/null
  install_chart kube-prometheus-stack "${slack[@]}"
  retry 30 5 kubectl -n monitoring get statefulset prometheus-kube-prometheus-stack-prometheus alertmanager-kube-prometheus-stack-alertmanager >/dev/null 2>&1 ||
    die "Prometheus Operator did not create Prometheus and Alertmanager"
  kubectl -n monitoring rollout status statefulset/prometheus-kube-prometheus-stack-prometheus --timeout=300s >/dev/null
  kubectl -n monitoring rollout status statefulset/alertmanager-kube-prometheus-stack-alertmanager --timeout=300s >/dev/null
  install_chart loki
  install_chart alloy
  install_chart tempo
  install_chart opentelemetry-collector --set-string "config.exporters.googlecloud.project=$CONTRACT_PROJECT"
}

install_gitops() {
  install_chart argo-cd
  kubectl wait --for=condition=Established --timeout=120s \
    crd/applications.argoproj.io crd/appprojects.argoproj.io >/dev/null
  apply_full full/argocd-platform.yaml
  apply_full full/rbac-argocd-deployer.yaml
}

install_policies() {
  local repository=$1 repos="$WORK_DIR/allowed-repos.yaml" f kind
  install_chart gatekeeper
  retry 10 6 kubectl apply -f "$HERE/local/policies/templates/" >/dev/null || die "could not apply Gatekeeper ConstraintTemplates"
  while read -r kind; do
    retry 30 2 kubectl get crd "${kind,,}.constraints.gatekeeper.sh" >/dev/null 2>&1 || die "Gatekeeper did not create the CRD of $kind"
    kubectl wait --for=condition=Established "crd/${kind,,}.constraints.gatekeeper.sh" --timeout=60s >/dev/null
  done < <(sed -n 's/^        kind: \(Lab[A-Za-z]*\)$/\1/p' "$HERE"/local/policies/templates/*.yaml)
  for f in "$HERE"/local/policies/constraints/*.yaml; do
    [[ "$(basename "$f")" != allowed-repos.yaml ]] || continue
    retry 10 6 kubectl apply -f "$f" >/dev/null || die "could not apply Gatekeeper constraint $(basename "$f")"
  done
  sed "s|__ARTIFACT_REGISTRY_REPOSITORY__|$repository/|" "$HERE/full/policies/constraints/allowed-repos.yaml" >"$repos"
  retry 10 6 kubectl apply -f "$repos" >/dev/null || die "could not apply Gatekeeper constraint allowed-repos"
}

# Kyverno and its fail-closed image policy: only digests of the two dx03v2 repositories that carry the
# promotion attestation signed by deploy-gcp.yml start in the app namespace. Installed before Argo CD can
# sync the app, so the app never runs unverified.
install_image_admission() {
  install_chart kyverno
  kubectl wait --for=condition=Established --timeout=180s \
    crd/imagevalidatingpolicies.policies.kyverno.io >/dev/null
  kubectl --namespace kyverno rollout status deployment/kyverno-admission-controller --timeout=300s >/dev/null ||
    die "Kyverno's admission controller is not ready; image verification stays fail-closed"
  apply_full full/image-verification.yaml
}

# The Istio CRDs come with the managed Cloud Service Mesh (checked ACTIVE in main), but they can appear a
# few seconds after the fleet feature reports it.
install_app_security() {
  retry 30 5 kubectl get crd peerauthentications.security.istio.io authorizationpolicies.security.istio.io >/dev/null 2>&1 ||
    die "the Istio security CRDs of the managed Cloud Service Mesh are missing"
  apply_full full/app-security.yaml
}

install_backup() {
  local -a identity=()
  if [[ "$LAB_TARGET" == secondary ]]; then
    identity+=(--set-string serviceAccount.server.name=velero-dr)
  fi
  install_chart velero "${identity[@]}"
  # shellcheck disable=SC2016 # expanded by the inner bash
  retry 30 5 bash -c '[[ "$(kubectl -n velero get backupstoragelocation default -o jsonpath="{.status.phase}")" == Available ]]' ||
    die "Velero backup storage location is not Available (check the GKE Workload Identity bucket binding)"
  kubectl wait --for=condition=Established --timeout=120s \
    crd/volumesnapshotclasses.snapshot.storage.k8s.io crd/schedules.velero.io >/dev/null
  apply_full full/volume-snapshot-class.yaml
  if [[ "$LAB_TARGET" == secondary ]]; then
    kubectl apply -f - >/dev/null <<EOF
apiVersion: velero.io/v1
kind: BackupStorageLocation
metadata:
  name: primary-recovery
  namespace: velero
spec:
  provider: gcp
  accessMode: ReadOnly
  objectStorage:
    bucket: tx03v2-lab-velero-$CONTRACT_PROJECT
EOF
    # shellcheck disable=SC2016 # kubectl expands inside the retry shell, not this shell
    retry 30 5 bash -c '[[ "$(kubectl -n velero get backupstoragelocation primary-recovery -o jsonpath="{.status.phase}")" == Available ]]' ||
      die "Secondary Velero cannot read the primary multiregion recovery bucket"
  fi
}

install_full() {
  local repository
  require_cmd openssl curl
  load_pins "$HERE/local/versions.env" "$HERE/versions.env"
  VELERO_BUCKET="$LAB_NAME-velero-$CONTRACT_PROJECT"
  repository="$(contract artifact-registry/repository)"
  [[ "$repository" == *"-docker.pkg.dev/$CONTRACT_PROJECT/dx03v2" ]] ||
    die "contract key artifact-registry/repository is not the dx03v2 Artifact Registry repository"
  ARTIFACT_REPOSITORY="$repository"

  apply_full full/namespaces.yaml
  install_chart cert-manager
  install_app_security
  install_observability
  apply_full full/app-monitoring.yaml
  install_policies "$repository"
  install_image_admission
  install_gitops
  install_chart trivy-operator
  install_backup
  install_chart chaos-mesh
  log "profile full ready (GKE Autopilot: managed Cloud Service Mesh; Istio ambient, node-exporter and the Chaos Mesh daemon are not installed)"
}

main() {
  while (($# > 0)); do
    case "$1" in
      --profile) [[ "${2:-}" == core || "${2:-}" == full ]] || usage; PROFILE=$2; shift 2 ;;
      --github-owner) [[ "${2:-}" =~ $OWNER_RE ]] || usage; OWNER=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  [[ "$PROFILE" == core || -n "$OWNER" ]] || die "profile full requires --github-owner"
  local project contract_project region cluster deployer store deployers email extra
  require_cmd gcloud kubectl helm jq gke-gcloud-auth-plugin
  require_gcloud_login
  load_platform_versions
  select_lab_target "${LAB_TARGET:-primary}"
  project="$(lab_project)"
  mask "$project"
  WORK_DIR="$(mktemp -d)"
  trap cleanup EXIT

  load_contract "$project"
  contract_project="$(contract project-id)"
  [[ "$contract_project" == "$project" ]] || die "contract key project-id ($contract_project) differs from GCP_PROJECT_ID"
  region="$(contract region)"
  [[ "$region" =~ $REGION_RE ]] || die "contract key region is not a Google Cloud region"
  cluster="$(contract cluster-name)"
  [[ "$cluster" == "$LAB_NAME" ]] || die "contract key cluster-name is '$cluster', not $LAB_NAME"
  require_lab_cluster "$project" "$region" "$cluster"
  store="$(contract eso/cluster-secret-store)"
  [[ "$store" == "$SECRET_STORE" ]] ||
    die "contract key eso/cluster-secret-store is '$store' but platform/manifests creates $SECRET_STORE"
  deployer="$(contract deploy/service-account)"
  [[ "$deployer" =~ $EMAIL_RE ]] || die "contract key deploy/service-account is not a service account e-mail"
  mask "$deployer"
  deployers="$deployer"
  extra="$(emails_from_members "${APP_DEPLOYER_MEMBERS:-[]}")"
  while IFS= read -r email; do
    [[ -n "$email" ]] || continue
    mask "$email"
    deployers+=",$email"
  done <<<"$extra"
  CONTRACT_PROJECT="$project"
  DEPLOYERS="$deployers"

  if [[ "$PROFILE" == full ]]; then
    [[ "$(contract mesh/management)" == managed ]] ||
      die "profile full requires Terraform enable_managed_mesh=true and an active managed Cloud Service Mesh"
    [[ "$(contract dns/hostname)" != disabled && "$(contract dns/certificate-map)" == tx03v2-lab-app ]] ||
      die "profile full requires the global Certificate Map tx03v2-lab-app"
    gcloud container fleet mesh describe --project "$project" --format=json >"$WORK_DIR/mesh-status.json" ||
      die "cannot inspect the managed Cloud Service Mesh fleet feature"
    jq -e --arg cluster "$cluster" \
      '[.membershipStates | to_entries[] | select(.key | endswith("/memberships/" + $cluster)) | .value.servicemesh.controlPlaneManagement.state] | any(. == "ACTIVE")' \
      "$WORK_DIR/mesh-status.json" >/dev/null ||
      die "managed Cloud Service Mesh for $cluster is not ACTIVE yet; inspect the fleet feature before installing full"
    [[ "$(gcloud certificate-manager certificates describe tx03v2-lab-app --location=global --project "$project" --format='value(managed.state)')" == ACTIVE ]] ||
      die "Google-managed certificate tx03v2-lab-app is not ACTIVE"
  fi

  # Rendered before anything is installed: a malformed contract value stops the script here.
  "$HERE/render-manifests.sh" "$project" "$deployers" >"$WORK_DIR/manifests.yaml"

  log "cluster $cluster in $region"
  connect_cluster "$project" "$region" "$cluster"
  install_external_secrets
  log "applying platform/manifests"
  apply_manifests "$WORK_DIR/manifests.yaml"
  install_otel_collector "$project"
  # Ready means ESO reached Secret Manager with the identity of its controller ServiceAccount.
  kubectl wait --for=condition=Ready "clustersecretstore/$store" --timeout=180s
  log "platform ready: ClusterSecretStore $store, namespace dx03v2, OTLP endpoint opentelemetry-collector.$OTEL_NAMESPACE.svc:4318 (GatewayClass gke-l7-global-external-managed is managed by GKE)"
  if [[ "$PROFILE" == full ]]; then
    install_full
  fi
}

main "$@"
