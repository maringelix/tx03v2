#!/usr/bin/env bash
# No cloud calls: a fake CLI proves current values, regional host rewriting, idempotency and refusal.
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
WORK="$(mktemp -d)"
trap 'rm -rf -- "${WORK:?}"' EXIT
export MOCK_DIR=$WORK
mkdir -p "$WORK/bin"
cat >"$WORK/bin/gcloud" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "secrets versions access latest --secret=tx03v2-lab-db-app "*)
    printf '%s' '{"username":"dx03v2","password":"CURRENT-FIXTURE","host":"primary.sql.goog","port":"5432","dbname":"dx03v2"}' ;;
  "secrets versions access latest --secret=tx03v2-lab-app-admin-token "*)
    printf '%048d' 1 ;;
  "secrets versions list "*)
    name=$4
    if [[ -f "$MOCK_DIR/$name" ]]; then printf '1'; fi ;;
  "secrets versions access latest --secret=tx03v2-lab-dr-"*)
    name="${5#--secret=}"
    cat "$MOCK_DIR/$name" ;;
  "secrets versions add "*)
    name=$4
    file=''
    for arg in "$@"; do [[ "$arg" != --data-file=* ]] || file="${arg#--data-file=}"; done
    [[ "$name" == tx03v2-lab-dr-db-app || "$name" == tx03v2-lab-dr-app-admin-token ]]
    cp "$file" "$MOCK_DIR/$name"
    printf 'write\n' >>"$MOCK_DIR/writes" ;;
  *) printf 'unexpected CLI call\n' >&2; exit 1 ;;
esac
MOCK
chmod +x "$WORK/bin/gcloud"
export PATH="$WORK/bin:$PATH" GCP_PROJECT_ID=tx03v2-lab-example
bash "$REPO_ROOT/scripts/sync-dr-secrets.sh" --db-host standby.us-east1.sql.goog
jq -e '.password == "CURRENT-FIXTURE" and .host == "standby.us-east1.sql.goog"' "$WORK/tx03v2-lab-dr-db-app" >/dev/null
[[ "$(wc -l <"$WORK/writes")" == 2 ]]
bash "$REPO_ROOT/scripts/sync-dr-secrets.sh" --db-host standby.us-east1.sql.goog
[[ "$(wc -l <"$WORK/writes")" == 2 ]]
if bash "$REPO_ROOT/scripts/sync-dr-secrets.sh" --db-host attacker.example.org >/dev/null 2>&1; then
  die 'arbitrary database target accepted'
fi
echo 'PASS current credentials, regional hostname, fixed owned secrets, idempotency and invalid target refusal'
