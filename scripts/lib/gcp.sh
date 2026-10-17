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

# Only these two lab-owned runtimes can be selected. Do not let arbitrary shell cluster/name
# variables retarget a write. Read-only inventory retains the primary prefix and includes both.
select_lab_target() {
  LAB_TARGET="${1:-primary}"
  case "$LAB_TARGET" in
    primary) LAB_NAME=tx03v2-lab ;;
    secondary) LAB_NAME=tx03v2-lab-dr ;;
    *) die 'LAB_TARGET must be primary or secondary' ;;
  esac
  CONTRACT_PARAMETER=$LAB_NAME-contract
  export LAB_TARGET
}
PROJECT_RE='^[a-z][a-z0-9-]{4,28}[a-z0-9]$'
# shellcheck disable=SC2034
REGION_RE='^[a-z]+-[a-z]+[0-9]+$'
EMAIL_RE='^[a-z0-9][a-z0-9._%+-]*@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$'
# The GKE Gateway controller names what it creates outside the Terraform state after the namespace of
# the app: gkegw1-<hash>-dx03v2-<gateway>-<hash> (forwarding rule, proxy, URL map, backend service,
# health check), k8s1-<hash>-dx03v2-<service>-<port>-<hash> (network endpoint group).
LAB_APP_NAMESPACE=dx03v2
CONTROLLER_RE="^(gkegw1|gkemcg1|k8s1|k8s2)-.*$LAB_APP_NAMESPACE"
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

# controller_owned NAME HOME -> success when the resource is a load balancer piece that the GKE
# controllers created for the lab: a name that carries the namespace of the app (CONTROLLER_RE), or a
# firewall rule of the controllers in the network of the lab. HOME is the network, or the cluster, the
# resource belongs to ("" when it has none).
controller_owned() {
  [[ "$1" =~ $CONTROLLER_RE ]] && return 0
  [[ "$2" == "$LAB_NAME" && "$1" =~ ^(gkegw1-|gkemcg1-|k8s1-|k8s2-|k8s-) ]]
}

# lab_resource NAME PROJECT_LABEL HOME -> success when a resource is the lab's, and only then: it
# carries the label project=tx03v2 (the provider puts it on everything that takes labels, and GKE
# copies the labels of the cluster to its disks), is named tx03v2-lab* (or gke-tx03v2-lab*, the
# firewall rules of the cluster), lives in the network of the lab, or is a piece of the load balancer
# the GKE controllers created for it. Everything else belongs to other work in the same project.
lab_resource() {
  local name=$1 label=$2 home=$3
  [[ "$label" == "$LAB_PROJECT" || "$home" == "$LAB_NAME" ]] && return 0
  [[ "$name" == "$LAB_NAME"* || "$name" == "gke-$LAB_NAME"* ]] && return 0
  controller_owned "$name" "$home"
}

# controller_leftovers PROJECT -> one "KIND NAME SCOPE" line per piece of the load balancer that the
# GKE controllers created for the lab and that still exists, in an order in which they can be deleted
# (a piece goes before what it refers to). KIND is the `gcloud compute` command group; SCOPE is
# global, a region or (network endpoint groups) a zone. Fails when a list fails: an API error is
# never read as "nothing left".
controller_leftovers() {
  local project=$1 kind key out name scope home
  for kind in forwarding-rules target-http-proxies target-https-proxies url-maps backend-services \
    health-checks network-endpoint-groups firewall-rules; do
    key='region.basename()'
    [[ "$kind" != network-endpoint-groups ]] || key='zone.basename()'
    out="$(gcloud compute "$kind" list --project "$project" --quiet \
      --format="value[separator=\"|\"](name,$key,network.basename())")" || return 1
    while IFS='|' read -r name scope home; do
      if [[ -n "$name" ]] && controller_owned "$name" "$home"; then
        printf '%s %s %s\n' "$kind" "$name" "${scope:-global}"
      fi
    done <<<"$out"
  done
}

# delete_controller_resources PROJECT -> deletes through the Google Cloud API what controller_leftovers
# lists (the controllers could not: the cluster API was unreachable, or the controller stopped). Only
# the pieces of the lab, by name and network; nothing else of the project is read as a target.
delete_controller_resources() {
  local project=$1 pieces kind name scope rc=0
  local -a where=()
  pieces="$(controller_leftovers "$project")" || die "cannot list the load balancer pieces of the project"
  while read -r kind name scope; do
    [[ -n "$kind" ]] || continue
    case "$kind" in
      network-endpoint-groups) where=(--zone "$scope") ;;
      firewall-rules) where=() ;;
      *)
        if [[ "$scope" == global ]]; then where=(--global); else where=(--region "$scope"); fi
        ;;
    esac
    log "deleting $kind $name ($scope)"
    gcloud compute "$kind" delete "$name" "${where[@]}" --project "$project" --quiet || rc=1
  done <<<"$pieces"
  return "$rc"
}
