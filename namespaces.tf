resource "kubernetes_namespace_v1" "main" {
  for_each = toset(local.namespaces)

  metadata {
    name   = each.value
    labels = local.default_labels
  }

  depends_on = [null_resource.gke_api_ready, google_container_node_pool.default]
}
