# Inputs are validated by the calling root (terraform/envs/lab); this module trusts them.

variable "name" {
  description = "Name prefix of the lab (tx03v2-lab): VPC, router, NAT and the subnet <name>-nodes."
  type        = string
}

variable "region" {
  description = "Region of the subnet, router and NAT."
  type        = string
}

variable "nodes_subnet_cidr" {
  description = "Primary range of the nodes subnet (contract key nodes-subnet-cidr)."
  type        = string
}

variable "pods_cidr" {
  description = "Secondary range `pods` of the nodes subnet (GKE Pod IPs)."
  type        = string
}

variable "services_cidr" {
  description = "Secondary range `services` of the nodes subnet (GKE Service IPs)."
  type        = string
}
