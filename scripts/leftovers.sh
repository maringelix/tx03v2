#!/usr/bin/env bash
# Lists what the lab may have left behind after a destroy. Read-only (gcloud list calls).
#   BILLABLE   still costs money (or may) -> exit 1
#   ORPHANED   free, but blocks or confuses the next round (shown, exit code unaffected)
#   INFO       expected (bootstrap resources) or an API that is not enabled (nothing can exist there)
#   UNCHECKED  this identity may not read that list: the CI identities have project roles chosen
#              for the lab only, so run the script locally as the project Owner for a complete scan
# Usage: scripts/leftovers.sh [--retry-for SECONDS]   (needs gcloud logged in and GCP_PROJECT_ID)
#   --retry-for re-scans every 60 s until nothing billable remains or the time is up (deletions
#   still running right after a destroy). Exit 2 on usage or Google Cloud API errors.
# A dedicated project is assumed (docs/RUNBOOK.md): every cluster, instance, load balancer piece,
# address, disk, repository, secret, parameter and DNS zone in it counts.
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=scripts/lib/gcp.sh
source "$REPO_ROOT/scripts/lib/gcp.sh"

PROJECT=""
BILLABLE=0
UNCHECKED=0
WORK_DIR=""
declare -A SEEN=()

cleanup() {
  [[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
}

usage() {
  echo "usage: $0 [--retry-for SECONDS]   (GCP_PROJECT_ID must be set)" >&2
  exit 2
}

found() { # LEVEL WHAT ITEMS... (billable and orphaned items are reported once)
  local level=$1 what=$2 item key
  shift 2
  for item in "$@"; do
    [[ -n "$item" ]] || continue
    key="$what|$item"
    if [[ "$level" == BILLABLE || "$level" == ORPHANED ]]; then
      [[ -z "${SEEN[$key]:-}" ]] || continue
      SEEN[$key]=1
    fi
    printf '%-9s %-40s %s\n' "$level" "$what" "$item"
    if [[ "$level" == BILLABLE ]]; then
      BILLABLE=$((BILLABLE + 1))
    fi
  done
  return 0
}

# gcloud_items NAME WHAT ARGS... -> NAME=(non-empty output lines of `gcloud ARGS --project P`).
# A permission error marks WHAT as UNCHECKED; a disabled API means nothing of that kind can exist
# (INFO); any other error exits 2 (an API error is never read as "nothing left").
gcloud_items() {
  local -n _items=$1
  local what=$2 out rc=0 err="$WORK_DIR/gcloud.err"
  shift 2
  _items=()
  out="$(gcloud "$@" --project "$PROJECT" --quiet 2>"$err")" || rc=$?
  if ((rc != 0)); then
    if grep -qE 'SERVICE_DISABLED|has not been used in project|is disabled' "$err"; then
      printf '%-9s %-40s %s\n' INFO "$what" "API not enabled in the project: nothing of this kind exists"
      return 0
    fi
    if grep -qE 'PERMISSION_DENIED|does not have .*permission|Required .* permission|forbidden' "$err"; then
      printf '%-9s %-40s %s\n' UNCHECKED "$what" "this identity cannot list it (run the scan locally as the project Owner)"
      UNCHECKED=$((UNCHECKED + 1))
      return 0
    fi
    sed 's/^/  gcloud: /' "$err" >&2
    echo "error: $what: gcloud failed with exit code $rc" >&2
    exit 2
  fi
  out="$(lines <<<"$out")"
  [[ -z "$out" ]] || mapfile -t _items <<<"$out"
}

scan() {
  local -a items=() nats=()
  local entry name region
  gcloud_items items "GKE clusters" container clusters list --format='value(name,location)'
  found BILLABLE "GKE cluster" "${items[@]}"
  gcloud_items items "Cloud SQL instances" sql instances list --format='value(name,region)'
  found BILLABLE "Cloud SQL instance" "${items[@]}"
  # Backups retained after an instance deletion are billed until they expire or are deleted.
  gcloud_items items "Cloud SQL backups" sql backups list --format='value(name)'
  found BILLABLE "Cloud SQL backup (retained)" "${items[@]}"

  # Load balancer pieces created by the GKE Gateway controller (outside the Terraform state).
  gcloud_items items "forwarding rules" compute forwarding-rules list --format='value(name,region.basename())'
  found BILLABLE "forwarding rule" "${items[@]}"
  gcloud_items items "target HTTP proxies" compute target-http-proxies list --format='value(name)'
  found ORPHANED "target HTTP proxy" "${items[@]}"
  gcloud_items items "target HTTPS proxies" compute target-https-proxies list --format='value(name)'
  found ORPHANED "target HTTPS proxy" "${items[@]}"
  gcloud_items items "URL maps" compute url-maps list --format='value(name)'
  found ORPHANED "URL map" "${items[@]}"
  gcloud_items items "backend services" compute backend-services list --format='value(name)'
  found ORPHANED "backend service" "${items[@]}"
  gcloud_items items "health checks" compute health-checks list --format='value(name)'
  found ORPHANED "health check" "${items[@]}"
  gcloud_items items "network endpoint groups" compute network-endpoint-groups list --format='value(name,zone.basename())'
  found ORPHANED "network endpoint group" "${items[@]}"
  gcloud_items items "security policies" compute security-policies list --format='value(name)'
  found BILLABLE "Cloud Armor security policy" "${items[@]}"

  # Reserved addresses are billed, in use or not (global gateway address, PSC endpoint address).
  gcloud_items items "IP addresses" compute addresses list --format='value(name,region.basename())'
  found BILLABLE "reserved IP address" "${items[@]}"
  gcloud_items items "Cloud Routers" compute routers list --format='value(name,region.basename())'
  for entry in "${items[@]}"; do
    read -r name region <<<"$entry"
    found ORPHANED "Cloud Router" "$name $region"
    gcloud_items nats "Cloud NAT of $name" compute routers nats list --router "$name" --region "$region" --format='value(name)'
    found BILLABLE "Cloud NAT (router $name)" "${nats[@]}"
  done
  # PersistentVolumes with reclaimPolicy Retain survive the cluster as disks.
  gcloud_items items "persistent disks" compute disks list --format='value(name,zone.basename())'
  found BILLABLE "persistent disk" "${items[@]}"
  gcloud_items items "firewall rules created by GKE" compute firewall-rules list --filter='name~^(gke-|k8s)' --format='value(name)'
  found ORPHANED "firewall rule (GKE)" "${items[@]}"
  gcloud_items items "VPC networks" compute networks list --filter="name=$LAB_NAME" --format='value(name)'
  found ORPHANED "VPC network" "${items[@]}"

  gcloud_items items "Artifact Registry repositories" artifacts repositories list --format='value(name)'
  found BILLABLE "Artifact Registry repository" "${items[@]}"
  gcloud_items items "Secret Manager secrets" secrets list --format='value(name)'
  found BILLABLE "Secret Manager secret" "${items[@]}"
  gcloud_items items "Parameter Manager parameters" parametermanager parameters list --location=global --format='value(name)'
  found BILLABLE "Parameter Manager parameter" "${items[@]}"
  gcloud_items items "Cloud DNS zones" dns managed-zones list --format='value(name)'
  found BILLABLE "Cloud DNS managed zone" "${items[@]}"

  # Bootstrap resources (kept between rounds; removed only by the bootstrap teardown).
  gcloud_items items "state bucket" storage buckets list --filter="name~^$LAB_PROJECT-tfstate-" --format='value(name)'
  found INFO "bootstrap: state bucket (kept)" "${items[@]}"
  gcloud_items items "workload identity pools" iam workload-identity-pools list --location=global --format='value(name)'
  found INFO "bootstrap: workload identity pool (kept)" "${items[@]}"
  gcloud_items items "service accounts" iam service-accounts list --filter='email~^(tx03v2-gha-|dx03v2-gha-)' --format='value(email)'
  found INFO "bootstrap: service account (kept)" "${items[@]}"
  gcloud_items items "lab node service account" iam service-accounts list --filter="email~^$LAB_NAME-nodes@" --format='value(email)'
  found ORPHANED "service account of the lab nodes" "${items[@]}"
}

main() {
  local retry_for=0 deadline
  while (($# > 0)); do
    case "$1" in
      --retry-for)
        [[ "${2:-}" =~ ^[0-9]+$ ]] || usage
        retry_for=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  # Exit 2 (not 1) for setup problems, so they are never mistaken for "billable leftovers found".
  command -v gcloud >/dev/null 2>&1 || {
    echo "error: the Google Cloud CLI (gcloud) is required" >&2
    exit 2
  }
  [[ "${GCP_PROJECT_ID:-}" =~ $PROJECT_RE ]] || {
    echo "error: set GCP_PROJECT_ID to the project of the lab" >&2
    exit 2
  }
  PROJECT="$GCP_PROJECT_ID"
  [[ -n "$(gcloud auth list --filter=status:ACTIVE --format='value(account)')" ]] || {
    echo "error: gcloud is not logged in (gcloud auth login, or google-github-actions/auth in the workflow)" >&2
    exit 2
  }
  mask "$PROJECT"
  WORK_DIR="$(mktemp -d)"
  trap cleanup EXIT
  deadline=$((SECONDS + retry_for))
  while :; do
    BILLABLE=0
    UNCHECKED=0
    SEEN=()
    log "scanning the project for leftovers of $LAB_NAME ..."
    scan
    if ((UNCHECKED > 0)); then
      log "warning: $UNCHECKED list(s) were not possible with this identity: run scripts/leftovers.sh locally as the project Owner (docs/RUNBOOK.md)."
    fi
    if ((BILLABLE == 0)); then
      log "result: nothing billable left by $LAB_NAME in the scanned lists."
      return 0
    fi
    if ((SECONDS + 60 > deadline)); then
      log "result: $BILLABLE billable leftover(s). Delete them (docs/RUNBOOK.md, section sobras) and re-run."
      return 1
    fi
    log "$BILLABLE billable item(s) still present; re-scanning in 60 s"
    sleep 60
  done
}

main "$@"
