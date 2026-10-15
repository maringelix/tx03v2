#!/usr/bin/env bash
# Offline test of scripts/leftovers.sh with a simulated gcloud: no Google Cloud account, nothing is
# read or created. Proves what docs/GUARDRAILS.md (SEC-17) promises about the leftover check: in a
# project that also holds other work, only the lab's resources are billable leftovers, the rest is
# INFO "(not the lab's)", every gcloud call names the project given on the command line (never one of
# the environment), and an API error is never read as "nothing left".
# Run by the harness (check leftovers-flow); usage: scripts/tests/leftovers-flow.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILED=0
PROJECT="tx03v2-lab-example"

# The script under test runs from a copy of the tree (the scripts put .tools/bin in front of PATH).
mkdir -p "$WORK/repo/scripts" "$WORK/bin" "$WORK/state"
cp "$REPO_ROOT/scripts/leftovers.sh" "$WORK/repo/scripts/"
cp -r "$REPO_ROOT/scripts/lib" "$WORK/repo/scripts/lib"

# The simulated gcloud answers what each list command of the scan would print with its --format:
# one "name|place|label|home" line per resource, or the plain value of the bootstrap lists.
# FAKE_SCENARIO: mixed = the lab and other work share the project; others = only other work;
# broken = the cluster list fails with an error that is not a permission or API-disabled one.
cat >"$WORK/bin/gcloud" <<'EOF'
#!/usr/bin/env bash
args="$*"
echo "gcloud $args" >>"$FAKE_STATE/calls.log"
lab() { [[ "$FAKE_SCENARIO" != others ]]; }
case "$1 $2 $3" in
  "auth list "*) echo "lab-operator@example.org" ;;
  "container clusters list")
    if [[ "$FAKE_SCENARIO" == broken ]]; then
      echo "ERROR: (gcloud.container.clusters.list) HTTPError 500: backend error" >&2
      exit 1
    fi
    if lab; then echo "tx03v2-lab|us-central1|tx03v2|tx03v2-lab"; fi
    echo "their-cluster|us-east1||default"
    ;;
  "sql instances list")
    if lab; then echo "tx03v2-lab-ab12cd34|us-central1|tx03v2"; fi
    echo "their-db|us-east1|"
    ;;
  "sql backups list")
    if lab; then echo "tx03v2-lab-ab12cd34|1700000000000"; fi
    echo "their-db|1699999999999"
    ;;
  "compute forwarding-rules list")
    if lab; then
      echo "gkegw1-abcd1234-dx03v2-gateway-ef56||"
      echo "tx03v2-lab-db|us-central1|tx03v2|tx03v2-lab"
    fi
    echo "their-fr|us-east1||default"
    echo "gkegw1-zzzz1111-other-ns-gateway-9999||"
    ;;
  "compute target-http-proxies list")
    if lab; then echo "gkegw1-abcd1234-dx03v2-gateway-ef56|||"; fi
    echo "their-proxy|||"
    ;;
  "compute target-https-proxies list") : ;;
  "compute url-maps list")
    if lab; then echo "gkegw1-abcd1234-dx03v2-gateway-ef56|||"; fi
    echo "their-urlmap|||"
    ;;
  "compute backend-services list")
    if lab; then echo "gkegw1-abcd1234-dx03v2-web-8080-aa11|||"; fi
    echo "their-bs|||"
    ;;
  "compute health-checks list")
    if lab; then echo "gkegw1-abcd1234-dx03v2-web-8080-aa11|||"; fi
    echo "their-hc|||"
    ;;
  "compute network-endpoint-groups list")
    if lab; then echo "k8s1-abcd1234-dx03v2-web-8080-bb22|us-central1-a||tx03v2-lab"; fi
    echo "their-neg|us-east1-b||default"
    ;;
  "compute security-policies list")
    if lab; then echo "tx03v2-lab-waf|||"; fi
    echo "their-armor|||"
    ;;
  "compute addresses list")
    if lab; then echo "tx03v2-lab-gateway|||"; fi
    echo "their-ip|us-east1||"
    ;;
  "compute routers list")
    if lab; then echo "tx03v2-lab|us-central1||tx03v2-lab"; fi
    echo "their-router|us-east1||default"
    ;;
  "compute routers nats")
    case "$args" in
      *"--router tx03v2-lab "*) echo "tx03v2-lab" ;;
      *) : ;;
    esac
    ;;
  "compute disks list")
    if lab; then
      echo "pvc-0123|us-central1-a||tx03v2-lab"
      echo "labelled-disk|us-central1-b|tx03v2|"
    fi
    echo "their-disk|us-east1-b|someone-else|"
    ;;
  "compute firewall-rules list")
    if lab; then echo "gke-tx03v2-lab-abc-all|||tx03v2-lab"; fi
    echo "k8s-fw-their|||default"
    ;;
  "compute networks list")
    if lab; then echo "tx03v2-lab"; fi
    ;;
  "artifacts repositories list")
    if lab; then echo "dx03v2|DOCKER|tx03v2"; fi
    echo "their-repo|DOCKER|"
    ;;
  "secrets list "*)
    if lab; then echo "tx03v2-lab-db-app|2026-10-14T00:00:00Z|tx03v2"; fi
    echo "their-secret|2026-01-01T00:00:00Z|"
    ;;
  "parametermanager parameters list")
    if lab; then echo "tx03v2-lab-contract|2026-10-14T00:00:00Z|tx03v2"; fi
    echo "their-param|2026-01-01T00:00:00Z|"
    ;;
  "dns managed-zones list")
    if lab; then echo "tx03v2-lab-sql|private|tx03v2"; fi
    echo "their-zone|public|"
    ;;
  "storage buckets list")
    if lab; then echo "tx03v2-tfstate-ab12cd34"; fi
    ;;
  "iam workload-identity-pools list")
    if lab; then echo "projects/1/locations/global/workloadIdentityPools/tx03v2-github"; fi
    ;;
  "iam service-accounts list")
    case "$args" in
      *"nodes@"*) if lab; then echo "tx03v2-lab-nodes@tx03v2-lab-example.iam.gserviceaccount.com"; fi ;;
      *) if lab; then echo "tx03v2-gha-plan@tx03v2-lab-example.iam.gserviceaccount.com"; fi ;;
    esac
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
    GCP_PROJECT_ID=another-project-1 CLOUDSDK_CORE_PROJECT=another-project-2 \
    bash "$WORK/repo/scripts/leftovers.sh" "$@" >"$WORK/$name.out" 2>&1 || rc=$?
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

no_call() { # NAME REGEX DESCRIPTION -> no gcloud call of the case matches REGEX
  if grep -qE -- "$2" "$WORK/$1.calls"; then echo "FAIL $1: $3"; FAILED=1; else echo "PASS $1: $3"; fi
}

main() {
  # 1. The lab and other work in the same project.
  run_case mixed 1 mixed --project "$PROJECT"
  has mixed '^BILLABLE +GKE cluster +tx03v2-lab us-central1' "the cluster of the lab is billable"
  has mixed '^BILLABLE +Cloud SQL instance +tx03v2-lab-ab12cd34 ' "the Cloud SQL instance of the lab is billable"
  has mixed '^BILLABLE +forwarding rule +gkegw1-abcd1234-dx03v2-gateway-ef56' "the forwarding rule of the Gateway controller is billable"
  has mixed '^BILLABLE +forwarding rule +tx03v2-lab-db us-central1' "the PSC forwarding rule of the lab is billable"
  has mixed '^ORPHANED +network endpoint group +k8s1-abcd1234-dx03v2-web-8080-bb22 us-central1-a' "the NEG of the lab is orphaned"
  has mixed '^ORPHANED +backend service +gkegw1-abcd1234-dx03v2-web-8080-aa11' "the backend service of the Gateway controller is orphaned"
  has mixed '^BILLABLE +Cloud Armor security policy +tx03v2-lab-waf' "the Cloud Armor policy of the lab is billable"
  has mixed '^BILLABLE +reserved IP address +tx03v2-lab-gateway' "the reserved address of the lab is billable"
  has mixed '^BILLABLE +Cloud NAT \(router tx03v2-lab\) +tx03v2-lab' "the Cloud NAT of the lab router is billable"
  has mixed '^BILLABLE +persistent disk +pvc-0123 us-central1-a' "a disk the cluster created (cluster label) is billable"
  has mixed '^BILLABLE +persistent disk +labelled-disk ' "a disk with the label project=tx03v2 is billable"
  has mixed '^ORPHANED +firewall rule \(GKE\) +gke-tx03v2-lab-abc-all' "the firewall rule of the cluster is orphaned"
  has mixed '^BILLABLE +Artifact Registry repository +dx03v2 ' "the repository with the label project=tx03v2 is billable"
  has mixed '^BILLABLE +Secret Manager secret +tx03v2-lab-db-app ' "the secret of the lab is billable"
  has mixed '^BILLABLE +Parameter Manager parameter +tx03v2-lab-contract ' "the contract parameter of the lab is billable"
  has mixed '^BILLABLE +Cloud DNS managed zone +tx03v2-lab-sql ' "the private zone of the lab is billable"
  lacks mixed '^(BILLABLE|ORPHANED).*(their-|someone-else|other-ns)' "nothing of other work is a leftover"
  has mixed "^INFO +GKE cluster \\(not the lab's\\) +their-cluster us-east1" "the cluster of other work is INFO"
  has mixed "^INFO +Cloud SQL instance \\(not the lab's\\) +their-db " "the database of other work is INFO"
  has mixed "^INFO +forwarding rule \\(not the lab's\\) +their-fr us-east1" "the forwarding rule of other work is INFO"
  has mixed "^INFO +forwarding rule \\(not the lab's\\) +gkegw1-zzzz1111-other-ns-gateway-9999" "a Gateway of another namespace is not the lab's"
  has mixed "^INFO +persistent disk \\(not the lab's\\) +their-disk " "the disk of other work is INFO"
  has mixed "^INFO +Cloud Router \\(not the lab's\\) +their-router us-east1" "the router of other work is INFO"
  has mixed "^INFO +Secret Manager secret \\(not the lab's\\) +their-secret " "the secret of other work is INFO"
  has mixed "^INFO +firewall rule \\(GKE\\) \\(not the lab's\\) +k8s-fw-their" "the firewall rule of another network is INFO"
  no_call mixed 'nats list --router their-router' "the NATs of a router that is not the lab's are not even listed"
  if grep -E '^gcloud ' "$WORK/mixed.calls" | grep -v '^gcloud auth ' | grep -vq -- "--project $PROJECT"; then
    echo "FAIL mixed: a gcloud call does not name the project of --project:"
    grep -E '^gcloud ' "$WORK/mixed.calls" | grep -v '^gcloud auth ' | grep -v -- "--project $PROJECT" | head -n 3
    FAILED=1
  else
    echo "PASS mixed: every gcloud call names the project given on the command line"
  fi
  if grep -q 'another-project' "$WORK/mixed.calls"; then
    echo "FAIL mixed: a project of the environment reached a gcloud call"
    FAILED=1
  else
    echo "PASS mixed: GCP_PROJECT_ID and CLOUDSDK_CORE_PROJECT of the shell decide nothing"
  fi

  # 2. Only other work in the project: nothing of the lab is left, the check passes.
  run_case others 0 others --project "$PROJECT"
  lacks others '^BILLABLE' "no billable leftover when only other work is there"
  has others "not the lab's" "the resources of other work are still listed, as INFO"

  # 3. The project is always explicit.
  run_case usage 2 others
  has usage '^usage:' "no --project is a usage error"
  run_case bad-usage 2 others --project "Not A Project"
  has bad-usage '^usage:' "a project that is not a project ID is a usage error"

  # 4. An API error is never read as "nothing left".
  run_case broken 2 broken --project "$PROJECT"
  has broken 'gcloud failed with exit code' "a failed list exits 2 instead of passing"

  exit "$FAILED"
}

main "$@"
