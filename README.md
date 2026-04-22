# gcp-gke-sandbox

GKE Autopilot sandbox for Nuon BYOC deployments. Equivalent to [aws-eks-karpenter-sandbox](https://github.com/nuonco/aws-eks-karpenter-sandbox).

GKE Autopilot manages node provisioning automatically — no Karpenter equivalent needed.

## Prerequisites

### Required GCP APIs

Enable these APIs on your GCP project before running:

```bash
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  artifactregistry.googleapis.com \
  dns.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project=<PROJECT_ID>
```

### Required IAM Permissions

The service account or user running terraform needs:
- Kubernetes Engine Admin (`roles/container.admin`)
- Compute Network Admin (`roles/compute.networkAdmin`)
- Artifact Registry Admin (`roles/artifactregistry.admin`)
- DNS Administrator (`roles/dns.admin`)
- Service Account User (`roles/iam.serviceAccountUser`)

## Resources Created

- **GKE Autopilot Cluster** — Workload Identity, private nodes, configurable release channel
- **Artifact Registry** (Docker) — equivalent to ECR
- **Cloud DNS Zones** — public and internal (optional, controlled by `enable_nuon_dns`)
- **VPC + Subnet + Cloud NAT** — networking (optional, can use existing VPC)
- **Kubernetes Namespaces** — nuon_id namespace + additional

## Local Testing

```bash
gcloud auth application-default login --project=<PROJECT_ID>
terraform init
terraform plan -var-file=example.tfvars
terraform apply -var-file=example.tfvars
```

See [docs/connecting-to-gke.md](docs/connecting-to-gke.md) for connecting to the cluster after creation.

## Inputs

| Name | Description | Default | Required |
|------|-------------|---------|----------|
| `nuon_id` | Nuon install identifier | — | yes |
| `region` | GCP region | — | yes |
| `project_id` | GCP project ID | — | yes |
| `gcp_credentials_base64` | Base64-encoded service account JSON | `""` | no |
| `cluster_name` | GKE cluster name | `n-{nuon_id}` | no |
| `release_channel` | GKE release channel | `REGULAR` | no |
| `cluster_endpoint_public_access` | Public API endpoint | `true` | no |
| `network` | Existing VPC (empty = create new) | `""` | no |
| `subnetwork` | Existing subnet (empty = create new) | `""` | no |
| `enable_nuon_dns` | Enable Nuon DNS zones | `false` | no |
| `public_root_domain` | Public DNS domain | `""` | no |
| `internal_root_domain` | Internal DNS domain | `""` | no |
| `additional_namespaces` | Extra K8s namespaces | `[]` | no |
| `kyverno_policy_dir` | Path to Kyverno policy manifests | `"./kyverno-policies"` | no |
| `deletion_protection` | Cluster deletion protection | `false` | no |
| `labels` | Resource labels | `{}` | no |
| `tags` | Nuon resource tags | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `account` | project_id, region |
| `cluster` | name, endpoint, ca_cert, location |
| `gar` | repository_id, repository_url, registry_url |
| `vpc` | network, subnetwork |
| `nuon_dns` | enabled, public_domain, internal_domain |
| `namespaces` | list of created namespaces |
