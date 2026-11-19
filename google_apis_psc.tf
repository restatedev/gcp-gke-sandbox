# -----------------------------------------------------------------------------
# Google APIs through a Private Service Connect endpoint (optional).
#
# Gated by var.enable_google_apis_psc. Creates one PSC endpoint for the
# all-apis bundle at a fixed internal address, and private DNS zones that point
# googleapis.com, pkg.dev and gcr.io (apex and every subdomain) at it.
#
# Without it, Cloud Storage, Artifact Registry and the other Google APIs are
# reached on Google's public addresses, so Cloud IDS packet mirroring inspects
# and bills that traffic: it was about 80% of the inspected volume on a GKE
# install. Put the address inside a range that cloud_ids_mirror_cidr_ranges
# leaves out and the API traffic drops out of mirroring with no change to the
# filter. It does not need Cloud IDS and works on its own.
# -----------------------------------------------------------------------------

locals {
  google_apis_psc_count = var.enable_google_apis_psc ? 1 : 0
  # Every googleapis.com host, plus Artifact Registry and Container Registry,
  # which the all-apis bundle also serves.
  google_apis_psc_domains = var.enable_google_apis_psc ? toset(["googleapis.com", "pkg.dev", "gcr.io"]) : toset([])
}

resource "google_compute_global_address" "google_apis_psc" {
  count = local.google_apis_psc_count

  project      = var.project_id
  name         = "${local.cluster_name}-googleapis"
  purpose      = "PRIVATE_SERVICE_CONNECT"
  address_type = "INTERNAL"
  address      = var.google_apis_psc_address
  network      = local.network_self_link

  lifecycle {
    precondition {
      condition     = can(cidrhost("${var.google_apis_psc_address}/32", 0))
      error_message = "google_apis_psc_address must be an IPv4 address. Pick one outside every subnet range of the VPC."
    }
  }
}

resource "google_compute_global_forwarding_rule" "google_apis_psc" {
  count = local.google_apis_psc_count

  project = var.project_id
  # PSC endpoints for Google APIs take 1-20 lowercase letters and digits only.
  name                  = "psc${substr(sha1(local.cluster_name), 0, 17)}"
  network               = local.network_self_link
  ip_address            = google_compute_global_address.google_apis_psc[0].id
  target                = "all-apis"
  load_balancing_scheme = ""
}

resource "google_dns_managed_zone" "google_apis_psc" {
  for_each = local.google_apis_psc_domains

  project     = var.project_id
  name        = "${local.cluster_name}-psc-${replace(each.value, ".", "-")}"
  dns_name    = "${each.value}."
  visibility  = "private"
  description = "${each.value} through the Private Service Connect endpoint for Google APIs"

  private_visibility_config {
    networks {
      network_url = local.network_self_link
    }
  }

  labels = local.default_labels
}

resource "google_dns_record_set" "google_apis_psc_apex" {
  for_each = local.google_apis_psc_domains

  project      = var.project_id
  managed_zone = google_dns_managed_zone.google_apis_psc[each.value].name
  name         = "${each.value}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.google_apis_psc[0].address]
}

resource "google_dns_record_set" "google_apis_psc_wildcard" {
  for_each = local.google_apis_psc_domains

  project      = var.project_id
  managed_zone = google_dns_managed_zone.google_apis_psc[each.value].name
  name         = "*.${each.value}."
  type         = "CNAME"
  ttl          = 300
  rrdatas      = ["${each.value}."]
}
