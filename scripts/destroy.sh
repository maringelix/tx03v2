#!/usr/bin/env bash
# Destroys the lab: the platform layer, terraform/envs/lab and the leftover check. CLOUD-MUTATING.
# Run by .github/workflows/terraform-destroy.yml (after the typed confirmation and the approval of
# the lab environment); by hand it needs the same environment as the workflow.
#   1. platform/uninstall.sh, when the cluster exists (it deletes the namespace dx03v2, so the GKE
#      Gateway controller deletes the load balancer it created outside the Terraform state). When it
#      fails (cluster API unreachable, controller stopped, timeout), or pieces of that load balancer
#      are still there, they are deleted through the Google Cloud API instead: only what
#      controller_leftovers lists (scripts/lib/gcp.sh), by name and network.
#   2. terraform init and destroy, also after a failed step 1: the VPC and the cluster go away even
#      when the controller could not clean up.
#   3. scripts/leftovers.sh --project ID --retry-for 900, whatever happened before.
# Exit code 0 only when terraform destroy and the leftover check both passed; a failed uninstall that
# the API cleanup recovered is a warning. Every failure is printed, nothing is ignored.
# usage: scripts/destroy.sh --project ID [--force-unlock LOCK_ID]
#   --project       the project of the lab; no variable of your shell (GCP_PROJECT_ID,
#                   CLOUDSDK_CORE_PROJECT) or gcloud configuration chooses it
#   --force-unlock  first removes the Terraform state lock of an interrupted apply or destroy (the
#                   lock object of the state bucket); LOCK_ID is the "ID" of the lock error message,
#                   a number (the generation of the lock object).
# Environment: TF_STATE_BUCKET, REGION (GCP_REGION of the workflow) and the TF_VAR_* variables of
# the lab (as in the workflow).
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=scripts/lib/gcp.sh
source "$REPO_ROOT/scripts/lib/gcp.sh"
export PATH="$REPO_ROOT/.tools/bin:$PATH"

TF_DIR="$REPO_ROOT/terraform/envs/lab"

usage() {
  echo "usage: $0 --project ID [--force-unlock LOCK_ID]" >&2
  exit 2
}

main() {
  local project="" force_unlock="" clusters cluster location target rc=0 uninstalled=1
  while (($# > 0)); do
    case "$1" in
      --project)
        [[ "${2:-}" =~ $PROJECT_RE ]] || usage
        project=$2
        shift 2
        ;;
      --force-unlock)
        [[ "${2:-}" =~ ^[0-9]{1,20}$ ]] || usage
        force_unlock=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  [[ -n "$project" ]] || usage
  require_cmd gcloud terraform
  require_gcloud_login
  [[ -n "${TF_STATE_BUCKET:-}" ]] || die "set TF_STATE_BUCKET to the state bucket of the bootstrap"
  [[ -z "${REGION:-}" || "$REGION" =~ $REGION_RE ]] || die "REGION '$REGION' is not a Google Cloud region"
  # The scripts called below read the project from the environment: the one named here wins.
  export GCP_PROJECT_ID="$project" CLOUDSDK_CORE_PROJECT="$project"

  clusters="$(gcloud container clusters list --project "$project" --filter="name~^$LAB_NAME(-dr)?$" \
    --format='value(name,location)')" || clusters=unknown
  if [[ "$clusters" == unknown ]]; then
    # Inventory failure must reach the API fallback and a failing leftover check, never a silent skip.
    uninstalled=0
  elif [[ -z "$clusters" ]]; then
    log "no primary or secondary lab cluster found: nothing to uninstall"
  else
    while read -r cluster location; do
      case "$cluster" in
        tx03v2-lab) target=primary ;;
        tx03v2-lab-dr) target=secondary ;;
        *) die 'cluster inventory returned a name outside the two lab runtimes' ;;
      esac
      # Older mock inventories omit location; only the known primary has a default.
      [[ -n "$location" ]] || location="${REGION:-$LAB_REGION_DEFAULT}"
      LAB_TARGET="$target" REGION="$location" bash "$REPO_ROOT/platform/uninstall.sh" || uninstalled=0
    done <<<"$clusters"
  fi
  if ((uninstalled == 0)) || [[ -n "$(controller_leftovers "$project" 2>/dev/null)" ]]; then
    log "warning: platform/uninstall.sh did not finish, or load balancer pieces of the lab are left; deleting them through the Google Cloud API"
    delete_controller_resources "$project" || rc=1
  fi

  terraform -chdir="$TF_DIR" init -input=false -lockfile=readonly \
    -backend-config="bucket=$TF_STATE_BUCKET" -backend-config="prefix=envs/lab" || rc=1
  if [[ -n "$force_unlock" ]]; then
    terraform -chdir="$TF_DIR" force-unlock -force "$force_unlock" || rc=1
  fi
  terraform -chdir="$TF_DIR" destroy -auto-approve -input=false -no-color || rc=1

  # The leftover check runs after a failed destroy too: it says what still costs money.
  bash "$REPO_ROOT/scripts/leftovers.sh" --project "$project" --retry-for 900 || rc=1
  return "$rc"
}

main "$@"
