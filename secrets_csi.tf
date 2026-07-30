resource "kubernetes_namespace_v1" "secrets_store" {
  metadata {
    name = "secrets-store-csi-driver"
  }

  depends_on = [null_resource.gke_api_ready, google_container_node_pool.default]
}

resource "helm_release" "secrets_store_csi" {
  name       = "secrets-store-csi-driver"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  version    = "1.4.7"
  namespace  = kubernetes_namespace_v1.secrets_store.metadata[0].name

  set = [{
    name  = "syncSecret.enabled"
    value = "true"
  }]
}

data "http" "secrets_store_gcp_provider" {
  url = "https://raw.githubusercontent.com/GoogleCloudPlatform/secrets-store-csi-driver-provider-gcp/v1.11.0/deploy/provider-gcp-plugin.yaml"
}

data "kubectl_file_documents" "secrets_store_gcp_provider" {
  content = data.http.secrets_store_gcp_provider.response_body
}

resource "kubectl_manifest" "secrets_store_gcp_provider" {
  for_each  = data.kubectl_file_documents.secrets_store_gcp_provider.manifests
  yaml_body = each.value

  depends_on = [helm_release.secrets_store_csi]
}
