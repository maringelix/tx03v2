# Autopilot supports Google-managed Cloud Service Mesh. No in-cluster Istio control plane or
# privileged user DaemonSet is installed by this lab. The same dedicated project is fleet host,
# network owner and cluster owner. Core keeps this optional to avoid mesh dataplane cost.
resource "google_gke_hub_membership" "lab" {
  count = var.enable_managed_mesh ? 1 : 0

  membership_id = local.name
  location      = var.region
  endpoint {
    gke_cluster {
      resource_link = "//container.googleapis.com/${module.gke.cluster_id}"
    }
  }
}

resource "google_gke_hub_feature" "mesh" {
  count = var.enable_managed_mesh ? 1 : 0

  name     = "servicemesh"
  location = "global"
}

resource "google_gke_hub_feature_membership" "mesh" {
  count = var.enable_managed_mesh ? 1 : 0

  location            = google_gke_hub_feature.mesh[0].location
  feature             = google_gke_hub_feature.mesh[0].name
  membership          = google_gke_hub_membership.lab[0].membership_id
  membership_location = google_gke_hub_membership.lab[0].location
  mesh {
    management = "MANAGEMENT_AUTOMATIC"
  }
}
