output "network_id" {
  description = "VPC ID (projects/<project>/global/networks/<name>)."
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "VPC name (contract key network-name)."
  value       = google_compute_network.this.name
}

output "nodes_subnet_id" {
  description = "Nodes subnet ID."
  value       = google_compute_subnetwork.nodes.id
}

output "nodes_subnet_name" {
  description = "Nodes subnet name."
  value       = google_compute_subnetwork.nodes.name
}

output "nodes_subnet_cidr" {
  description = "Primary range of the nodes subnet (contract key nodes-subnet-cidr)."
  value       = google_compute_subnetwork.nodes.ip_cidr_range
}

output "pods_range_name" {
  description = "Name of the secondary range for Pods."
  value       = google_compute_subnetwork.nodes.secondary_ip_range[0].range_name
}

output "services_range_name" {
  description = "Name of the secondary range for Services."
  value       = google_compute_subnetwork.nodes.secondary_ip_range[1].range_name
}

output "gateway_address_name" {
  description = "Name of the global address of the Gateway (contract key gateway/address-name)."
  value       = google_compute_global_address.gateway.name
}

output "gateway_address" {
  description = "IPv4 of the global address of the Gateway (contract key gateway/address)."
  value       = google_compute_global_address.gateway.address
}
