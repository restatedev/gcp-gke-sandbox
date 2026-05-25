# -----------------------------------------------------------------------------
# Cluster-scoped Kyverno policies for Restate namespaces.
#
# These were previously declared as Nuon [[policy]] entries in nuon-byoc's
# restate-byoc-gcp/policies.toml, but Nuon's `kubernetes_cluster` policy type
# isn't actually deploying them for this app (the install config state has no
# policies field), so they get installed here as part of the sandbox TF.
#
# Order:
#   1. helm_release.linkerd_crds      -- linkerd CRDs available for Kyverno
#                                        webhook validation
#   2. helm_release.kyverno           -- Kyverno controllers running
#   3. ClusterRoles                   -- grant the kyverno background controller
#                                        permission to create policy.linkerd.io
#                                        resources (Server, HTTPRoute,
#                                        AuthorizationPolicy)
#   4. ClusterPolicies                -- the mutate/generate rules themselves
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "kyverno_rbac_linkerd_view" {
  yaml_body = file("${path.module}/policies/rbac-linkerd-view.yml")

  depends_on = [helm_release.kyverno]
}

resource "kubectl_manifest" "kyverno_rbac_linkerd_manage" {
  yaml_body = file("${path.module}/policies/rbac-linkerd-manage.yml")

  depends_on = [helm_release.kyverno]
}

resource "kubectl_manifest" "kyverno_add_linkerd_annotation" {
  yaml_body = file("${path.module}/policies/add-linkerd-annotation-to-restate-namespaces.yml")

  depends_on = [
    helm_release.kyverno,
    helm_release.linkerd_crds,
  ]
}

resource "kubectl_manifest" "kyverno_linkerd_authz_for_restate" {
  yaml_body = file("${path.module}/policies/linkerd-authz-for-restate.yml")

  depends_on = [
    helm_release.kyverno,
    helm_release.linkerd_crds,
    kubectl_manifest.kyverno_rbac_linkerd_manage,
    kubectl_manifest.kyverno_rbac_linkerd_view,
  ]
}
