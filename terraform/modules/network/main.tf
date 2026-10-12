# VPC of the lab (contract: tx03v2-lab, custom mode) with one subnet for the GKE nodes and its two
# secondary ranges (pods, services), Private Google Access (private nodes reach Google APIs
# without NAT), a Cloud Router + Cloud NAT for the egress of the private nodes, and the global
# external IPv4 address of the GKE Gateway (contract key gateway/address-name).
resource "google_compute_network" "this" {
  name                    = var.name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "nodes" {
  name                     = "${var.name}-nodes"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.nodes_subnet_cidr
  stack_type               = "IPV4_ONLY"
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

resource "google_compute_router" "this" {
  name    = var.name
  region  = var.region
  network = google_compute_network.this.id
}

# Egress of the private nodes (image pulls outside Google, external APIs). Only the nodes subnet,
# automatic NAT addresses, error logs only (logs are billed per GB).
resource "google_compute_router_nat" "this" {
  name                               = var.name
  region                             = var.region
  router                             = google_compute_router.this.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.nodes.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Global external IPv4 address of the GKE Gateway (spec.addresses NamedAddress in dx03v2). Global
# addresses are always on the Premium network tier (the resource has no network_tier argument).
resource "google_compute_global_address" "gateway" {
  name         = "${var.name}-gateway"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}
