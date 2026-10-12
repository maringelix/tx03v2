# Network of the contract: custom-mode VPC tx03v2-lab, the nodes subnet with its secondary ranges
# and Private Google Access, Cloud NAT limited to that subnet, and the global address of the
# Gateway. modules/network tested directly.

mock_provider "google" {
  source = "../../tests/mocks"
}

run "vpc_subnet_and_nat" {
  command = apply

  module {
    source = "../../modules/network"
  }

  variables {
    name              = "tx03v2-lab"
    region            = "us-central1"
    nodes_subnet_cidr = "10.30.0.0/20"
    pods_cidr         = "10.32.0.0/16"
    services_cidr     = "10.33.0.0/20"
  }

  assert {
    condition     = google_compute_network.this.name == "tx03v2-lab" && google_compute_network.this.auto_create_subnetworks == false
    error_message = "Custom-mode VPC tx03v2-lab (no automatic subnets in every region)."
  }

  assert {
    condition = (
      google_compute_subnetwork.nodes.name == "tx03v2-lab-nodes" &&
      google_compute_subnetwork.nodes.region == "us-central1" &&
      google_compute_subnetwork.nodes.ip_cidr_range == "10.30.0.0/20" &&
      google_compute_subnetwork.nodes.private_ip_google_access == true &&
      google_compute_subnetwork.nodes.stack_type == "IPV4_ONLY"
    )
    error_message = "Nodes subnet tx03v2-lab-nodes with Private Google Access (private nodes reach Google APIs without NAT)."
  }

  assert {
    condition = { for r in google_compute_subnetwork.nodes.secondary_ip_range : r.range_name => r.ip_cidr_range } == {
      pods     = "10.32.0.0/16"
      services = "10.33.0.0/20"
    }
    error_message = "Secondary ranges pods and services (VPC-native GKE)."
  }

  assert {
    condition = (
      output.pods_range_name == "pods" && output.services_range_name == "services" &&
      output.network_name == "tx03v2-lab" && output.nodes_subnet_cidr == "10.30.0.0/20"
    )
    error_message = "The outputs must give the range names and the contract values."
  }

  assert {
    condition = (
      google_compute_router_nat.this.name == "tx03v2-lab" &&
      google_compute_router_nat.this.router == "tx03v2-lab" &&
      google_compute_router_nat.this.nat_ip_allocate_option == "AUTO_ONLY" &&
      google_compute_router_nat.this.source_subnetwork_ip_ranges_to_nat == "LIST_OF_SUBNETWORKS" &&
      length(google_compute_router_nat.this.subnetwork) == 1 &&
      one(google_compute_router_nat.this.subnetwork).name == google_compute_subnetwork.nodes.id
    )
    error_message = "Cloud NAT serves only the nodes subnet, with automatic addresses."
  }

  assert {
    condition     = google_compute_router_nat.this.log_config[0].enable == true && google_compute_router_nat.this.log_config[0].filter == "ERRORS_ONLY"
    error_message = "NAT logs errors only (logs are billed per GB)."
  }

  assert {
    condition = (
      google_compute_global_address.gateway.name == "tx03v2-lab-gateway" &&
      google_compute_global_address.gateway.address_type == "EXTERNAL" &&
      google_compute_global_address.gateway.ip_version == "IPV4" &&
      output.gateway_address_name == "tx03v2-lab-gateway"
    )
    error_message = "Global external IPv4 tx03v2-lab-gateway for the Gateway (contract key gateway/address-name)."
  }
}
