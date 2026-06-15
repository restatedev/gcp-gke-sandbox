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

# hyperdisk-balanced formatted xfs with inline discard. fstype applies only to
# newly provisioned volumes. The VAC tiers below work against this class too.
resource "kubernetes_storage_class_v1" "hyperdisk_balanced_xfs" {
  count = var.enable_hyperdisk ? 1 : 0

  metadata {
    name = "hyperdisk-balanced-xfs"
  }

  storage_provisioner    = "pd.csi.storage.gke.io"
  volume_binding_mode    = "WaitForFirstConsumer"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true

  parameters = {
    type                        = "hyperdisk-balanced"
    "csi.storage.k8s.io/fstype" = "xfs"
  }

  mount_options = ["discard"]
}

# VolumeAttributesClass tiers for hyperdisk-balanced. IOPS values are powers of
# 2 so the ladder is easy to reason about and map them to machine types;
# throughput is paired to match VM-cap realities for the [c3d, c3] ComputeClass
# priority.
# you get 3000 IOPS / 140 MiB/s for free on hyperdisk.
# 1200 MiB/s is the max we can get on c3d machines.
# 93,750 IOPS is the max IOPS for c3d.
locals {
  hyperdisk_vacs = {
    "hyperdisk-3k-1200"  = { iops = "3000", throughput = "1200Mi" }
    "hyperdisk-4k-200"   = { iops = "4000", throughput = "200Mi" } # 2-vCPU profiles
    "hyperdisk-4k-1200"  = { iops = "4000", throughput = "1200Mi" }
    "hyperdisk-8k-400"   = { iops = "8000", throughput = "400Mi" } # 4-vCPU profiles
    "hyperdisk-8k-1200"  = { iops = "8000", throughput = "1200Mi" }
    "hyperdisk-16k-400"  = { iops = "16000", throughput = "400Mi" } # 8-vCPU profiles
    "hyperdisk-16k-1200" = { iops = "16000", throughput = "1200Mi" }
    "hyperdisk-32k-800"  = { iops = "32000", throughput = "800Mi" }  # 16+ vCPU profiles / benchmarking
    "hyperdisk-32k-1200" = { iops = "32000", throughput = "1200Mi" } # warning: +$336/mo
    "hyperdisk-64k-1200" = { iops = "64000", throughput = "1200Mi" } # warning: +$816/mo
    "hyperdisk-93k-1200" = { iops = "93750", throughput = "1200Mi" } # warning: +$1262/mo
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
