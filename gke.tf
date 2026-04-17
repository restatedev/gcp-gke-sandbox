# -----------------------------------------------------------------------------
# GKE Standard Cluster
#
# Using Standard (not Autopilot) because Autopilot blocks NET_ADMIN, which
# Linkerd's proxy init container requires to set up iptables interception.
# Standard gives full node control; autoscaling handles capacity automatically.
# -----------------------------------------------------------------------------

resource "google_container_cluster" "autopilot" {
  project  = var.project_id
  name     = local.cluster_name
  location = var.region

  # Standard mode — remove the default node pool immediately and manage
  # node pools explicitly so we can tune machine type and autoscaling.
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection

  network    = local.network
  subnetwork = local.subnetwork

  ip_allocation_policy {
    cluster_secondary_range_name  = local.create_vpc ? "pods" : null
    services_secondary_range_name = local.create_vpc ? "services" : null
  }

  release_channel {
    channel = var.release_channel
  }

  # Private cluster — nodes have no public IPs; Cloud NAT handles egress.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = !var.cluster_endpoint_public_access
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  # Workload Identity — allows pods to assume GCP service accounts via
  # Kubernetes ServiceAccount annotations (GKE equivalent of IRSA).
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  binary_authorization {
    evaluation_mode = "DISABLED"
  }

  addons_config {
    config_connector_config {
      enabled = true
    }
  }

  # Node Auto-Provisioning — when enabled, GKE creates node pools on-demand
  # based on pending pod requirements. The ComputeClass CRD (applied by the
  # region operator) controls machine family preferences and node config.
  dynamic "cluster_autoscaling" {
    for_each = var.enable_nap ? [1] : []
    content {
      # Affects both the default pool and NAP pools — more aggressive
      # scale-down than the default BALANCED profile. Ideally this would
      # be set independently of NAP, but autoscaling_profile can only be
      # set inside cluster_autoscaling.
      autoscaling_profile = "OPTIMIZE_UTILIZATION"

      resource_limits {
        resource_type = "cpu"
        minimum       = 0
        maximum       = var.nap_max_cpu
      }
      resource_limits {
        resource_type = "memory"
        minimum       = 0
        maximum       = var.nap_max_memory_gb
      }

      auto_provisioning_defaults {
        service_account = google_service_account.gke_nodes.email
        disk_type       = var.node_disk_type
        disk_size       = var.node_disk_size_gb
        image_type      = "COS_CONTAINERD"

        management {
          auto_repair  = true
          auto_upgrade = true
        }

        shielded_instance_config {
          enable_secure_boot          = false
          enable_integrity_monitoring = true
        }

        oauth_scopes = [
          "https://www.googleapis.com/auth/cloud-platform",
        ]
      }
    }
  }

  resource_labels = local.default_labels
}

# Single node pool for all workloads (infra and restate pods).
# Configurable machine type; defaults to x86, set to c4a family for ARM.
resource "google_container_node_pool" "default" {
  project  = var.project_id
  name     = "default"
  cluster  = google_container_cluster.autopilot.name
  location = var.region

  initial_node_count = var.node_initial_count

  autoscaling {
    min_node_count  = var.node_min_count
    max_node_count  = var.node_max_count
    location_policy = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.node_machine_type
    disk_size_gb    = var.node_disk_size_gb
    disk_type       = var.node_disk_type
    service_account = google_service_account.gke_nodes.email

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Secure boot disabled to allow Linkerd init container NET_ADMIN
    shielded_instance_config {
      enable_secure_boot          = false
      enable_integrity_monitoring = true
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels = merge(local.default_labels, {
      "workload-type" = "restate"
    })

    linux_node_config {
      sysctls = {
        "fs.aio-max-nr"               = "65536"
        "fs.file-max"                 = "104857"
        "fs.inotify.max_user_watches" = "1000000"
      }
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}
