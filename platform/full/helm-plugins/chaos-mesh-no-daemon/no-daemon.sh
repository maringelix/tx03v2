#!/usr/bin/env bash
# Chaos Mesh 2.8.4 has no values switch for its privileged daemon; remove only that DaemonSet
# while preserving the controller, CRDs, and API-driven PodChaos support for GKE Autopilot.
set -euo pipefail

awk '
  function flush_document() {
    if (document != "" && !(kind == "DaemonSet" && resource_name == "chaos-daemon")) {
      printf "%s", document
    }
    document = ""
    kind = ""
    resource_name = ""
  }
  /^---[[:space:]]*$/ {
    flush_document()
    document = $0 ORS
    next
  }
  {
    document = document $0 ORS
    if ($0 ~ /^kind:[[:space:]]*/) {
      kind = $0
      sub(/^kind:[[:space:]]*/, "", kind)
    } else if ($0 ~ /^  name:[[:space:]]*/) {
      resource_name = $0
      sub(/^  name:[[:space:]]*/, "", resource_name)
      gsub(/[\047\042]/, "", resource_name)
    }
  }
  END { flush_document() }
'
