#!/usr/bin/env bash
# Offline target selection: reject arbitrary names, keep contracts and GitOps branches separate.
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=scripts/lib/gcp.sh
source "$REPO_ROOT/scripts/lib/gcp.sh"
select_lab_target primary
[[ "$LAB_NAME" == tx03v2-lab && "$CONTRACT_PARAMETER" == tx03v2-lab-contract ]]
select_lab_target secondary
[[ "$LAB_NAME" == tx03v2-lab-dr && "$CONTRACT_PARAMETER" == tx03v2-lab-dr-contract ]]
if (select_lab_target user-cluster) >/dev/null 2>&1; then die 'arbitrary target accepted'; fi
primary="$(LAB_TARGET=primary bash "$REPO_ROOT/platform/render-manifests.sh" tx03v2-lab-example \
  dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com --full example-owner \
  --artifact-registry-repository us-central1-docker.pkg.dev/tx03v2-lab-example/dx03v2)"
secondary="$(LAB_TARGET=secondary bash "$REPO_ROOT/platform/render-manifests.sh" tx03v2-lab-example \
  dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com --full example-owner \
  --artifact-registry-repository us-east1-docker.pkg.dev/tx03v2-lab-example/dx03v2)"
[[ "$primary" == *'dxRevision: gitops/gcp'* && "$primary" != *'gitops/gcp-dr'* ]]
[[ "$secondary" == *'dxRevision: gitops/gcp-dr'* ]]
echo 'PASS: only primary/secondary lab runtimes; separate contracts and GitOps revisions'
