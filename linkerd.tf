locals {
  linkerd_egress_network_name = "all-egress"
}

# -----------------------------------------------------------------------------
# cert-manager
#
# Required by:
#   - ingress component: Certificate *.env.<domain>
#   - tunnel component:  Certificate *.tunnel.<domain>
#   - Linkerd:           identity issuer certificate rotation
# -----------------------------------------------------------------------------

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.17.2"
  namespace        = "cert-manager"
  create_namespace = true
  wait             = true
  wait_for_jobs    = true

  values = [yamlencode({
    crds = { enabled = true }
    # GKE: cainjector can take several minutes to inject the CA bundle into
    # the webhook configuration. The startupapicheck job retries until the
    # webhook is actually ready — with wait_for_jobs=true, Terraform blocks
    # here until it succeeds, so subsequent cert-manager resources are safe.
    startupapicheck = {
      timeout      = "5m"
      backoffLimit = 20
    }
    serviceAccount = {
      annotations = {
        "iam.gke.io/gcp-service-account" = google_service_account.cert_manager.email
      }
    }
    # Use public DNS for ACME DNS-01 propagation checks. GCP Cloud DNS private
    # zones shadow the entire subtree within the VPC, so cert-manager's default
    # in-cluster resolver returns NXDOMAIN for _acme-challenge records that are
    # in the public zone but under a domain with a private zone overlay.
    extraArgs = [
      "--dns01-recursive-nameservers=8.8.8.8:53,1.1.1.1:53",
      "--dns01-recursive-nameservers-only=true",
    ]
  })]

  depends_on = [google_container_cluster.autopilot, google_container_node_pool.default]
}

# -----------------------------------------------------------------------------
# Linkerd mTLS certificates
#
# Trust anchor: long-lived root CA (10 years), stored in state.
# Issuer cert:  shorter-lived intermediate CA (1 year), rotated by cert-manager.
# Both generated with the tls provider to avoid external tooling dependencies.
# -----------------------------------------------------------------------------

resource "tls_private_key" "linkerd_trust_anchor" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "linkerd_trust_anchor" {
  private_key_pem   = tls_private_key.linkerd_trust_anchor.private_key_pem
  is_ca_certificate = true

  subject {
    common_name = "root.linkerd.cluster.local"
  }

  validity_period_hours = 87600 # 10 years
  allowed_uses          = ["cert_signing", "crl_signing"]
}

resource "tls_private_key" "linkerd_issuer" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "linkerd_issuer" {
  private_key_pem = tls_private_key.linkerd_issuer.private_key_pem

  subject {
    common_name = "identity.linkerd.cluster.local"
  }
}

resource "tls_locally_signed_cert" "linkerd_issuer" {
  cert_request_pem      = tls_cert_request.linkerd_issuer.cert_request_pem
  ca_private_key_pem    = tls_private_key.linkerd_trust_anchor.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.linkerd_trust_anchor.cert_pem
  is_ca_certificate     = true
  validity_period_hours = 8760 # 1 year
  allowed_uses          = ["cert_signing"]
}

# -----------------------------------------------------------------------------
# Linkerd
#
# GKE Standard: proxy init container uses NET_ADMIN to set up iptables
# interception; no CNI plugin needed.
#
# Using the edge channel (helm.linkerd.io/edge) — EgressNetwork was added in
# Linkerd 2.17 (edge-26.2.1) and is not available in the stable channel.
# Edge releases are published frequently and are well-tested.
# -----------------------------------------------------------------------------

resource "helm_release" "linkerd_crds" {
  name             = "linkerd-crds"
  repository       = "https://helm.linkerd.io/edge"
  chart            = "linkerd-crds"
  version          = "2026.2.1"
  namespace        = "linkerd"
  create_namespace = true
  wait             = true

  values = [yamlencode({
    installGatewayAPI = true
  })]

  depends_on = [google_container_cluster.autopilot, google_container_node_pool.default]
}

resource "helm_release" "linkerd_control_plane" {
  name       = "linkerd-control-plane"
  repository = "https://helm.linkerd.io/edge"
  chart      = "linkerd-control-plane"
  version    = "2026.2.1"
  namespace  = "linkerd"
  wait       = true

  set = [
    {
      name  = "identityTrustAnchorsPEM"
      value = tls_self_signed_cert.linkerd_trust_anchor.cert_pem
    },
    {
      name  = "identity.issuer.tls.crtPEM"
      value = tls_locally_signed_cert.linkerd_issuer.cert_pem
    },
    {
      name  = "identity.issuer.tls.keyPEM"
      value = tls_private_key.linkerd_issuer.private_key_pem
    },
  ]

  depends_on = [helm_release.linkerd_crds]
}

# -----------------------------------------------------------------------------
# Linkerd egress
#
# EgressNetwork captures all non-RFC1918 outbound TLS so that TLSRoute rules
# in the tunnel component can intercept and route traffic to the proxy service
# instead of sending it directly to the internet.
# -----------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "linkerd_egress" {
  metadata {
    name = "linkerd-egress"
    annotations = {
      "linkerd.io/inject" = "enabled"
    }
  }

  depends_on = [helm_release.linkerd_control_plane]
}

resource "kubectl_manifest" "egress_network" {
  yaml_body = yamlencode({
    apiVersion = "policy.linkerd.io/v1alpha1"
    kind       = "EgressNetwork"
    metadata = {
      name      = local.linkerd_egress_network_name
      namespace = "linkerd-egress"
    }
    spec = {
      trafficPolicy = "Allow"
      networks = [
        {
          cidr = "0.0.0.0/0"
          except = [
            "10.0.0.0/8",
            "172.16.0.0/12",
            "192.168.0.0/16",
          ]
        }
      ]
    }
  })

  depends_on = [kubernetes_namespace_v1.linkerd_egress]
}
