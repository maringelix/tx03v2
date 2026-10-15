#!/usr/bin/env bash
# Offline test of scripts/destroy.sh with simulated gcloud, terraform, kubectl and helm: no Google
# Cloud account, no cluster, nothing is created. Proves what docs/GUARDRAILS.md (CUSTO-03) promises:
# a destroy whose platform uninstall fails still deletes, through the API, the load balancer pieces of
# the lab (and only those), still runs terraform destroy and still ends in the leftover check; a
# failed terraform destroy fails the run; a lock of an interrupted apply is released first.
# Run by the harness (check destroy-flow); usage: scripts/tests/destroy-flow.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILED=0
PROJECT="tx03v2-lab-example"
DESTROY_ARGS=(--project "$PROJECT")

# The scripts under test run from a copy of the tree: they put .tools/bin (the real terraform,
# kubectl and helm of the harness) in front of PATH, which would shadow the simulated CLIs.
make_sandbox() {
  mkdir -p "$WORK/repo/scripts" "$WORK/repo/platform"
  cp "$REPO_ROOT/scripts/destroy.sh" "$REPO_ROOT/scripts/leftovers.sh" "$WORK/repo/scripts/"
  cp -r "$REPO_ROOT/scripts/lib" "$WORK/repo/scripts/lib"
  cp "$REPO_ROOT/platform/uninstall.sh" "$WORK/repo/platform/"
}

# The pieces of the load balancer in the simulated project, one "kind|name|scope|network" line each:
# the ones of the lab (the names the Gateway controller gives them) and ones of other work.
write_pieces() {
  cat >"$WORK/pieces.initial" <<'EOF'
forwarding-rules|gkegw1-abcd1234-dx03v2-gateway-ef56|global|
target-http-proxies|gkegw1-abcd1234-dx03v2-gateway-ef56|global|
url-maps|gkegw1-abcd1234-dx03v2-gateway-ef56|global|
backend-services|gkegw1-abcd1234-dx03v2-web-8080-aa11|global|
health-checks|gkegw1-abcd1234-dx03v2-web-8080-aa11|global|
network-endpoint-groups|k8s1-abcd1234-dx03v2-web-8080-bb22|us-central1-a|tx03v2-lab
firewall-rules|gkegw1-l7--tx03v2-lab|global|tx03v2-lab
forwarding-rules|their-fr|us-east1|default
url-maps|gkegw1-zzzz1111-other-ns-gateway-9999|global|
firewall-rules|k8s-fw-their|global|default
EOF
}

make_fakes() {
  local bin="$WORK/bin"
  mkdir -p "$bin"
  # FAKE_CLUSTERS=0: no cluster. FAKE_PIECES=0: the controller left nothing. After a successful
  # terraform destroy the cluster is gone from the lists.
  cat >"$bin/gcloud" <<'EOF'
#!/usr/bin/env bash
args="$*"
echo "gcloud $args" >>"$FAKE_STATE/calls.log"

# list_pieces KIND -> the pieces of that kind, in the format the caller asked for.
list_pieces() {
  local kind=$1 k name scope home
  [[ -s "$FAKE_STATE/pieces" ]] || return 0
  while IFS='|' read -r k name scope home; do
    [[ "$k" == "$kind" ]] || continue
    [[ "$scope" != global ]] || scope=""
    if [[ "$args" == *labels.project* ]]; then
      printf '%s|%s||%s\n' "$name" "$scope" "$home"
    else
      printf '%s|%s|%s\n' "$name" "$scope" "$home"
    fi
  done <"$FAKE_STATE/pieces"
}

case "$1 $2 $3" in
  "auth list "*) echo "lab-operator@example.org" ;;
  "container clusters list")
    if [[ "${FAKE_CLUSTERS:-1}" == 1 && ! -f "$FAKE_STATE/destroyed" ]]; then
      case "$args" in
        *"--filter=name=tx03v2-lab"*) echo "tx03v2-lab" ;;
        *) echo "tx03v2-lab|us-central1|tx03v2|tx03v2-lab" ;;
      esac
    fi
    ;;
  "container clusters describe") echo "tx03v2" ;;
  "compute network-endpoint-groups list")
    # The filtered call of the uninstall waits for the controller to delete its NEGs: it did.
    case "$args" in
      *"--filter=name~dx03v2"*) : ;;
      *) list_pieces network-endpoint-groups ;;
    esac
    ;;
  "compute "*" list") list_pieces "$2" ;;
  "compute "*" delete")
    grep -v -F "$2|$4|" "$FAKE_STATE/pieces" >"$FAKE_STATE/pieces.new" || true
    mv "$FAKE_STATE/pieces.new" "$FAKE_STATE/pieces"
    ;;
  *) : ;;
esac
exit 0
EOF
  cat >"$bin/kubectl" <<'EOF'
#!/usr/bin/env bash
echo "kubectl $*" >>"$FAKE_STATE/calls.log"
if [[ "$*" == "get --raw /readyz" && "${FAKE_API_DOWN:-0}" == 1 ]]; then
  echo "the connection to the server was refused" >&2
  exit 1
fi
exit 0
EOF
  cat >"$bin/terraform" <<'EOF'
#!/usr/bin/env bash
echo "terraform $*" >>"$FAKE_STATE/calls.log"
if [[ " $* " == *" destroy "* ]]; then
  if [[ "${FAKE_TF_DESTROY_FAILS:-0}" == 1 ]]; then
    echo "Error: the destroy failed" >&2
    exit 1
  fi
  : >"$FAKE_STATE/destroyed"
fi
exit 0
EOF
  for tool in helm gke-gcloud-auth-plugin; do
    cat >"$bin/$tool" <<'EOF'
#!/usr/bin/env bash
echo "$(basename "$0") $*" >>"$FAKE_STATE/calls.log"
exit 0
EOF
  done
  # No retry loop is entered in a healthy run; one that is entered must not wait or spin here.
  cat >"$bin/sleep" <<'EOF'
#!/usr/bin/env bash
echo "the simulated sleep was called: a retry loop was entered" >&2
exit 1
EOF
  chmod +x "$bin"/*
}

# run_case NAME EXPECTED_EXIT [VAR=VALUE...] -> $WORK/<NAME>.out and $WORK/<NAME>.calls
run_case() {
  local name=$1 expected=$2 rc=0
  shift 2
  mkdir -p "$WORK/state"
  rm -f "$WORK/state"/*
  cp "$WORK/pieces.initial" "$WORK/state/pieces"
  env -u GITHUB_ACTIONS "$@" PATH="$WORK/bin:$PATH" FAKE_STATE="$WORK/state" TF_STATE_BUCKET=tx03v2-tfstate-0123abcd \
    GCP_PROJECT_ID=another-project-1 CLOUDSDK_CORE_PROJECT=another-project-2 \
    bash "$WORK/repo/scripts/destroy.sh" "${DESTROY_ARGS[@]}" >"$WORK/$name.out" 2>&1 || rc=$?
  if [[ -f "$WORK/state/calls.log" ]]; then cp "$WORK/state/calls.log" "$WORK/$name.calls"; else : >"$WORK/$name.calls"; fi
  if [[ "$rc" != "$expected" ]]; then
    echo "FAIL $name: exit code $rc, expected $expected"
    sed 's/^/    /' "$WORK/$name.out" | tail -n 25
    FAILED=1
  fi
}

line_of() { # NAME REGEX -> first line number of the calls of the case that matches REGEX
  grep -nE -- "$2" "$WORK/$1.calls" | head -n 1 | cut -d: -f1
}

expect() { # NAME DESCRIPTION CONDITION(0 = true)
  if [[ "$3" == 0 ]]; then echo "PASS $1: $2"; else echo "FAIL $1: $2"; FAILED=1; fi
}

absent() { # NAME REGEX -> 0 when no call of the case matches
  if [[ -z "$(line_of "$1" "$2")" ]]; then echo 0; else echo 1; fi
}

present() { # NAME REGEX -> 0 when a call of the case matches
  if [[ -n "$(line_of "$1" "$2")" ]]; then echo 0; else echo 1; fi
}

output_has() { # NAME TEXT -> 0 when the output of the case contains TEXT
  if grep -qF -- "$2" "$WORK/$1.out"; then echo 0; else echo 1; fi
}

ordered() { # NAME REGEX_A REGEX_B -> 0 when A exists and comes before B
  local a b
  a="$(line_of "$1" "$2")"
  b="$(line_of "$1" "$3")"
  if [[ -n "$a" && -n "$b" ]] && ((a < b)); then echo 0; else echo 1; fi
}

pieces_left() { # NAME -> the pieces of the simulated project after the case, one name per line
  cut -d'|' -f2 "$WORK/state/pieces" 2>/dev/null || true
}

# Both orders of a deletion are proved on one case: the controller pieces go in the order in which
# they can be deleted, and the other work of the project is never a target.
check_cleanup() { # NAME
  local n=$1 prev=forwarding-rules kind
  expect "$n" "the load balancer pieces of the lab are deleted through the API" \
    "$(present "$n" '^gcloud compute forwarding-rules delete gkegw1-abcd1234-dx03v2-gateway-ef56 --global ')"
  for kind in target-http-proxies url-maps backend-services health-checks network-endpoint-groups firewall-rules; do
    expect "$n" "$prev is deleted before $kind" \
      "$(ordered "$n" "^gcloud compute $prev delete " "^gcloud compute $kind delete ")"
    prev=$kind
  done
  expect "$n" "the network endpoint group is deleted in its zone" \
    "$(present "$n" '^gcloud compute network-endpoint-groups delete k8s1-abcd1234-dx03v2-web-8080-bb22 --zone us-central1-a ')"
  expect "$n" "terraform destroy runs after the pieces are gone" \
    "$(ordered "$n" '^gcloud compute firewall-rules delete ' '^terraform .*destroy')"
  expect "$n" "nothing of other work is deleted" \
    "$(absent "$n" 'delete (their-fr|gkegw1-zzzz1111-other-ns-gateway-9999|k8s-fw-their) ')"
  expect "$n" "the project still holds the pieces of other work" \
    "$(if [[ "$(pieces_left | sort | tr '\n' ' ')" == "gkegw1-zzzz1111-other-ns-gateway-9999 k8s-fw-their their-fr " ]]; then echo 0; else echo 1; fi)"
  expect "$n" "the leftover check lists the pieces of other work as INFO" \
    "$(if grep -qE "^INFO +forwarding rule \\(not the lab's\\) +their-fr us-east1" "$WORK/$n.out"; then echo 0; else echo 1; fi)"
}

main() {
  make_sandbox
  write_pieces
  make_fakes

  # 1. The controller did its job: the platform layer is uninstalled, nothing is left to delete.
  : >"$WORK/pieces.initial"
  run_case healthy 0
  expect healthy "the platform is uninstalled, then terraform destroy runs" \
    "$(ordered healthy 'helm uninstall' '^terraform .*destroy')"
  expect healthy "nothing is deleted through the API" "$(absent healthy '^gcloud compute .* delete ')"
  expect healthy "no warning about the uninstall" \
    "$(if grep -qF 'did not finish' "$WORK/healthy.out"; then echo 1; else echo 0; fi)"
  expect healthy "the leftover check runs after the destroy" \
    "$(ordered healthy '^terraform .*destroy' '^gcloud container clusters list .*value\[separator')"
  write_pieces

  # 2. The cluster API is unreachable: the uninstall fails, the pieces are deleted through the API,
  #    the destroy still runs, the leftover check runs and the run passes.
  run_case api-down 0 FAKE_API_DOWN=1
  expect api-down "the uninstall failure is reported as a warning" \
    "$(output_has api-down 'warning: platform/uninstall.sh did not finish')"
  check_cleanup api-down
  expect api-down "no gcloud call names a project of the environment" "$(absent api-down 'another-project')"
  expect api-down "every gcloud call (but the login check) names the project given by --project" \
    "$(if grep -E '^gcloud ' "$WORK/api-down.calls" | grep -v '^gcloud auth ' | grep -vq -- "--project $PROJECT"; then echo 1; else echo 0; fi)"

  # 3. The uninstall passed but pieces are still there (a controller that stopped halfway).
  run_case pieces-left 0
  expect pieces-left "pieces left after a good uninstall are deleted too" \
    "$(present pieces-left '^gcloud compute forwarding-rules delete gkegw1-abcd1234-dx03v2-gateway-ef56')"

  # 4. No cluster (deleted by hand): nothing to uninstall, the orphaned pieces are still removed.
  run_case no-cluster 0 FAKE_CLUSTERS=0
  expect no-cluster "the uninstall is skipped" "$(absent no-cluster '^kubectl ')"
  check_cleanup no-cluster

  # 5. terraform destroy fails: the run fails, and the leftover check still ran.
  run_case destroy-fails 1 FAKE_TF_DESTROY_FAILS=1
  expect destroy-fails "a failed terraform destroy fails the run" "$(output_has destroy-fails 'Error: the destroy failed')"
  expect destroy-fails "the leftover check runs after a failed destroy" \
    "$(ordered destroy-fails '^terraform .*destroy' '^gcloud container clusters list .*value\[separator')"

  # 6. An interrupted apply left a lock: --force-unlock removes it before the destroy.
  DESTROY_ARGS=(--project "$PROJECT" --force-unlock 1760461244183439)
  run_case lock 0
  DESTROY_ARGS=(--project "$PROJECT")
  expect lock "the lock is released before terraform destroy" \
    "$(ordered lock '^terraform .*force-unlock -force 1760461244183439' '^terraform .*destroy')"
  DESTROY_ARGS=(--project "$PROJECT" --force-unlock not-a-lock-id)
  run_case bad-lock 2
  DESTROY_ARGS=(--project "$PROJECT")
  expect bad-lock "a lock ID that is not a number is refused before anything runs" \
    "$(if [[ -s "$WORK/state/calls.log" ]]; then echo 1; else echo 0; fi)"

  # 7. The project is always explicit.
  DESTROY_ARGS=()
  run_case no-project 2
  DESTROY_ARGS=(--project "$PROJECT")
  expect no-project "no --project is a usage error" "$(output_has no-project 'usage:')"

  exit "$FAILED"
}

main "$@"
