resource "google_artifact_registry_repository" "main" {
  project       = var.project_id
  location      = var.region
  repository_id = local.cluster_name
  format        = "DOCKER"
  labels        = local.default_labels
}

# Dedicated GKE node SA — replaces reliance on the default Compute Engine SA.
# Customers may have restricted or removed the default SA's roles; a dedicated
# SA with explicit least-privilege permissions avoids this issue.
resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = "${substr(var.nuon_id, 0, 20)}-gke"
  display_name = "GKE nodes for ${var.nuon_id}"
}

resource "google_artifact_registry_repository_iam_member" "gke_nodes_ar_reader" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.main.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}
