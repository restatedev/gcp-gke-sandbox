resource "google_artifact_registry_repository" "main" {
  project       = var.project_id
  location      = var.region
  repository_id = local.cluster_name
  format        = "DOCKER"
  labels        = local.default_labels
}

# Image pulls are performed by the kubelet using the node pool's SA, not
# the pod's Workload Identity SA. Grant the default Compute Engine SA
# reader access on the repo -- required on projects created after May 2024
# where the automatic Editor grant is disabled by org policy.
data "google_compute_default_service_account" "default" {
  project = var.project_id
}

resource "google_artifact_registry_repository_iam_member" "node_pull" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.main.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}
