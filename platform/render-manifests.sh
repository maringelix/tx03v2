#!/usr/bin/env bash
# Prints every platform/manifests/*.yaml as one multi-document YAML stream with the placeholders
# replaced. Used by platform/install.sh (| kubectl apply -f -) and by the harness
# (| kubeconform, contract-platform), so what is validated is exactly what gets applied. Needs no
# cluster.
# Usage: platform/render-manifests.sh <project-id> <deployer-email>[,<e-mail>...]
#   project-id         contract key project-id, e.g. tx03v2-lab-example
#   deployer e-mails   contract key deploy/service-account first, then the e-mails of
#                      app_deployer_members (without the user:/serviceAccount: prefix)
# Placeholders are replaced only in their one allowed position (a value would otherwise leak
# into comments or break the YAML):
#   a line that is exactly __DEPLOYER_SUBJECTS__   -> one `kind: User` subject per e-mail
#   `projectID: __PROJECT_ID__`                    -> the project ID
# Any other __NAME__ token left in the output is an error.
set -euo pipefail

# Google Cloud project IDs: 6-30 characters, lowercase letters, digits and hyphens, starting with a
# letter and not ending with a hyphen.
PROJECT_RE='^[a-z][a-z0-9-]{4,28}[a-z0-9]$'
# Google identities as Kubernetes RBAC sees them (users and service accounts, lowercase).
EMAIL_RE='^[a-z0-9][a-z0-9._%+-]*@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$'

usage() {
  echo "usage: $0 <project-id> <deployer-email>[,<e-mail>...]" >&2
  exit 2
}

main() {
  (($# == 2)) || usage
  local project=$1 emails=$2 dir f email line n name subjects="" out=""
  [[ "$project" =~ $PROJECT_RE ]] || {
    echo "error: '$project' is not a Google Cloud project ID" >&2
    exit 2
  }
  local -a deployers=()
  IFS=',' read -ra deployers <<<"$emails"
  ((${#deployers[@]} > 0)) || usage
  for email in "${deployers[@]}"; do
    [[ "$email" =~ $EMAIL_RE ]] || {
      echo "error: '$email' is not a lowercase e-mail address (the user:/serviceAccount: prefix is not part of it)" >&2
      exit 2
    }
    [[ "$subjects" == *"name: $email"$'\n'* ]] && continue
    subjects+="  - kind: User"$'\n'"    name: $email"$'\n'"    apiGroup: rbac.authorization.k8s.io"$'\n'
  done

  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/manifests"
  shopt -s nullglob
  local -a files=("$dir"/*.yaml)
  ((${#files[@]} > 0)) || {
    echo "error: no manifests in $dir" >&2
    exit 1
  }
  for f in "${files[@]}"; do
    name="platform/manifests/${f##*/}"
    out+="---"$'\n'"# Source: $name"$'\n'
    n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      n=$((n + 1))
      if [[ "$line" == "__DEPLOYER_SUBJECTS__" ]]; then
        out+="$subjects"
        continue
      fi
      if [[ "$line" =~ ^([[:space:]]*projectID:[[:space:]]+)__PROJECT_ID__$ ]]; then
        line="${BASH_REMATCH[1]}$project"
      fi
      if [[ "$line" =~ __[A-Z][A-Z0-9_]*__ ]]; then
        echo "error: $name:$n: placeholder ${BASH_REMATCH[0]} outside its allowed position" >&2
        exit 1
      fi
      out+="$line"$'\n'
    done <"$f"
  done
  printf '%s' "$out"
}

main "$@"
