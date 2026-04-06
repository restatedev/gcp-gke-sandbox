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

  namespaces = concat([var.nuon_id], var.additional_namespaces)
}
