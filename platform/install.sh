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
# nothing to install for it.
# CLOUD-MUTATING: run it only when you mean to (docs/RUNBOOK.md). Needs gcloud logged in (gcloud
# auth login, or google-github-actions/auth + setup-gcloud in the platform workflow) with the
# gke-gcloud-auth-plugin component, kubectl and helm (scripts/install-tools.sh kubectl helm), jq,
# and an identity with roles/container.admin (tx03v2-gha-apply) or Kubernetes cluster-admin.
# Reads the contract from Parameter Manager; nothing comes from the Terraform state. Environment:
#   GCP_PROJECT_ID        project of the lab (required; the script never guesses it)
#   APP_DEPLOYER_MEMBERS  JSON list of extra deployers (the Terraform variable app_deployer_members,
#                         e.g. ["user:you@example.com"]), default []; they become RoleBinding
#                         subjects by e-mail, without the user:/serviceAccount: prefix
# Re-running it upgrades in place.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/../scripts/lib/common.sh"
# shellcheck source=scripts/lib/gcp.sh
source "$REPO_ROOT/scripts/lib/gcp.sh"
export PATH="$REPO_ROOT/.tools/bin:$PATH"

ESO_NAMESPACE=external-secrets
OTEL_NAMESPACE=observability
OTEL_CHART_REPO="https://open-telemetry.github.io/opentelemetry-helm-charts"
SECRET_STORE=gcp-secret-manager
WORK_DIR=""

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

main() {
  (($# == 0)) || die "usage: $0 (configuration through environment variables, see the header)"
  local project contract_project region cluster deployer store deployers email extra
  require_cmd gcloud kubectl helm jq gke-gcloud-auth-plugin
  require_gcloud_login
  load_platform_versions
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
}

main "$@"
