# -----------------------------------------------------------------------------
# cert-manager ACME ClusterIssuers
#
# Matches the pattern used in aws-eks-karpenter-sandbox and azure-aks-sandbox.
# Uses Let's Encrypt with DNS01 challenges via Cloud DNS.
# -----------------------------------------------------------------------------

locals {
  cert_manager_issuers = {
    email              = "dns@nuon.co"
    server             = "https://acme-v02.api.letsencrypt.org/directory"
    public_issuer_name = "public-issuer"
  }
}

# GCP service account for cert-manager to manage DNS01 challenges.
resource "google_service_account" "cert_manager" {
  account_id   = "${substr(var.nuon_id, 0, 20)}-cm"
  display_name = "cert-manager for ${var.nuon_id}"
}

resource "google_project_iam_member" "cert_manager_dns_admin" {
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.cert_manager.email}"
}

resource "google_service_account_iam_member" "cert_manager_wi" {
  service_account_id = google_service_account.cert_manager.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[cert-manager/cert-manager]"
  depends_on         = [google_container_cluster.autopilot]
}

# public-issuer ClusterIssuer — used by ingress/tunnel Certificate resources.
resource "kubectl_manifest" "cluster_issuer_public" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = local.cert_manager_issuers.public_issuer_name
    }
    spec = {
      acme = {
        email  = local.cert_manager_issuers.email
        server = local.cert_manager_issuers.server
        privateKeySecretRef = {
          name = local.cert_manager_issuers.public_issuer_name
        }
        solvers = [
          {
            selector = {
              dnsZones = [
                trimsuffix(google_dns_managed_zone.public[0].dns_name, "."),
              ]
            }
            dns01 = {
              cloudDNS = {
                project        = var.project_id
                hostedZoneName = google_dns_managed_zone.public[0].name
              }
            }
          }
        ]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}
