resource "google_service_account" "restate" {
  account_id   = "${substr(var.nuon_id, 0, 20)}-rst"
  display_name = "Restate pods for ${var.nuon_id}"
}

resource "google_service_account" "secrets_accessor" {
  account_id   = "${substr(var.nuon_id, 0, 20)}-sec"
  display_name = "Secret accessor for ${var.nuon_id}"
}

resource "google_secret_manager_secret" "region_token" {
  project   = var.project_id
  secret_id = "restatecloudregiontoken_${var.nuon_id}"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "secrets_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.region_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.secrets_accessor.email}"
}

resource "google_service_account_iam_member" "secrets_accessor_wi_ingress" {
  service_account_id = google_service_account.secrets_accessor.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[restate-cloud-ingress/restate-cloud-ingress]"
  depends_on         = [google_container_cluster.autopilot]
}

resource "google_service_account_iam_member" "secrets_accessor_wi_tunnel" {
  service_account_id = google_service_account.secrets_accessor.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[restate-cloud-tunnel/restate-cloud-tunnel]"
  depends_on         = [google_container_cluster.autopilot]
}

# Dedicated SA for the Datadog OTel collector, kept separate from secrets_accessor
# so this third-party workload cannot read the region token. No secret bindings
# here: the nuon-byoc datadog_secret component grants this SA accessor on only the
# Datadog API key secret it creates. Only provisioned for installs that run the
# collector, so disabled installs carry no unused SA.
resource "google_service_account" "datadog_secrets_accessor" {
  count        = var.enable_datadog_collector ? 1 : 0
  account_id   = "${substr(var.nuon_id, 0, 20)}-dd"
  display_name = "Datadog secret accessor for ${var.nuon_id}"
}

resource "google_service_account_iam_member" "datadog_secrets_accessor_wi" {
  count              = var.enable_datadog_collector ? 1 : 0
  service_account_id = google_service_account.datadog_secrets_accessor[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[observability/datadog]"
  depends_on         = [google_container_cluster.autopilot]
}
