# -----------------------------------------------------------------------------
# Cloud IDS (optional, billed): one endpoint in one zone, fed by packet
# mirroring of the GKE subnet. Gated by var.enable_cloud_ids.
#
# Cloud IDS peers the VPC to Google's managed service network through private
# services access, so this allocates a range and creates that connection.
# -----------------------------------------------------------------------------

locals {
  cloud_ids_count               = var.enable_cloud_ids ? 1 : 0
  cloud_ids_zone                = var.cloud_ids_zone != "" ? var.cloud_ids_zone : sort(data.google_compute_zones.available.names)[0]
  gke_subnet_name               = element(split("/", local.subnetwork), length(split("/", local.subnetwork)) - 1)
  cloud_ids_mirror_cidr_ranges  = [for c in split(",", var.cloud_ids_mirror_cidr_ranges) : trimspace(c) if trimspace(c) != ""]
  cloud_ids_mirror_ip_protocols = [for p in split(",", var.cloud_ids_mirror_ip_protocols) : trimspace(p) if trimspace(p) != ""]
  cloud_ids_severities          = ["INFORMATIONAL", "LOW", "MEDIUM", "HIGH", "CRITICAL"]
  # Severities at or above cloud_ids_alert_min_severity, as a log filter clause; empty alerts on all.
  cloud_ids_alert_severity_filter = var.cloud_ids_alert_min_severity == "" ? "" : format(
    " AND jsonPayload.alert_severity=(%s)",
    join(" OR ", [for s in slice(local.cloud_ids_severities, index(local.cloud_ids_severities, var.cloud_ids_alert_min_severity), length(local.cloud_ids_severities)) : "\"${s}\""])
  )
  cloud_ids_mirror_filtered = (
    var.cloud_ids_mirror_direction != "BOTH" ||
    length(local.cloud_ids_mirror_cidr_ranges) > 0 ||
    length(local.cloud_ids_mirror_ip_protocols) > 0
  )
  # A packet mirroring policy takes at most 30 filters, counted as CIDR ranges times protocols.
  # A longer list is spread over several policies feeding the same endpoint; their CIDR filters
  # don't overlap, so each packet is mirrored once. The first policy keeps its original name.
  cloud_ids_mirror_ranges_per_policy = floor(30 / max(1, length(local.cloud_ids_mirror_ip_protocols)))
  cloud_ids_mirror_cidr_chunks = (
    length(local.cloud_ids_mirror_cidr_ranges) == 0
    ? [[]]
    : chunklist(local.cloud_ids_mirror_cidr_ranges, local.cloud_ids_mirror_ranges_per_policy)
  )
  cloud_ids_alert_excluded_threat_ids = [for t in split(",", var.cloud_ids_alert_excluded_threat_ids) : trimspace(t) if trimspace(t) != ""]
  # Signatures excluded from the threat alert, as a log filter clause; they are still logged.
  cloud_ids_alert_exclusion_filter = length(local.cloud_ids_alert_excluded_threat_ids) == 0 ? "" : format(
    " AND NOT jsonPayload.threat_id=(%s)",
    join(" OR ", [for t in local.cloud_ids_alert_excluded_threat_ids : "\"${t}\""])
  )
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
  count = local.cloud_ids_count * length(local.cloud_ids_mirror_cidr_chunks)

  project = var.project_id
  name    = count.index == 0 ? "${local.cluster_name}-ids-mirroring" : "${local.cluster_name}-ids-mirroring-${count.index}"
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

  # With none of the three variables set, no filter is rendered and the whole
  # subnet is mirrored, which is also what the provider does by default.
  dynamic "filter" {
    for_each = local.cloud_ids_mirror_filtered ? [1] : []
    content {
      direction    = var.cloud_ids_mirror_direction
      cidr_ranges  = local.cloud_ids_mirror_cidr_chunks[count.index]
      ip_protocols = local.cloud_ids_mirror_ip_protocols
    }
  }
}

# Threat alerting goes through a log-based metric rather than a log-match condition: Vanta's
# "Intrusion detection system notifications configured (GCP)" test looks for a logs-based metric
# on the Cloud IDS threat log with an alert policy on it, and does not recognise log-match
# policies. The filter follows the form Vanta's remediation gives.
resource "google_logging_metric" "cloud_ids_threat" {
  count = local.cloud_ids_count

  project = var.project_id
  name    = "${local.cluster_name}-cloud-ids-threats"
  filter  = "logName=\"projects/${var.project_id}/logs/ids.googleapis.com%2Fthreat\" AND resource.type=\"ids.googleapis.com/Endpoint\"${local.cloud_ids_alert_severity_filter}${local.cloud_ids_alert_exclusion_filter}"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

# A new resource name, so Terraform replaces the earlier log-match policy instead of updating it:
# the Monitoring API accepts an update that changes a condition's type (log match to threshold)
# but keeps the old condition, so an in-place update never takes effect.
resource "google_monitoring_alert_policy" "cloud_ids_threat_metric" {
  count = local.cloud_ids_count

  project      = var.project_id
  display_name = "${local.cluster_name} Cloud IDS threats (log-based metric)"
  combiner     = "OR"
  user_labels  = local.default_labels

  conditions {
    display_name = "Cloud IDS threats logged"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.cloud_ids_threat[0].name}\" AND resource.type=\"ids.googleapis.com/Endpoint\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  notification_channels = local.alert_channels
}
