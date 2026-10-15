#!/usr/bin/env bash
# Offline test of scripts/preflight.sh with a simulated gcloud: no Google Cloud account, nothing is
# read or created. Proves what docs/GUARDRAILS.md (SEC-18) promises: a project that holds a cluster,
# a Cloud SQL instance or a secret of other work is refused, a project with only the lab's (or with
# nothing, even with the APIs not enabled yet) passes, and a project that could not be checked is
# never reported as dedicated.
# Run by the harness (check preflight-flow); usage: scripts/tests/preflight-flow.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILED=0
PROJECT="tx03v2-lab-example"

mkdir -p "$WORK/repo/scripts" "$WORK/bin" "$WORK/state"
cp "$REPO_ROOT/scripts/preflight.sh" "$WORK/repo/scripts/"
cp -r "$REPO_ROOT/scripts/lib" "$WORK/repo/scripts/lib"

# FAKE_SCENARIO: lab = only the lab's resources; empty = nothing, the APIs are not enabled yet;
# mixed = the lab and other work; denied = the identity cannot list secrets.
cat >"$WORK/bin/gcloud" <<'EOF'
#!/usr/bin/env bash
echo "gcloud $*" >>"$FAKE_STATE/calls.log"
disabled() {
  echo "ERROR: (gcloud.$1) PERMISSION_DENIED: $2 API has not been used in project 123 before or it is disabled." >&2
  exit 1
}
case "$1 $2 $3" in
  "auth list "*) echo "lab-operator@example.org" ;;
  "container clusters list")
    [[ "$FAKE_SCENARIO" != empty ]] || disabled container.clusters.list "Kubernetes Engine"
    echo "tx03v2-lab|tx03v2|tx03v2-lab"
    [[ "$FAKE_SCENARIO" != mixed ]] || echo "their-cluster||default"
    ;;
  "sql instances list")
    [[ "$FAKE_SCENARIO" != empty ]] || disabled sql.instances.list "Cloud SQL Admin"
    echo "tx03v2-lab-ab12cd34|tx03v2"
    [[ "$FAKE_SCENARIO" != mixed ]] || echo "their-db|"
    ;;
  "secrets list "*)
    if [[ "$FAKE_SCENARIO" == denied ]]; then
      echo "ERROR: (gcloud.secrets.list) PERMISSION_DENIED: Permission 'secretmanager.secrets.list' denied" >&2
      exit 1
    fi
    [[ "$FAKE_SCENARIO" != empty ]] || disabled secrets.list "Secret Manager"
    echo "tx03v2-lab-db-app|tx03v2"
    [[ "$FAKE_SCENARIO" != mixed ]] || echo "their-secret|"
    ;;
  *) : ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/gcloud"

run_case() { # NAME EXPECTED_EXIT SCENARIO ARGS...
  local name=$1 expected=$2 scenario=$3 rc=0
  shift 3
  rm -f "$WORK/state/calls.log"
  env -u GITHUB_ACTIONS PATH="$WORK/bin:$PATH" FAKE_STATE="$WORK/state" FAKE_SCENARIO="$scenario" \
    GCP_PROJECT_ID=another-project-1 \
    bash "$WORK/repo/scripts/preflight.sh" "$@" >"$WORK/$name.out" 2>&1 || rc=$?
  if [[ -f "$WORK/state/calls.log" ]]; then cp "$WORK/state/calls.log" "$WORK/$name.calls"; else : >"$WORK/$name.calls"; fi
  if [[ "$rc" != "$expected" ]]; then
    echo "FAIL $name: exit code $rc, expected $expected"
    sed 's/^/    /' "$WORK/$name.out" | tail -n 25
    FAILED=1
  fi
}

has() { # NAME REGEX DESCRIPTION
  if grep -qE -- "$2" "$WORK/$1.out"; then echo "PASS $1: $3"; else echo "FAIL $1: $3"; FAILED=1; fi
}

lacks() { # NAME REGEX DESCRIPTION
  if grep -qE -- "$2" "$WORK/$1.out"; then echo "FAIL $1: $3"; FAILED=1; else echo "PASS $1: $3"; fi
}

main() {
  run_case lab 0 lab --project "$PROJECT"
  has lab 'result: the project holds nothing that is not the lab' "a project with only the lab's resources passes"

  run_case empty 0 empty --project "$PROJECT"
  has empty 'result: the project holds nothing' "a project whose APIs are not enabled yet passes (nothing exists there)"

  run_case mixed 1 mixed --project "$PROJECT"
  has mixed '^  GKE cluster +their-cluster$' "a cluster of other work is named and refused"
  has mixed '^  Cloud SQL instance +their-db$' "a database of other work is named and refused"
  has mixed '^  Secret Manager secret +their-secret$' "a secret of other work is named and refused"
  lacks mixed '^  .*(tx03v2-lab|tx03v2-lab-ab12cd34|tx03v2-lab-db-app)$' "the lab's own resources are not reported"
  has mixed 'use a project dedicated to the lab' "the refusal says what to do"

  run_case denied 2 denied --project "$PROJECT"
  has denied 'could not be checked' "a list the identity cannot read is never reported as dedicated"

  run_case usage 2 lab
  has usage '^usage:' "no --project is a usage error"
  if grep -q 'another-project' "$WORK/lab.calls"; then
    echo "FAIL lab: a project of the environment reached a gcloud call"
    FAILED=1
  else
    echo "PASS lab: GCP_PROJECT_ID of the shell decides nothing"
  fi

  exit "$FAILED"
}

main "$@"
