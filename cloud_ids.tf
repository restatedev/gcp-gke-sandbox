# -----------------------------------------------------------------------------
# Cloud IDS (optional, billed): one endpoint in one zone, fed by packet
# mirroring of the GKE subnet. Gated by var.enable_cloud_ids.
#
# Cloud IDS peers the VPC to Google's managed service network through private
# services access, so this allocates a range and creates that connection.
# -----------------------------------------------------------------------------

locals {
  cloud_ids_count = var.enable_cloud_ids ? 1 : 0
  cloud_ids_zone  = var.cloud_ids_zone != "" ? var.cloud_ids_zone : sort(data.google_compute_zones.available.names)[0]
  gke_subnet_name = element(split("/", local.subnetwork), length(split("/", local.subnetwork)) - 1)
}

resource "google_project_service" "cloud_ids" {
  for_each = var.enable_cloud_ids ? toset(["ids.googleapis.com", "servicenetworking.googleapis.com"]) : toset([])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_global_address" "cloud_ids_psa" {
  count = local.cloud_ids_count

  project       = var.project_id
  name          = "${local.cluster_name}-ids-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.cloud_ids_psa_prefix_length
  network       = local.network
}

resource "google_service_networking_connection" "cloud_ids" {
  count = local.cloud_ids_count

  network                 = local.network
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.cloud_ids_psa[0].name]

  depends_on = [google_project_service.cloud_ids]
}

resource "google_cloud_ids_endpoint" "main" {
  count = local.cloud_ids_count

  project  = var.project_id
  name     = "${local.cluster_name}-ids"
  location = local.cloud_ids_zone
  network  = local.network
  severity = var.cloud_ids_severity

  depends_on = [google_service_networking_connection.cloud_ids]
}

data "google_compute_subnetwork" "gke" {
  count = local.cloud_ids_count

  project = var.project_id
  region  = var.region
  name    = local.gke_subnet_name
}

resource "google_compute_packet_mirroring" "cloud_ids" {
  count = local.cloud_ids_count

  project = var.project_id
  name    = "${local.cluster_name}-ids-mirroring"
  region  = var.region

  network {
    url = local.network_self_link
  }

  collector_ilb {
    url = google_cloud_ids_endpoint.main[0].endpoint_forwarding_rule
  }

  mirrored_resources {
    subnetworks {
      url = data.google_compute_subnetwork.gke[0].self_link
    }
  }
}

resource "google_monitoring_alert_policy" "cloud_ids_threat" {
  count = local.cloud_ids_count

  project      = var.project_id
  display_name = "${local.cluster_name} Cloud IDS threat detected"
  combiner     = "OR"
  user_labels  = local.default_labels

  conditions {
    display_name = "Cloud IDS threat log entry"
    condition_matched_log {
      filter = "resource.type=\"ids.googleapis.com/Endpoint\" AND log_id(\"ids.googleapis.com/threat\")"
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "3600s"
    }
  }

  notification_channels = [for c in google_monitoring_notification_channel.email : c.id]
}
