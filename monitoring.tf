# -----------------------------------------------------------------------------
# Alerting for compliance (Vanta): instance CPU and Cloud IDS threats.
# -----------------------------------------------------------------------------

locals {
  alert_emails = toset([for e in split(",", var.alert_notification_emails) : trimspace(e) if trimspace(e) != ""])
}

resource "google_monitoring_notification_channel" "email" {
  for_each = local.alert_emails

  project      = var.project_id
  display_name = "${local.cluster_name} alerts: ${each.value}"
  type         = "email"
  labels       = { email_address = each.value }
}

# Project-wide, so it also covers VMs outside the cluster (the Nuon runner).
resource "google_monitoring_alert_policy" "instance_cpu" {
  project      = var.project_id
  display_name = "${local.cluster_name} compute instance CPU high"
  combiner     = "OR"
  user_labels  = local.default_labels

  conditions {
    display_name = "Mean CPU utilization above ${var.cpu_alert_threshold * 100}%"
    condition_threshold {
      filter          = "resource.type = \"gce_instance\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.cpu_alert_threshold
      duration        = "900s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [for c in google_monitoring_notification_channel.email : c.id]
}
