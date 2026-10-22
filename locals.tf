locals {
  cluster_name = substr(var.cluster_name != "" ? var.cluster_name : "n-${var.nuon_id}", 0, 38)
  create_vpc   = var.network == ""

  enable_nuon_dns = contains(["1", "true"], var.enable_nuon_dns)

  public_domain   = trimprefix(trimsuffix(trimspace(var.public_root_domain), "."), ".")
  internal_domain = trimprefix(trimsuffix(trimspace(var.internal_root_domain), "."), ".")

  default_labels = merge(var.labels, {
    "nuon-id"         = var.nuon_id
    "managed-by"      = "nuon"
    "sandbox-name"    = "gcp-gke"
    "sandbox-variant" = "standard"
  })

  # Ownership and classification labels that compliance checks (Vanta) require on
  # every Compute Engine instance. GKE propagates cluster resource labels to all
  # node VMs and their disks, including node-auto-provisioned pools, so they are
  # set on the cluster only. var.labels can override any of them.
  cluster_resource_labels = merge(
    {
      "environment"        = var.environment
      "owner"              = "restate"
      "project"            = var.nuon_id
      "dataclassification" = "confidential"
      "application"        = "restate-byoc"
    },
    local.default_labels,
  )

  namespaces = concat([var.nuon_id], var.additional_namespaces)
}
