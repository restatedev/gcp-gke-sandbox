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

# VolumeAttributesClass tiers for hyperdisk-balanced. Each tier is sized to fit
# the worst-case VM cap for a given profile CPU bucket under the [c3d, c3]
# ComputeClass priority, so the tier name reflects what the disk can actually
# deliver on the smallest VM NAP could land on.
locals {
  hyperdisk_vacs = {
    "hyperdisk-25k-400"   = { iops = "25000", throughput = "400" }   # 4-vCPU profiles
    "hyperdisk-50k-800"   = { iops = "50000", throughput = "800" }   # 8-vCPU profiles
    "hyperdisk-75k-1200"  = { iops = "75000", throughput = "1200" }  # 16-44 vCPU profiles (bounded by c3d; c3 could go higher in this range, but NAP may pick either)
    "hyperdisk-160k-2400" = { iops = "160000", throughput = "2400" } # 60+ vCPU profiles (c3d catches up to c3 here)
  }
}

resource "kubernetes_manifest" "hyperdisk_vac" {
  for_each = var.enable_hyperdisk ? local.hyperdisk_vacs : {}

  manifest = {
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
  }
}
