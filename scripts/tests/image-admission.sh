#!/usr/bin/env bash
# Parse the rendered policy structurally; runtime signature verification is a separate cloud proof.
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cmd helm jq
WORK="$(mktemp -d)"
trap 'rm -rf -- "${WORK:?}"' EXIT
mkdir -p "$WORK/chart/templates"
cat >"$WORK/chart/Chart.yaml" <<'YAML'
apiVersion: v2
name: image-policy-fixture
version: 0.1.0
YAML
cat >"$WORK/chart/templates/policy.yaml" <<'TPL'
{{ .Files.Get "policy.yaml" | fromYaml | toJson }}
TPL
validate() {
  cp "$1" "$WORK/chart/policy.yaml"
  helm template fixture "$WORK/chart" | sed '/^#/d; /^---$/d' | jq -e '
    .kind == "ImageValidatingPolicy" and
    .spec.evaluation.mode == "Kubernetes" and
    .spec.evaluation.background.enabled == false and
    .spec.failurePolicy == "Fail" and .spec.validationActions == ["Deny"] and
    .spec.matchConstraints.namespaceSelector.matchLabels["kubernetes.io/metadata.name"] == "dx03v2" and
    .spec.matchConstraints.resourceRules[0].resources == ["pods"] and
    .spec.matchConstraints.resourceRules[0].operations == ["CREATE", "UPDATE"] and
    .spec.matchImageReferences == [{"glob":"us-central1-docker.pkg.dev/tx03v2-lab-example/dx03v2/api@sha256:*"},{"glob":"us-central1-docker.pkg.dev/tx03v2-lab-example/dx03v2/web@sha256:*"}] and
    .spec.validationConfigurations.required == true and .spec.validationConfigurations.verifyDigest == true and
    .spec.credentials.providers == ["google"] and .spec.credentials.allowInsecureRegistry == false and
    .spec.attestors[0].cosign.keyless.identities == [{"subject":"https://github.com/example-owner/dx03v2/.github/workflows/deploy-gcp.yml@refs/heads/main","issuer":"https://token.actions.githubusercontent.com"}] and
    .spec.attestations[0].intoto.type == "https://github.com/maringelix/tx00v2/attestations/promoted-image/v1" and
    (.spec.validations[0].expression | gsub("\\s+"; "")) == "(images.containers+images.initContainers+images.ephemeralContainers).map(image,verifyAttestationSignatures(image,attestations.promotion,[attestors.github])>0).all(verified,verified)"
  ' >/dev/null
}
bash "$REPO_ROOT/platform/render-manifests.sh" tx03v2-lab-example \
  dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com --full example-owner \
  --artifact-registry-repository us-central1-docker.pkg.dev/tx03v2-lab-example/dx03v2 \
  --only full/image-verification.yaml >"$WORK/policy.yaml"
validate "$WORK/policy.yaml" || die 'rendered policy is not a fail-closed Kubernetes admission policy'
sed 's/mode: Kubernetes/mode: JSON/' "$WORK/policy.yaml" >"$WORK/json-mode.yaml"
if validate "$WORK/json-mode.yaml"; then die 'the Kubernetes policy check accepted JSON mode'; fi
sed 's/- Deny/- Audit/' "$WORK/policy.yaml" >"$WORK/audit-only.yaml"
if validate "$WORK/audit-only.yaml"; then die 'the Kubernetes policy check accepted audit-only admission'; fi
sed 's|github.com/example-owner/dx03v2|github.com/another-owner/dx03v2|' "$WORK/policy.yaml" >"$WORK/foreign-signer.yaml"
if validate "$WORK/foreign-signer.yaml"; then die 'the Kubernetes policy check accepted a foreign signer'; fi
sed 's/images.initContainers/[]/' "$WORK/policy.yaml" >"$WORK/missing-init.yaml"
if validate "$WORK/missing-init.yaml"; then die 'the Kubernetes policy check accepted missing init images'; fi
sed 's/images.ephemeralContainers/[]/' "$WORK/policy.yaml" >"$WORK/missing-ephemeral.yaml"
if validate "$WORK/missing-ephemeral.yaml"; then die 'the Kubernetes policy check accepted missing ephemeral images'; fi
# shellcheck disable=SC2016 # Match the literal installer shell variables.
new_gate="$(grep -nF 'retry 10 6 kubectl apply -f "$repos"' "$REPO_ROOT/platform/install.sh" | cut -d: -f1)"
old_gate="$(grep -nF 'kubectl delete laballowedrepos.constraints.gatekeeper.sh allowed-repos --ignore-not-found' "$REPO_ROOT/platform/install.sh" | cut -d: -f1)"
[[ "$new_gate" =~ ^[0-9]+$ && "$old_gate" =~ ^[0-9]+$ && "$new_gate" -lt "$old_gate" ]] ||
  die 'the old cloud constraint may be removed only after the replacement is enforced'
echo 'PASS parsed Kubernetes policy, all image groups and migration order; JSON/audit/foreign-signer/missing-group mutants rejected'
