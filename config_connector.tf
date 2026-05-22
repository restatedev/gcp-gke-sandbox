# Config Connector — GKE addon that allows the Restate operator to create
# IAMPolicyMember CRs, which Config Connector reconciles into GCP IAM bindings.
# This is the GCP equivalent of ACK on AWS (see ack_eks.tf in aws-eks-karpenter-sandbox).
#
# Uses cluster-scoped mode so that a single controller manages IAMPolicyMember
# resources in any namespace (each Restate environment gets its own namespace).
# Per-namespace mode would require a WI binding per environment namespace, which
# doesn't scale.

# GCP SA for Config Connector. Needs permission to manage IAM bindings on the
# restate SA so it can create per-environment workload identity bindings.
resource "google_service_account" "config_connector" {
  account_id   = "${substr(var.nuon_id, 0, 20)}-cnrm"
  display_name = "Config Connector for ${var.nuon_id}"
}

# Allow Config Connector to manage IAM bindings on the restate GCP SA.
# This is the install SA used by the restate-operator's v2.3.0 Workload Identity
# binding automation. Do not remove: removing it would break operator-driven WI
# bindings on the install-shared SA even after the per-env identity feature lands.
resource "google_service_account_iam_member" "config_connector_restate_sa_admin" {
  service_account_id = google_service_account.restate.name
  role               = "roles/iam.serviceAccountAdmin"
  member             = "serviceAccount:${google_service_account.config_connector.email}"
}

# Project-level permissions for Config Connector to create and destroy per-env
# GCP service accounts (one per Restate Cloud environment) and to manage their
# Workload Identity bindings. The matching bucket-scoped permissions needed
# to attach prefix-conditional GCS bindings live in the restate-gcs-bucket
# component (nuon-byoc) and reference google_service_account.config_connector.email.
#
# Least-privilege over roles/iam.serviceAccountAdmin: the predefined role grants
# undelete, disable, enable, update, actAs and more that Config Connector never
# exercises for the per-env identity flow.
resource "google_project_iam_custom_role" "config_connector_env_sa_admin" {
  project     = var.project_id
  role_id     = replace("${var.nuon_id}_cc_env_sa_admin", "-", "_")
  title       = "${var.nuon_id} Config Connector per-env SA admin"
  description = "Permissions Config Connector needs to provision per-environment GCP service accounts and their Workload Identity bindings."
  stage       = "GA"

  permissions = [
    "iam.serviceAccounts.create",
    "iam.serviceAccounts.delete",
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.getIamPolicy",
    "iam.serviceAccounts.setIamPolicy",
  ]
}

resource "google_project_iam_member" "config_connector_env_sa_admin" {
  project = var.project_id
  role    = google_project_iam_custom_role.config_connector_env_sa_admin.id
  member  = "serviceAccount:${google_service_account.config_connector.email}"
}

# Workload Identity binding so the Config Connector K8s SA can act as the GCP SA.
# In cluster-scoped mode, the controller uses cnrm-system/cnrm-controller-manager.
resource "google_service_account_iam_member" "config_connector_wi" {
  service_account_id = google_service_account.config_connector.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[cnrm-system/cnrm-controller-manager]"
  depends_on         = [google_container_cluster.autopilot]
}

# Cluster-scoped ConfigConnector CR. A single controller in cnrm-system manages
# resources across all namespaces, using the same GCP SA.
resource "kubectl_manifest" "config_connector" {
  yaml_body = yamlencode({
    apiVersion = "core.cnrm.cloud.google.com/v1beta1"
    kind       = "ConfigConnector"
    metadata = {
      name = "configconnector.core.cnrm.cloud.google.com"
    }
    spec = {
      mode                = "cluster"
      googleServiceAccount = google_service_account.config_connector.email
    }
  })

  depends_on = [
    google_container_cluster.autopilot,
    google_container_node_pool.default,
    google_service_account_iam_member.config_connector_wi,
  ]
}
