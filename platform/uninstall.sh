#!/usr/bin/env bash
# Removes the platform layer before `terraform destroy`:
#   1. stops the Argo CD app-of-apps and app Application so self-heal cannot recreate the Gateway;
#   2. deletes the namespace dx03v2 (Gateway, HTTPRoutes, HealthCheckPolicies, GCPBackendPolicies,
#      Services): the GKE Gateway controller then deletes the load balancer it created outside the
#      Terraform state (forwarding rule, target proxy, URL map, backend services, health checks,
#      NEGs) and removes the Gateway finalizer, so the cluster must still be running;
#   3. waits until the namespace is gone and until no network endpoint group whose name contains
#      dx03v2 is left in the project (read-only gcloud polling; fails loudly on timeout);
#   4. uninstalls the releases of the profile full (none exists with the core profile), then deletes the
#      PersistentVolumeClaims of the monitoring namespace: their Persistent Disk volumes are not part
#      of the Terraform state and would outlive the cluster (billed until deleted);
#   5. uninstalls the OpenTelemetry Collector and the External Secrets Operator releases. The cluster
#      itself goes away with terraform destroy.
# CLOUD-MUTATING. Fails loudly on any error or timeout. Needs the same tools as platform/install.sh.
# GCP_PROJECT_ID is required; REGION defaults to us-central1. The cluster is the contract name
# (tx03v2-lab), so the teardown does not depend on the contract parameter; no environment variable
# changes it (a shell may export CLUSTER_NAME for other work), and the cluster must carry the label
# project=tx03v2. The kubeconfig is temporary: ~/.kube/config and its current context stay as they were.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/../scripts/lib/common.sh"
# shellcheck source=scripts/lib/gcp.sh
source "$REPO_ROOT/scripts/lib/gcp.sh"
export PATH="$REPO_ROOT/.tools/bin:$PATH"

REGION="${REGION:-$LAB_REGION_DEFAULT}"
CLUSTER_NAME=$LAB_NAME
APP_NAMESPACE=dx03v2
NAMESPACE_WAIT_SECONDS="${NAMESPACE_WAIT_SECONDS:-900}"
NEG_WAIT_SECONDS="${NEG_WAIT_SECONDS:-900}"
WORK_DIR=""
# "release namespace" of the profile full (platform/full/charts.txt), newest first.
FULL_RELEASES=(
  "chaos-mesh chaos-mesh" "velero velero" "trivy-operator trivy-system" "kyverno kyverno"
  "gatekeeper gatekeeper-system" "argocd argocd" "tempo monitoring" "alloy monitoring" "loki monitoring"
  "kube-prometheus-stack monitoring" "cert-manager cert-manager"
)

cleanup() {
  [[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
}

# namespace_exists -> success while the app namespace exists. API errors are fatal, never "gone".
namespace_exists() {
  local out
  out="$(kubectl get namespace "$APP_NAMESPACE" --ignore-not-found --output name)" ||
    die "cannot query the namespace $APP_NAMESPACE"
  [[ -n "$out" ]]
}

delete_app_namespace() {
  local deadline
  namespace_exists || {
    log "namespace $APP_NAMESPACE not found: nothing to delete"
    return 0
  }
  log "deleting namespace $APP_NAMESPACE (the Gateway controller removes its load balancer first)"
  kubectl delete namespace "$APP_NAMESPACE" --wait=false
  deadline=$((SECONDS + NAMESPACE_WAIT_SECONDS))
  while namespace_exists; do
    ((SECONDS < deadline)) ||
      die "namespace $APP_NAMESPACE still present after ${NAMESPACE_WAIT_SECONDS}s (Gateway finalizer?): kubectl get gateways,httproutes -n $APP_NAMESPACE"
    log "waiting for namespace $APP_NAMESPACE (Gateway finalizer, Services) to go"
    sleep 15
  done
  log "namespace $APP_NAMESPACE deleted"
}

stop_gitops() {
  local crd
  crd="$(kubectl get crd applications.argoproj.io --ignore-not-found -o name)" || die "cannot query the Argo CD Application CRD"
  [[ -n "$crd" ]] || return 0
  # Remove the parent first: it owns platform/gitops and would otherwise recreate the child app.
  kubectl -n argocd delete application platform --ignore-not-found --wait=false
  kubectl -n argocd delete application dx03v2 --ignore-not-found --wait=false
}

# app_negs PROJECT -> network endpoint groups (zonal NEGs of the Gateway controller, k8s1-*) whose
# name contains dx03v2, one "name zone" per line.
app_negs() {
  gcloud compute network-endpoint-groups list --project "$1" \
    --filter="name~$APP_NAMESPACE" --format='value(name,zone.basename())' | lines
}

wait_for_negs() {
  local project=$1 deadline remaining
  deadline=$((SECONDS + NEG_WAIT_SECONDS))
  while :; do
    remaining="$(app_negs "$project")" || die "cannot list the network endpoint groups of the project"
    if [[ -z "$remaining" ]]; then
      log "no network endpoint group of $APP_NAMESPACE left"
      return 0
    fi
    ((SECONDS < deadline)) ||
      die "network endpoint groups of $APP_NAMESPACE still present after ${NEG_WAIT_SECONDS}s:"$'\n'"$remaining"
    log "waiting for $(wc -l <<<"$remaining") network endpoint group(s) of $APP_NAMESPACE to be deleted"
    sleep 30
  done
}

uninstall_full_releases() {
  local entry
  for entry in "${FULL_RELEASES[@]}"; do
    helm uninstall "${entry% *}" --namespace "${entry#* }" --ignore-not-found --wait=watcher --timeout 10m
  done
}

# The Persistent Disk volumes of Prometheus, Alertmanager, Grafana, Loki and Tempo: deleted with their
# claims once the releases are gone, so no disk outlives the cluster.
delete_monitoring_pvcs() {
  local namespace left
  namespace="$(kubectl get namespace monitoring --ignore-not-found --output name)" ||
    die "cannot check the monitoring namespace before deleting PVCs"
  [[ -n "$namespace" ]] || return 0
  left="$(kubectl get pvc --namespace monitoring --output name)" || die "cannot list monitoring PVCs"
  [[ -z "$left" ]] && return 0
  log "deleting monitoring PVCs (Persistent Disk volumes of the full profile)"
  kubectl delete pvc --namespace monitoring --all --wait=true --timeout=10m
  left="$(kubectl get pvc --namespace monitoring --output name)" || die "cannot list monitoring PVCs after deletion"
  [[ -z "$left" ]] || die "monitoring PVCs remain after uninstall:"$'\n'"$left"
}

main() {
  (($# == 0)) || die "usage: $0 (configuration through environment variables, see the header)"
  local project
  require_cmd gcloud kubectl helm gke-gcloud-auth-plugin
  require_gcloud_login
  project="$(lab_project)"
  mask "$project"
  require_lab_cluster "$project" "$REGION" "$CLUSTER_NAME"
  WORK_DIR="$(mktemp -d)"
  trap cleanup EXIT

  export KUBECONFIG="$WORK_DIR/kubeconfig"
  gcloud container clusters get-credentials "$CLUSTER_NAME" --location "$REGION" --project "$project" --dns-endpoint --quiet ||
    die "cannot fetch the credentials of $CLUSTER_NAME"
  kubectl get --raw /readyz >/dev/null ||
    die "the DNS endpoint of $CLUSTER_NAME does not answer, or this identity has no Kubernetes access"

  stop_gitops
  delete_app_namespace
  wait_for_negs "$project"

  log "uninstalling the platform releases"
  uninstall_full_releases
  delete_monitoring_pvcs
  helm uninstall opentelemetry-collector --namespace observability --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall external-secrets --namespace external-secrets --ignore-not-found --wait=watcher --timeout 10m
  log "platform removed from $CLUSTER_NAME"
}

main "$@"
