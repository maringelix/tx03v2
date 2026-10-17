# GKE Autopilot cluster of the lab (contract: tx03v2-lab, regional, release channel REGULAR).
# - Private nodes; the public IP endpoint of the control plane is off (enable_private_endpoint).
# - The DNS-based endpoint (*.gke.goog) accepts external traffic: every request is authenticated
#   and authorized by Google IAM (container.clusters.connect), so no IP allowlist is needed for
#   GitHub-hosted runners or laptops. Kubernetes tokens and certificates through the DNS endpoint
#   stay off (Google identities only).
# - Gateway API (standard channel) for the GKE Gateway controller (gke-l7-global-external-managed).
# - Workload Identity Federation for GKE (always on in Autopilot): ESO is a principal by itself.
# - Nodes run as the service account tx03v2-lab-nodes (roles/container.defaultNodeServiceAccount
#   and Artifact Registry reader on the dx03v2 repository), never the Compute Engine default.
# Autopilot also brings Dataplane V2 (NetworkPolicy enforcement), Cloud DNS and NodeLocal DNSCache.
resource "google_container_cluster" "this" {
  name             = var.name
  location         = var.region
  enable_autopilot = true
  # Lab: every round ends with terraform destroy.
  deletion_protection = false

  network    = var.network_id
  subnetwork = var.subnetwork_id

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  release_channel {
    channel = "REGULAR"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    # A fixed range, so the firewall rule of the admission webhooks below names its source.
    master_ipv4_cidr_block = var.control_plane_cidr
  }

  # Authorized networks on with no CIDR and no Google Cloud public IPs: nothing outside the VPC
  # reaches the IP endpoints (CIS GKE 5.6.3). People and CI use the DNS endpoint below, which
  # authorized networks do not apply to (IAM decides).
  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false
  }

  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic    = true
      enable_k8s_tokens_via_dns = false
      enable_k8s_certs_via_dns  = false
    }
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = var.node_service_account_email
      oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }
}

# The control plane of a private cluster starts TCP connections to nodes and Pods only on 443 and
# 10250 (cert-manager, External Secrets and the Prometheus Operator listen on 10250). The admission
# webhooks of the full profile listen on other Pod ports, and the rule counts Pod ports, not Service
# ports: Gatekeeper on 8443, Kyverno and Chaos Mesh on 9443. Without this rule the API server cannot
# call them: Gatekeeper's policies are skipped and the fail-closed image verification of Kyverno
# blocks every Pod of the app. Only the control plane range reaches the Autopilot nodes (the node
# service account), and only on these two ports.
resource "google_compute_firewall" "control_plane_webhooks" {
  name        = "${var.name}-control-plane-webhooks"
  network     = var.network_id
  description = "GKE control plane to the admission webhooks of the ${var.name} full profile (Gatekeeper, Kyverno, Chaos Mesh)."
  direction   = "INGRESS"
  priority    = 1000

  source_ranges           = [var.control_plane_cidr]
  target_service_accounts = [var.node_service_account_email]

  allow {
    protocol = "tcp"
    ports    = ["8443", "9443"]
  }
}
