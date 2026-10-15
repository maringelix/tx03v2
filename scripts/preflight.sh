#!/usr/bin/env bash
# Refuses a project that holds work that is not the lab's. Read-only (gcloud list calls).
# The CI identity that applies the lab (tx03v2-gha-apply) has Editor, Secret Manager Admin, Artifact
# Registry Admin, Kubernetes Engine Admin and Service Account User on the whole project: it could
# change or delete a cluster, a database or a secret of other work in the same project. The lab
# therefore belongs in a project of its own (docs/RUNBOOK.md, section 1), and this script says so
# before the bootstrap and before every apply (terraform-apply runs it first).
# It lists the GKE clusters, the Cloud SQL instances and the Secret Manager secrets of the project;
# each one must be the lab's (lab_resource, scripts/lib/gcp.sh: the label project=tx03v2, a name
# tx03v2-lab*, the network tx03v2-lab). An API that is not enabled yet means nothing of that kind
# exists; any other error, a permission one included, exits 2: a project that could not be checked is
# not a dedicated one.
# Usage: scripts/preflight.sh --project ID   (needs gcloud logged in)
# Exit code: 0 dedicated, 1 holds other work, 2 usage or could not be checked.
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=scripts/lib/gcp.sh
source "$REPO_ROOT/scripts/lib/gcp.sh"

PROJECT=""
OTHERS=0
WORK_DIR=""

cleanup() {
  [[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
}

usage() {
  echo "usage: $0 --project ID" >&2
  exit 2
}

# list_rows WHAT GCLOUD_ARGS... -> the non-empty lines of a list command of the project.
list_rows() {
  local what=$1 out rc=0 err="$WORK_DIR/gcloud.err"
  shift
  out="$(gcloud "$@" --project "$PROJECT" --quiet 2>"$err")" || rc=$?
  if ((rc != 0)); then
    if grep -qE 'SERVICE_DISABLED|has not been used in project|is disabled|not enabled on project' "$err"; then
      return 0
    fi
    sed 's/^/  gcloud: /' "$err" >&2
    echo "error: $what: gcloud failed with exit code $rc, so the project could not be checked" >&2
    exit 2
  fi
  lines <<<"$out"
}

# check WHAT GCLOUD_ARGS... -> reports every resource of the list that is not the lab's. The command
# prints name|label|home per line (the value of the label project, and the network when it has one).
check() {
  local what=$1 rows name label home
  shift
  rows="$(list_rows "$what" "$@")" || exit 2
  while IFS='|' read -r name label home; do
    [[ -n "$name" ]] || continue
    if ! lab_resource "$name" "$label" "$home"; then
      printf '  %-24s %s\n' "$what" "$name"
      OTHERS=$((OTHERS + 1))
    fi
  done <<<"$rows"
}

main() {
  while (($# > 0)); do
    case "$1" in
      --project)
        [[ "${2:-}" =~ $PROJECT_RE ]] || usage
        PROJECT=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  [[ -n "$PROJECT" ]] || usage
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

  log "checking that the project holds only the lab's clusters, databases and secrets ..."
  check "GKE cluster" container clusters list \
    --format='value[separator="|"](name,resourceLabels.project,network)'
  check "Cloud SQL instance" sql instances list \
    --format='value[separator="|"](name,settings.userLabels.project)'
  check "Secret Manager secret" secrets list \
    --format='value[separator="|"](name.basename(),labels.project)'

  if ((OTHERS > 0)); then
    echo "error: the project holds $OTHERS resource(s) that are not the lab's (above). tx03v2-gha-apply has Editor, Secret Manager Admin and Service Account User on the whole project and could change or delete them: use a project dedicated to the lab (docs/RUNBOOK.md, section 1)." >&2
    exit 1
  fi
  log "result: the project holds nothing that is not the lab's."
}

main "$@"
