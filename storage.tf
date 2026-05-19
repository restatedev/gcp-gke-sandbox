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
    type = "hyperdisk-balanced"
  }
}

# VolumeAttributesClass tiers for hyperdisk-balanced. IOPS values are powers of
# 2 so the ladder is easy to reason about and map them to machine types;
# throughput is paired to match VM-cap realities for the [c3d, c3] ComputeClass
# priority.
locals {
  hyperdisk_vacs = {
    "hyperdisk-4k-200"  = { iops = "4000", throughput = "200Mi" }  # 2-vCPU profiles
    "hyperdisk-8k-400"  = { iops = "8000", throughput = "400Mi" }  # 4-vCPU profiles
    "hyperdisk-16k-400" = { iops = "16000", throughput = "400Mi" } # 8-vCPU profiles
    "hyperdisk-32k-800" = { iops = "32000", throughput = "800Mi" } # 16+ vCPU profiles / benchmarking
  }
}

resource "kubectl_manifest" "hyperdisk_vac" {
  for_each = var.enable_hyperdisk ? local.hyperdisk_vacs : {}

  yaml_body = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "VolumeAttributesClass"
    metadata = {
      name = each.key
    }
    driverName = "pd.csi.storage.gke.io"
    parameters = {
      iops       = each.value.iops
      throughput = each.value.throughput
    }
  })

  depends_on = [google_container_cluster.autopilot]
}
