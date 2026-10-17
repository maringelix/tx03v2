#!/usr/bin/env bash
# CLOUD-MUTATING: protected apply only. Read CURRENT credentials, never a new ephemeral password.
set -euo pipefail
set +x
# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=scripts/lib/gcp.sh
source "$REPO_ROOT/scripts/lib/gcp.sh"
require_cmd gcloud jq cmp
[[ $# == 2 && "$1" == --db-host && "$2" =~ ^[a-z0-9.-]+\.sql\.goog$ ]] ||
  die 'usage: sync-dr-secrets.sh --db-host <Terraform dr_db_hostname>'
HOST=$2
PROJECT="$(lab_project)"
umask 077
WORK="$(mktemp -d)"
trap 'rm -rf -- "${WORK:?}"' EXIT
# Do not print values, hashes, JSON, or upload WORK. The apply identity has exact-secret accessor.
gcloud secrets versions access latest --secret=tx03v2-lab-db-app --project "$PROJECT" >"$WORK/db"
gcloud secrets versions access latest --secret=tx03v2-lab-app-admin-token --project "$PROJECT" >"$WORK/admin"
jq -e --arg host "$HOST" '
  (keys | sort) == ["dbname","host","password","port","username"] and
  all(.[]; type == "string" and length > 0) and .port == "5432"
' "$WORK/db" >/dev/null || die 'primary DB credential schema is invalid'
jq -cS --arg host "$HOST" '.host = $host' "$WORK/db" >"$WORK/db-dr"
[[ "$(cat "$WORK/admin")" =~ ^[A-Za-z0-9]{48}$ ]] || die 'primary administrator token is invalid'
sync_value() {
  local name=$1 file=$2 versions
  versions="$(gcloud secrets versions list "$name" --project "$PROJECT" --filter=state:ENABLED --limit=1 --format='value(name)')"
  if [[ -n "$versions" ]]; then
    gcloud secrets versions access latest --secret="$name" --project "$PROJECT" >"$WORK/current"
    if cmp -s "$file" "$WORK/current"; then return; fi
  fi
  gcloud secrets versions add "$name" --project "$PROJECT" --data-file="$file" --quiet >/dev/null
}
sync_value tx03v2-lab-dr-db-app "$WORK/db-dr"
sync_value tx03v2-lab-dr-app-admin-token "$WORK/admin"
log 'DR credentials synchronized from the current primary; only the database hostname differs.'
