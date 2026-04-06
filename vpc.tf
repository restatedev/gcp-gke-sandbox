# -----------------------------------------------------------------------------
# VPC (optional — created when no existing network is provided)
# -----------------------------------------------------------------------------

resource "google_compute_network" "main" {
  count = local.create_vpc ? 1 : 0

  project                 = var.project_id
  name                    = "${local.cluster_name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "gke" {
  count = local.create_vpc ? 1 : 0

  project       = var.project_id
  name          = "${local.cluster_name}-gke-subnet"
  region        = var.region
  network       = google_compute_network.main[0].id
  ip_cidr_range = var.subnet_cidr

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr_range
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr_range
  }

  private_ip_google_access = true
}

# Cloud Router + NAT for private GKE nodes
resource "google_compute_router" "main" {
  count = local.create_vpc ? 1 : 0

  project = var.project_id
  name    = "${local.cluster_name}-router"
  region  = var.region
  network = google_compute_network.main[0].id
}

resource "google_compute_router_nat" "main" {
  count = local.create_vpc ? 1 : 0

  project                            = var.project_id
  name                               = "${local.cluster_name}-nat"
  router                             = google_compute_router.main[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = false
    filter = "ERRORS_ONLY"
  }
}

data "google_compute_network" "existing" {
  count   = local.create_vpc ? 0 : 1
  project = var.project_id
  name    = var.network
}

locals {
  network           = local.create_vpc ? google_compute_network.main[0].id : data.google_compute_network.existing[0].id
  network_self_link = local.create_vpc ? google_compute_network.main[0].self_link : data.google_compute_network.existing[0].self_link
  subnetwork        = local.create_vpc ? google_compute_subnetwork.gke[0].id : var.subnetwork
}
