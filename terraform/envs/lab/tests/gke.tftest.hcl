# GKE Autopilot cluster of the contract: regional, release channel REGULAR, private nodes, no
# public IP endpoint, IAM-only DNS endpoint, Gateway API, Workload Identity Federation for GKE and
# the dedicated node service account.

mock_provider "google" {
  source = "../../tests/mocks"
}

variables {
  project_id             = "tx03v2-lab-example"
  deploy_service_account = "dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
}

override_resource {
  target = google_service_account.nodes
  values = {
    name   = "projects/tx03v2-lab-example/serviceAccounts/tx03v2-lab-nodes@tx03v2-lab-example.iam.gserviceaccount.com"
    email  = "tx03v2-lab-nodes@tx03v2-lab-example.iam.gserviceaccount.com"
    member = "serviceAccount:tx03v2-lab-nodes@tx03v2-lab-example.iam.gserviceaccount.com"
  }
}

run "cluster_follows_the_contract" {
  command = apply

  assert {
    condition = (
      module.gke.cluster_name == "tx03v2-lab" &&
      module.gke.location == "us-central1" &&
      module.gke.workload_pool == "tx03v2-lab-example.svc.id.goog"
    )
    error_message = "Cluster tx03v2-lab, regional in the lab region, workload pool <project_id>.svc.id.goog."
  }

  assert {
    condition     = google_service_account.nodes.account_id == "tx03v2-lab-nodes" && output.node_service_account == "tx03v2-lab-nodes@tx03v2-lab-example.iam.gserviceaccount.com"
    error_message = "Nodes run as tx03v2-lab-nodes, never the Compute Engine default service account."
  }
}

# modules/gke tested directly, so the resource arguments can be asserted.
run "autopilot_private_dns_endpoint_gateway" {
  command = apply

  module {
    source = "../../modules/gke"
  }

  variables {
    name                       = "tx03v2-lab"
    project_id                 = "tx03v2-lab-example"
    region                     = "us-central1"
    network_id                 = "projects/tx03v2-lab-example/global/networks/tx03v2-lab"
    subnetwork_id              = "projects/tx03v2-lab-example/regions/us-central1/subnetworks/tx03v2-lab-nodes"
    pods_range_name            = "pods"
    services_range_name        = "services"
    node_service_account_email = "tx03v2-lab-nodes@tx03v2-lab-example.iam.gserviceaccount.com"
  }

  assert {
    condition = (
      google_container_cluster.this.enable_autopilot == true &&
      google_container_cluster.this.location == "us-central1" &&
      google_container_cluster.this.release_channel[0].channel == "REGULAR" &&
      google_container_cluster.this.deletion_protection == false
    )
    error_message = "Autopilot, regional, channel REGULAR; deletion protection off (every lab round ends with a destroy)."
  }

  assert {
    condition = (
      google_container_cluster.this.private_cluster_config[0].enable_private_nodes == true &&
      google_container_cluster.this.private_cluster_config[0].enable_private_endpoint == true
    )
    error_message = "Nodes have private addresses only and the public IP endpoint of the control plane is off."
  }

  assert {
    condition = (
      length(google_container_cluster.this.master_authorized_networks_config) == 1 &&
      length(google_container_cluster.this.master_authorized_networks_config[0].cidr_blocks) == 0 &&
      google_container_cluster.this.master_authorized_networks_config[0].gcp_public_cidrs_access_enabled == false
    )
    error_message = "Authorized networks on, with no CIDR and no Google Cloud public IPs: the IP endpoints are closed to everything outside the VPC."
  }

  assert {
    condition = (
      google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].allow_external_traffic == true &&
      google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].enable_k8s_tokens_via_dns == false &&
      google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].enable_k8s_certs_via_dns == false
    )
    error_message = "The DNS endpoint accepts external traffic authorized by Google IAM only (no Kubernetes tokens or certificates through it)."
  }

  assert {
    condition     = google_container_cluster.this.gateway_api_config[0].channel == "CHANNEL_STANDARD"
    error_message = "Gateway API (standard channel) for the GKE Gateway controller."
  }

  assert {
    condition = (
      google_container_cluster.this.network == "projects/tx03v2-lab-example/global/networks/tx03v2-lab" &&
      google_container_cluster.this.subnetwork == "projects/tx03v2-lab-example/regions/us-central1/subnetworks/tx03v2-lab-nodes" &&
      google_container_cluster.this.ip_allocation_policy[0].cluster_secondary_range_name == "pods" &&
      google_container_cluster.this.ip_allocation_policy[0].services_secondary_range_name == "services"
    )
    error_message = "VPC-native cluster on the nodes subnet and its secondary ranges pods and services."
  }

  assert {
    condition = (
      google_container_cluster.this.workload_identity_config[0].workload_pool == "tx03v2-lab-example.svc.id.goog" &&
      google_container_cluster.this.cluster_autoscaling[0].auto_provisioning_defaults[0].service_account == "tx03v2-lab-nodes@tx03v2-lab-example.iam.gserviceaccount.com"
    )
    error_message = "Workload Identity Federation for GKE on the project pool; nodes run as the given service account."
  }

  assert {
    condition     = toset(google_container_cluster.this.logging_config[0].enable_components) == toset(["SYSTEM_COMPONENTS", "WORKLOADS"])
    error_message = "Logs of system components and workloads only (Cloud Logging bills per GB)."
  }
}
