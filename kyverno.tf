resource "kubernetes_namespace_v1" "kyverno" {
  metadata {
    name = "kyverno"
  }

  depends_on = [null_resource.gke_api_ready, google_container_node_pool.default]
}

resource "helm_release" "kyverno" {
  name       = "kyverno"
  repository = "https://kyverno.github.io/kyverno/"
  chart      = "kyverno"
  version    = "3.5.3"
  namespace  = kubernetes_namespace_v1.kyverno.metadata[0].name

  values = [file("${path.module}/values/kyverno.yaml")]
}

resource "kubectl_manifest" "vendor_policies" {
  for_each = fileset(var.kyverno_policy_dir, "*.yaml")

  yaml_body = file("${var.kyverno_policy_dir}/${each.key}")

  depends_on = [
    helm_release.kyverno,
    helm_release.linkerd_control_plane,
  ]
}
