output "account" {
  value = {
    project_id = var.project_id
    region     = var.region
  }
}

output "cluster" {
  value = {
    name                       = google_container_cluster.autopilot.name
    endpoint                   = "https://${google_container_cluster.autopilot.endpoint}"
    certificate_authority_data = google_container_cluster.autopilot.master_auth[0].cluster_ca_certificate
    location                   = google_container_cluster.autopilot.location
    self_link                  = google_container_cluster.autopilot.self_link
  }
}

output "gar" {
  value = {
    repository_id  = google_artifact_registry_repository.main.repository_id
    repository_url = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.main.repository_id}"
    registry_url   = "${var.region}-docker.pkg.dev"
  }
}

output "vpc" {
  value = {
    network    = local.network
    subnetwork = local.subnetwork
  }
}

output "nuon_dns" {
  value = {
    enabled = local.enable_nuon_dns
    public_domain = local.enable_nuon_dns && local.public_domain != "" ? {
      zone_id     = google_dns_managed_zone.public[0].managed_zone_id
      zone_name   = google_dns_managed_zone.public[0].name
      name        = google_dns_managed_zone.public[0].dns_name
      nameservers = google_dns_managed_zone.public[0].name_servers
    } : { zone_id = "", zone_name = "", name = "", nameservers = tolist([""]) }
    internal_domain = local.internal_domain != "" ? {
      zone_id     = google_dns_managed_zone.internal[0].managed_zone_id
      name        = google_dns_managed_zone.internal[0].dns_name
      nameservers = google_dns_managed_zone.internal[0].name_servers
    } : { zone_id = "", name = "", nameservers = tolist([""]) }
  }
}

output "namespaces" {
  value = [for ns in kubernetes_namespace_v1.main : ns.metadata[0].name]
}

# Comma-separated list of available zones in the cluster region.
# Used by ingress, tunnel, and gcp_lb components for topology spread
# and per-zone resource allocation.
output "availability_zones" {
  value = join(",", google_container_node_pool.default.node_locations)
}

output "workload_identity" {
  value = {
    restate_sa_email                  = google_service_account.restate.email
    secrets_accessor_sa_email         = google_service_account.secrets_accessor.email
    datadog_secrets_accessor_sa_email = var.enable_datadog_collector ? google_service_account.datadog_secrets_accessor[0].email : ""
  }
}

output "linkerd" {
  value = {
    # Name of the EgressNetwork resource in the linkerd-egress namespace.
    # Used by the tunnel component's TLSRoute to intercept outbound
    # connections to tunnel.<domain> and route them to the proxy service.
    all_egress_traffic = local.linkerd_egress_network_name
  }
}
