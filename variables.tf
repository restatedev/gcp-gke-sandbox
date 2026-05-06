# -----------------------------------------------------------
# Nuon-provided variables (from install stack / app config)
# -----------------------------------------------------------

variable "nuon_id" {
  description = "Nuon install identifier."
  type        = string
}

variable "region" {
  description = "GCP region for the GKE cluster."
  type        = string
}

variable "gcp_credentials_base64" {
  description = "GCP service account credentials JSON, base64 encoded."
  type        = string
  sensitive   = true
  default     = ""
}

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

# -----------------------------------------------------------
# Cluster configuration
# -----------------------------------------------------------

variable "cluster_name" {
  description = "Name for the GKE cluster. Defaults to n-{nuon_id}."
  type        = string
  default     = ""
}

variable "enable_nap" {
  description = "Enable GKE Node Auto-Provisioning (NAP). When enabled, GKE can create new node pools automatically based on pending pod requirements."
  type        = string
  default     = "false"
}

variable "nap_max_cpu" {
  description = "Maximum total CPU cores across all NAP-created node pools."
  type        = number
  default     = 256
}

variable "nap_max_memory_gb" {
  description = "Maximum total memory (GiB) across all NAP-created node pools."
  type        = number
  default     = 1024
}

variable "node_machine_type" {
  description = "Machine type for the node pool. Use c4a family for ARM."
  type        = string
  default     = "c3-standard-8"
}

variable "node_initial_count" {
  description = "Initial node count per zone."
  type        = number
  default     = 1
}

variable "node_min_count" {
  description = "Minimum node count per zone for autoscaling."
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Maximum node count per zone for autoscaling."
  type        = number
  default     = 6
}

variable "node_disk_size_gb" {
  description = "Boot disk size in GB."
  type        = number
  default     = 100
}

variable "node_disk_type" {
  description = "Boot disk type. Use hyperdisk-balanced for c4a ARM."
  type        = string
  default     = "pd-ssd"
}

variable "release_channel" {
  description = "GKE release channel. One of: RAPID, REGULAR, STABLE."
  type        = string
  default     = "REGULAR"
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection on the cluster."
  type        = bool
  default     = false
}

variable "cluster_endpoint_public_access" {
  description = "Whether the GKE cluster API endpoint is publicly accessible."
  type        = bool
  default     = true
}

# -----------------------------------------------------------
# Networking (optional — empty = create new VPC)
# -----------------------------------------------------------

variable "network" {
  description = "Existing VPC network name or self_link. If empty, a new VPC is created."
  type        = string
  default     = ""
}

variable "subnetwork" {
  description = "Existing subnetwork name or self_link for GKE. If empty, a new subnet is created."
  type        = string
  default     = ""
}

variable "subnet_cidr" {
  description = "Primary CIDR for the GKE subnet (when creating a new VPC)."
  type        = string
  default     = "10.0.0.0/20"
}

variable "pods_cidr_range" {
  description = "Secondary CIDR range for pods."
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr_range" {
  description = "Secondary CIDR range for services."
  type        = string
  default     = "10.2.0.0/20"
}

# -----------------------------------------------------------
# DNS
# -----------------------------------------------------------

variable "enable_nuon_dns" {
  description = "Whether the cluster should use Nuon-provided DNS."
  type        = string
  default     = "false"
}

variable "public_root_domain" {
  description = "The public root domain."
  type        = string
  default     = ""
}

variable "internal_root_domain" {
  description = "The internal root domain."
  type        = string
  default     = ""
}

# -----------------------------------------------------------
# Namespaces
# -----------------------------------------------------------

variable "additional_namespaces" {
  description = "Extra namespaces to create. The nuon_id namespace is always created."
  type        = list(string)
  default     = []
}


# -----------------------------------------------------------
# Storage
# -----------------------------------------------------------

variable "enable_hyperdisk" {
  description = "Whether to create the hyperdisk-balanced StorageClass (required for ARM/c4a)."
  type        = bool
  default     = false
}

variable "hyperdisk_iops" {
  description = "Provisioned IOPS for hyperdisk-balanced StorageClass."
  type        = string
  default     = "10000"
}

variable "hyperdisk_throughput" {
  description = "Provisioned throughput for hyperdisk-balanced StorageClass."
  type        = string
  default     = "1500Mi"
}

# -----------------------------------------------------------
# Access control
# -----------------------------------------------------------

variable "master_authorized_networks" {
  description = "CIDR blocks authorized to access the GKE control plane."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

# -----------------------------------------------------------
# Labels / tags
# -----------------------------------------------------------

variable "labels" {
  description = "Labels to apply to all resources."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags provided by Nuon for resource identification."
  type        = map(any)
  default     = {}
}
