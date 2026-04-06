resource "kubernetes_storage_class_v1" "pd_ssd" {
  metadata {
    name = "pd-ssd"
  }

  storage_provisioner    = "pd.csi.storage.gke.io"
  volume_binding_mode    = "WaitForFirstConsumer"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true

  parameters = {
    type = "pd-ssd"
  }
}

resource "kubernetes_storage_class_v1" "hyperdisk_balanced" {
  count = var.enable_hyperdisk ? 1 : 0

  metadata {
    name = "hyperdisk-balanced"
  }

  storage_provisioner    = "pd.csi.storage.gke.io"
  volume_binding_mode    = "WaitForFirstConsumer"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true

  parameters = {
    type                               = "hyperdisk-balanced"
    "provisioned-throughput-on-create" = var.hyperdisk_throughput
    "provisioned-iops-on-create"       = var.hyperdisk_iops
  }
}
