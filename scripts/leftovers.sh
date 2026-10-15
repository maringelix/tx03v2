#!/usr/bin/env bash
# Lists what the lab may have left behind after a destroy. Read-only (gcloud list calls).
#   BILLABLE   still costs money (or may) -> exit 1
#   ORPHANED   free, but blocks or confuses the next round (shown, exit code unaffected)
#   INFO       expected (bootstrap resources) or an API that is not enabled (nothing can exist there)
#   UNCHECKED  this identity may not read that list: the CI identities have project roles chosen
#              for the lab only, so run the script locally as the project Owner for a complete scan
# Usage: scripts/leftovers.sh --project ID [--retry-for SECONDS]   (needs gcloud logged in)
#   --project    the project of the lab, always explicit: every gcloud call names it, so no variable
#                of your shell (GCP_PROJECT_ID, CLOUDSDK_CORE_PROJECT) or gcloud configuration
#                decides what is scanned
#   --retry-for  re-scans every 60 s until nothing billable remains or the time is up (deletions
#                still running right after a destroy). Exit 2 on usage or Google Cloud API errors.
# Only what belongs to the lab counts as a leftover: a resource with the label project=tx03v2, named
# tx03v2-lab*, in the network tx03v2-lab, or a piece of the load balancer that the GKE controllers
# created for it (lab_resource, scripts/lib/gcp.sh). The same kinds of resource of any other work in
# the project are listed as INFO "(not the lab's)", never as something to delete.
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
  echo "usage: $0 --project ID [--retry-for SECONDS]" >&2
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

# The scoped lists print one line per resource, name|place|label|home: the value of the label
# project, and the network (or the cluster) the resource belongs to. A key that a resource does not
# have prints empty. The formats are the same for every list, so lab_resource decides in one place.
FORMAT_REGIONAL='value[separator="|"](name,region.basename(),labels.project,network.basename())'
FORMAT_ZONAL='value[separator="|"](name,zone.basename(),labels.project,network.basename())'
FORMAT_NAMED='value[separator="|"](name.basename(),createTime,labels.project)'

# scoped LEVEL WHAT GCLOUD_ARGS... -> runs one list command and sorts each resource: the lab's at
# LEVEL, the others as INFO "(not the lab's)". The command must print name|place|label|home.
scoped() {
  local level=$1 what=$2 line name place label home
  local -a items=()
  shift 2
  gcloud_items items "$what" "$@"
  for line in "${items[@]}"; do
    IFS='|' read -r name place label home <<<"$line"
    if lab_resource "$name" "$label" "$home"; then
      found "$level" "$what" "$name${place:+ $place}"
    else
      found INFO "$what (not the lab's)" "$name${place:+ $place}"
    fi
  done
}

scan() {
  local -a items=() nats=()
  local line name region label home
  scoped BILLABLE "GKE cluster" container clusters list \
    --format='value[separator="|"](name,location,resourceLabels.project,network)'
  scoped BILLABLE "Cloud SQL instance" sql instances list \
    --format='value[separator="|"](name,region,settings.userLabels.project)'
  # Backups retained after an instance deletion are billed until they expire or are deleted.
  scoped BILLABLE "Cloud SQL backup (retained)" sql backups list \
    --format='value[separator="|"](instance,id)'

  # Load balancer pieces created by the GKE Gateway controller (outside the Terraform state).
  scoped BILLABLE "forwarding rule" compute forwarding-rules list --format="$FORMAT_REGIONAL"
  scoped ORPHANED "target HTTP proxy" compute target-http-proxies list --format="$FORMAT_REGIONAL"
  scoped ORPHANED "target HTTPS proxy" compute target-https-proxies list --format="$FORMAT_REGIONAL"
  scoped ORPHANED "URL map" compute url-maps list --format="$FORMAT_REGIONAL"
  scoped ORPHANED "backend service" compute backend-services list --format="$FORMAT_REGIONAL"
  scoped ORPHANED "health check" compute health-checks list --format="$FORMAT_REGIONAL"
  scoped ORPHANED "network endpoint group" compute network-endpoint-groups list --format="$FORMAT_ZONAL"
  scoped BILLABLE "Cloud Armor security policy" compute security-policies list --format="$FORMAT_REGIONAL"

  # Reserved addresses are billed, in use or not (global gateway address, PSC endpoint address).
  scoped BILLABLE "reserved IP address" compute addresses list --format="$FORMAT_REGIONAL"
  gcloud_items items "Cloud Routers" compute routers list --format="$FORMAT_REGIONAL"
  for line in "${items[@]}"; do
    IFS='|' read -r name region label home <<<"$line"
    if lab_resource "$name" "$label" "$home"; then
      found ORPHANED "Cloud Router" "$name $region"
      gcloud_items nats "Cloud NAT of $name" compute routers nats list --router "$name" --region "$region" --format='value(name)'
      found BILLABLE "Cloud NAT (router $name)" "${nats[@]}"
    else
      found INFO "Cloud Router (not the lab's)" "$name $region"
    fi
  done
  # PersistentVolumes with reclaimPolicy Retain survive the cluster as disks. GKE puts the labels of
  # the cluster, and goog-k8s-cluster-name, on the disks it creates for it.
  scoped BILLABLE "persistent disk" compute disks list \
    --format='value[separator="|"](name,zone.basename(),labels.project,labels.goog-k8s-cluster-name)'
  scoped ORPHANED "firewall rule (GKE)" compute firewall-rules list --filter='name~^(gke-|k8s)' --format="$FORMAT_REGIONAL"
  gcloud_items items "VPC networks" compute networks list --filter="name=$LAB_NAME" --format='value(name)'
  found ORPHANED "VPC network" "${items[@]}"

  scoped BILLABLE "Artifact Registry repository" artifacts repositories list \
    --format='value[separator="|"](name.basename(),format,labels.project)'
  scoped BILLABLE "Secret Manager secret" secrets list --format="$FORMAT_NAMED"
  scoped BILLABLE "Parameter Manager parameter" parametermanager parameters list --location=global --format="$FORMAT_NAMED"
  scoped BILLABLE "Cloud DNS managed zone" dns managed-zones list \
    --format='value[separator="|"](name,visibility,labels.project)'

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
      --project)
        [[ "${2:-}" =~ $PROJECT_RE ]] || usage
        PROJECT=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  [[ -n "$PROJECT" ]] || usage
  # Exit 2 (not 1) for setup problems, so they are never mistaken for "billable leftovers found".
  command -v gcloud >/dev/null 2>&1 || {
    echo "error: the Google Cloud CLI (gcloud) is required" >&2
    exit 2
  }
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
