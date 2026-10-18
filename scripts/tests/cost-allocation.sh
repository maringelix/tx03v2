#!/usr/bin/env bash
# Exercise the actual allocation predicate and retry helper with simulated kubectl responses.
# No Docker, cloud, network request or real sleep; runtime integration is proved in the e2e job.
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=scripts/lib/platform.sh
source "$REPO_ROOT/scripts/lib/platform.sh"
require_cmd jq awk grep
WORK_DIR="$(mktemp -d)"
trap 'rm -rf -- "${WORK_DIR:?}"' EXIT
NS=lab-capacity
DRILL="$REPO_ROOT/scripts/local/capacity-drill.sh"
awk '/^allocation_positive\(\) \{$/ { copying = 1 }
  copying { print } copying && /^\}$/ { exit }' "$DRILL" >"$WORK_DIR/predicate.sh"
[[ -s "$WORK_DIR/predicate.sh" ]] || die 'allocation predicate missing from the real drill'
# shellcheck source=/dev/null
source "$WORK_DIR/predicate.sh"
grep -qxF 'if ! retry 7 30 allocation_positive; then' "$DRILL" ||
  die 'the actual cost probe must use seven attempts separated by thirty seconds'
grep -qF 'namespace:.properties.namespace,cpuCost,ramCost' "$DRILL" ||
  die 'exhausted allocation must report bounded synthetic namespace cost diagnostics'

# Keep the Pod exec/fetch contract visible. A failed HTTP request in Node propagates as this
# command failure; HTTP itself is not called by this fixture.
kubectl() {
  [[ "$#" == 8 && "$1" == -n && "$2" == "$NS" && "$3" == exec && "$4" == allocation &&
    "$5" == -- && "$6" == node && "$7" == -e ]] || return 2
  [[ "$8" == *'AbortSignal.timeout(15000)'* && "$8" == *'if(!r.ok)throw Error(r.status)'* ]] || return 2
  local count
  count="$(<"$WORK_DIR/attempts")"
  count=$((count + 1))
  printf '%s\n' "$count" >"$WORK_DIR/attempts"
  case "$CASE" in
    eventual)
      if ((count >= 3)); then
        printf '%s\n' '{"code":200,"data":[{"lab-capacity":{"name":"lab-capacity","cpuCost":0.0001,"ramCost":0.0002}}]}'
      else
        # A positive amount for some other namespace must never satisfy the probe.
        printf '%s\n' '{"code":200,"data":[{"other":{"name":"other","cpuCost":1,"ramCost":1},"lab-capacity":{"name":"lab-capacity","cpuCost":0,"ramCost":0}}]}'
      fi
      ;;
    zero) printf '%s\n' '{"code":200,"data":[{"lab-capacity":{"properties":{"namespace":"lab-capacity"},"cpuCost":0,"ramCost":0}}]}' ;;
    http-error) echo 'simulated HTTP 503 propagated by kubectl exec' >&2; return 1 ;;
    *) return 2 ;;
  esac
}
sleep() {
  [[ "$1" == 30 ]] || return 2
  printf '%s\n' "$1" >>"$WORK_DIR/sleeps"
}
run_case() {
  CASE=$1
  local expected=$2 attempts=$3 pauses=$4 rc=0
  printf '0\n' >"$WORK_DIR/attempts"
  : >"$WORK_DIR/sleeps"
  retry 7 30 allocation_positive >"$WORK_DIR/stdout" 2>"$WORK_DIR/stderr" || rc=$?
  [[ "$rc" == "$expected" && "$(<"$WORK_DIR/attempts")" == "$attempts" &&
    "$(wc -l <"$WORK_DIR/sleeps" | tr -d '[:space:]')" == "$pauses" ]] ||
    die "cost allocation $CASE returned $rc or unexpected attempt/sleep count"
}
run_case eventual 0 3 2
run_case zero 1 7 6
run_case http-error 1 7 6
echo 'PASS actual cost predicate: zero/foreign namespace -> positive, persistent zero and HTTP-command failure; retries bounded, no sleeps performed'
