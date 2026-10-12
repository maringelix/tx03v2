#!/usr/bin/env bash
# Removes the platform layer before `terraform destroy`:
#   1. deletes the namespace dx03v2 (Gateway, HTTPRoutes, HealthCheckPolicies, GCPBackendPolicies,
#      Services): the GKE Gateway controller then deletes the load balancer it created outside the
#      Terraform state (forwarding rule, target proxy, URL map, backend services, health checks,
#      NEGs) and removes the Gateway finalizer, so the cluster must still be running;
#   2. waits until the namespace is gone and until no network endpoint group whose name contains
#      dx03v2 is left in the project (read-only gcloud polling; fails loudly on timeout);
#   3. uninstalls the External Secrets Operator release.
# CLOUD-MUTATING. Fails loudly on any error or timeout. Needs the same tools as platform/install.sh.
# GCP_PROJECT_ID is required; REGION and CLUSTER_NAME default to us-central1 and the contract name
# (tx03v2-lab): the teardown does not depend on the contract parameter.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/../scripts/lib/common.sh"
# shellcheck source=scripts/lib/gcp.sh
source "$REPO_ROOT/scripts/lib/gcp.sh"
export PATH="$REPO_ROOT/.tools/bin:$PATH"

REGION="${REGION:-$LAB_REGION_DEFAULT}"
CLUSTER_NAME="${CLUSTER_NAME:-$LAB_NAME}"
APP_NAMESPACE=dx03v2
NAMESPACE_WAIT_SECONDS="${NAMESPACE_WAIT_SECONDS:-900}"
NEG_WAIT_SECONDS="${NEG_WAIT_SECONDS:-900}"
WORK_DIR=""

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

main() {
  (($# == 0)) || die "usage: $0 (configuration through environment variables, see the header)"
  local project
  require_cmd gcloud kubectl helm gke-gcloud-auth-plugin
  require_gcloud_login
  project="$(lab_project)"
  mask "$project"
  WORK_DIR="$(mktemp -d)"
  trap cleanup EXIT

  export KUBECONFIG="$WORK_DIR/kubeconfig"
  gcloud container clusters get-credentials "$CLUSTER_NAME" --location "$REGION" --project "$project" --dns-endpoint --quiet ||
    die "cannot fetch the credentials of $CLUSTER_NAME"
  kubectl get --raw /readyz >/dev/null ||
    die "the DNS endpoint of $CLUSTER_NAME does not answer, or this identity has no Kubernetes access"

  delete_app_namespace
  wait_for_negs "$project"

  log "uninstalling the platform release"
  helm uninstall external-secrets --namespace external-secrets --ignore-not-found --wait=watcher --timeout 10m
  log "platform removed from $CLUSTER_NAME"
}

main "$@"
