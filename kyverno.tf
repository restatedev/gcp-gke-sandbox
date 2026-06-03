resource "kubernetes_namespace_v1" "kyverno" {
  metadata {
    name = "kyverno"
  }

  depends_on = [google_container_node_pool.default]
}

resource "helm_release" "kyverno" {
  name       = "kyverno"
  repository = "https://kyverno.github.io/kyverno/"
  chart      = "kyverno"
  version    = "3.5.3"
  namespace  = kubernetes_namespace_v1.kyverno.metadata[0].name

  values = [file("${path.module}/values/kyverno.yaml")]
}
