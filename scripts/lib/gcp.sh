# shellcheck shell=bash
# Google Cloud CLI helpers shared by platform/*.sh and scripts/leftovers.sh. Read-only calls only.
# Every function fails (non-zero) when the gcloud call fails: callers must never treat an API error
# as "nothing found". Requires gcloud logged in (gcloud auth login locally, or
# google-github-actions/auth + setup-gcloud in CI) and GCP_PROJECT_ID.
# The lab names are fixed by the contract (docs/CONTRATO.md) and never read from the environment: a
# shell that already exports CLUSTER_NAME, LAB_NAME or similar for other work must not retarget a
# script of the lab.
LAB_PROJECT=tx03v2
LAB_NAME=tx03v2-lab
# shellcheck disable=SC2034 # used by the scripts that source this file
LAB_REGION_DEFAULT="us-central1"
CONTRACT_PARAMETER=$LAB_NAME-contract
PROJECT_RE='^[a-z][a-z0-9-]{4,28}[a-z0-9]$'
# shellcheck disable=SC2034
REGION_RE='^[a-z]+-[a-z]+[0-9]+$'
EMAIL_RE='^[a-z0-9][a-z0-9._%+-]*@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$'
declare -gA CONTRACT=()

# mask VALUE -> hides an identifier (project ID or number, e-mail) in GitHub Actions logs, which
# are public for a public repository. Prints the workflow command on stdout: never call it inside $(...).
mask() {
  if [[ "${GITHUB_ACTIONS:-}" == true && -n "$1" ]]; then
    printf '::add-mask::%s\n' "$1"
  fi
}

# lab_project -> GCP_PROJECT_ID, validated (the scripts never guess the project).
lab_project() {
  [[ -n "${GCP_PROJECT_ID:-}" ]] || die "set GCP_PROJECT_ID to the project of the lab (the scripts never guess it)."
  [[ "$GCP_PROJECT_ID" =~ $PROJECT_RE ]] || die "GCP_PROJECT_ID '$GCP_PROJECT_ID' is not a Google Cloud project ID."
  printf '%s' "$GCP_PROJECT_ID"
}

# require_gcloud_login -> fails unless gcloud has an active credential.
require_gcloud_login() {
  local account
  account="$(gcloud auth list --filter=status:ACTIVE --format='value(account)')" ||
    die "cannot query the gcloud credentials."
  [[ -n "$account" ]] || die "gcloud is not logged in (gcloud auth login, or google-github-actions/auth in the workflow)."
}

# require_lab_cluster PROJECT REGION CLUSTER -> the GKE cluster exists and carries the label
# project=tx03v2 of the lab (a default label of the provider, terraform/envs/lab/providers.tf): a
# cluster of whoever runs the script is never touched, even one with the same name.
require_lab_cluster() {
  local label
  label="$(gcloud container clusters describe "$3" --location "$2" --project "$1" --format='value(resourceLabels.project)')" ||
    die "cannot read the GKE cluster $3 in $2"
  [[ "$label" == "$LAB_PROJECT" ]] ||
    die "refusing to touch the GKE cluster $3: it does not carry the label project=$LAB_PROJECT (not created by this lab)"
}

# lab_suffix PROJECT_ID -> contract suffix: first 8 hex characters of sha1(project ID).
lab_suffix() {
  local h
  if command -v sha1sum >/dev/null 2>&1; then
    h="$(printf '%s' "$1" | sha1sum)"
  else
    h="$(printf '%s' "$1" | shasum -a 1)"
  fi
  printf '%s' "${h:0:8}"
}

# load_contract PROJECT -> fills CONTRACT[<key>] from the latest version of the Parameter Manager
# parameter tx03v2-lab-contract (a flat JSON object of strings, docs/CONTRATO.md). Needs jq.
load_contract() {
  local project=$1 payload json key value
  payload="$(gcloud parametermanager parameters versions render latest \
    --parameter="$CONTRACT_PARAMETER" --location=global --project="$project" \
    --format='value(renderedPayload)')" ||
    die "cannot render $CONTRACT_PARAMETER (did terraform apply of terraform/envs/lab run? does this identity have roles/parametermanager.parameterAccessor?)"
  json="$(printf '%s' "$payload" | base64 -d)" || die "the payload of $CONTRACT_PARAMETER is not base64"
  jq -e 'type == "object" and ([.[] | type] | all(. == "string"))' >/dev/null <<<"$json" ||
    die "$CONTRACT_PARAMETER must be a JSON object of strings (docs/CONTRATO.md)"
  CONTRACT=()
  while IFS=$'\t' read -r key value; do
    [[ -n "$key" ]] || continue
    CONTRACT["$key"]="$value"
  done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<<"$json")
  ((${#CONTRACT[@]} > 0)) || die "no contract key in $CONTRACT_PARAMETER"
}

# contract KEY -> value of the contract key (load_contract first).
contract() {
  [[ -n "${CONTRACT[$1]:-}" ]] || die "contract key $1 is missing or empty in $CONTRACT_PARAMETER (docs/CONTRATO.md)"
  printf '%s' "${CONTRACT[$1]}"
}

# emails_from_members JSON -> the e-mails of a JSON list of IAM members such as
# ["user:you@example.com", "serviceAccount:x@<project>.iam.gserviceaccount.com"], one per line.
# Groups are refused: Google Groups for RBAC is not configured on the lab cluster, so a
# `group:` member could never match a RoleBinding subject of kind User.
emails_from_members() {
  local item email
  local -a items=()
  [[ "$1" =~ ^[[:space:]]*\[.*\][[:space:]]*$ ]] || die "expected a JSON list of IAM members, got: $1"
  mapfile -t items < <(grep -oE '"[^"]*"' <<<"$1" | tr -d '"')
  for item in "${items[@]}"; do
    case "$item" in
      user:* | serviceAccount:*) email="${item#*:}" ;;
      group:*) die "'$item': group members cannot be RoleBinding subjects (Google Groups for RBAC is not configured); list the users instead" ;;
      *) die "'$item' is not an IAM member of the form user:<e-mail> or serviceAccount:<e-mail>" ;;
    esac
    [[ "$email" =~ $EMAIL_RE ]] || die "'$email' is not a lowercase e-mail address"
    printf '%s\n' "$email"
  done
}

# lines -> drops empty lines from gcloud value() output.
lines() {
  sed -e '/^[[:space:]]*$/d'
}
