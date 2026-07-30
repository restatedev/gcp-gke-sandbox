# Polls the GKE API server until it accepts our token. GKE returns
# google_container_cluster.autopilot as "complete" a beat before the auth
# webhook is fully accepting new tokens, causing sporadic 401 Unauthorized on
# the next kubernetes/kubectl/helm resource that runs (observed on Autopilot
# creation for a fresh customer project; a retried apply succeeded).
#
# We probe an *authenticated* endpoint (`/api`) rather than `/healthz` so we
# know both the API is up AND our identity's token is being accepted — the
# exact race we hit. Everything on the kubernetes side then depends on this
# instead of on the cluster resource directly.
resource "null_resource" "gke_api_ready" {
  triggers = {
    cluster_id = google_container_cluster.autopilot.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command     = <<-EOT
      set -e
      ca_file=$(mktemp)
      printf '%s' "$${CA}" | base64 -d > "$${ca_file}"
      trap 'rm -f "$${ca_file}"' EXIT

      for i in $(seq 1 60); do
        code=$(curl -sS -o /dev/null -w '%%{http_code}' \
          -H "Authorization: Bearer $${TOKEN}" \
          --cacert "$${ca_file}" \
          "https://$${HOST}/api")
        if [ "$${code}" = "200" ]; then
          echo "GKE API ready after attempt $${i}" >&2
          exit 0
        fi
        sleep 2
      done
      echo "GKE API did not accept our token within 120s (last HTTP=$${code})" >&2
      exit 1
    EOT
    environment = {
      HOST  = google_container_cluster.autopilot.endpoint
      TOKEN = data.google_client_config.default.access_token
      CA    = google_container_cluster.autopilot.master_auth[0].cluster_ca_certificate
    }
  }
}
