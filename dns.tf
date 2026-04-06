resource "google_dns_managed_zone" "public" {
  count = local.enable_nuon_dns && local.public_domain != "" ? 1 : 0

  project     = var.project_id
  name        = "${local.cluster_name}-public"
  dns_name    = "${local.public_domain}."
  description = "Public DNS zone for ${local.cluster_name}"
  labels      = local.default_labels
}

resource "google_dns_managed_zone" "internal" {
  count = local.internal_domain != "" ? 1 : 0

  project    = var.project_id
  name       = "${local.cluster_name}-internal"
  dns_name   = "${local.internal_domain}."
  visibility = "private"

  private_visibility_config {
    networks {
      network_url = local.network_self_link
    }
  }

  labels = local.default_labels
}
