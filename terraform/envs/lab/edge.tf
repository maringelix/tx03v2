# Optional public edge for the full profile. The fork owner delegates the Cloud DNS zone at their
# registrar. Certificate Manager proves domain control through DNS authorization and renews the
# certificate; the GKE global Gateway uses its Certificate Map (never a Kubernetes TLS Secret).
locals {
  public_edge_enabled = var.app_domain_name != ""
}

resource "google_dns_managed_zone" "app" {
  count = local.public_edge_enabled ? 1 : 0

  name        = "${local.name}-app"
  dns_name    = "${var.dns_zone_name}."
  description = "Public zone for the optional ${local.name} HTTPS app endpoint."
  visibility  = "public"
}

resource "google_certificate_manager_dns_authorization" "app" {
  count = local.public_edge_enabled ? 1 : 0

  name   = "${local.name}-app"
  domain = var.app_domain_name
}

resource "google_dns_record_set" "certificate_authorization" {
  count = local.public_edge_enabled ? 1 : 0

  managed_zone = google_dns_managed_zone.app[0].name
  name         = google_certificate_manager_dns_authorization.app[0].dns_resource_record[0].name
  type         = google_certificate_manager_dns_authorization.app[0].dns_resource_record[0].type
  ttl          = 300
  rrdatas      = [google_certificate_manager_dns_authorization.app[0].dns_resource_record[0].data]
}

resource "google_dns_record_set" "app" {
  count = local.public_edge_enabled ? 1 : 0

  managed_zone = google_dns_managed_zone.app[0].name
  name         = "${var.app_domain_name}."
  type         = "A"
  ttl          = 300
  rrdatas      = [var.active_region == "secondary" ? module.network_dr[0].gateway_address : module.network.gateway_address]
}

resource "google_certificate_manager_certificate" "app" {
  count = local.public_edge_enabled ? 1 : 0

  name = "${local.name}-app"
  managed {
    domains            = [var.app_domain_name]
    dns_authorizations = [google_certificate_manager_dns_authorization.app[0].id]
  }

  depends_on = [google_dns_record_set.certificate_authorization]
}

resource "google_certificate_manager_certificate_map" "app" {
  count = local.public_edge_enabled ? 1 : 0

  name = "${local.name}-app"
}

resource "google_certificate_manager_certificate_map_entry" "app" {
  count = local.public_edge_enabled ? 1 : 0

  name         = "${local.name}-app"
  map          = google_certificate_manager_certificate_map.app[0].name
  hostname     = var.app_domain_name
  certificates = [google_certificate_manager_certificate.app[0].id]
}
