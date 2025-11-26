# Terraform stack

This folder is the root Terraform module for deploying the semantic-segmenter stack on Kubernetes.

## Structure
- `main.tf` – minimal root: creates the namespace and calls the `modules/app` composite module
- `variables.tf` – input variables (kubeconfig, namespace, image_repo, ingest_image, node_port_base)
- `versions.tf` – Terraform and provider constraints; Kubernetes provider config
- `outputs.tf` – useful endpoints (Redis URL, NodePort URLs)
- `modules/` – reusable modules:
  - `app/` – one-call deployment of Redis, PVCs, and all services
  - `deployment/` – generic Kubernetes Deployment
  - `service/` – generic Kubernetes Service (ClusterIP/NodePort)
  - `pvc/` – generic PersistentVolumeClaim

## Usage
```bash
terraform init
terraform apply \
  -var kubeconfig="<path to kubeconfig>" \
  -var image_repo="<registry>/semantic-segmenter:<tag>" \
  -var ingest_image="<registry>/ingest-api:<tag>"
```

Recommended: create a `terraform.tfvars` file instead of passing `-var` flags.

## Variables
- `kubeconfig` (string): path to kubeconfig used by the Kubernetes provider
- `namespace` (string, default: `semseg`): Kubernetes namespace to deploy into
- `image_repo` (string): image for app services
- `ingest_image` (string): image for ingest-api
- `node_port_base` (number, default: `30080`): base port for NodePort services

## Outputs
- `redis_url`: `redis://...` connection URL
- `results_url`: external URL for results-api (NodePort)
- `qa_url`: external URL for qa-web (NodePort)
- `ingest_url`: external URL for ingest-api (NodePort)

## Environments
This root is suitable for a single environment (e.g., local). For multiple environments (dev/stage/prod), create separate root folders (e.g., `infra/terraform-dev`) that call the same `modules/app` module with different variables. This is a common best practice for clear separation and CI/CD.

## Notes
- For team usage, configure a remote backend (e.g., Azure Storage, S3) in `versions.tf` to manage state centrally.
- For production clusters, prefer an Ingress or LoadBalancer over NodePort.
- Run `terraform fmt` and `terraform validate` as part of CI to keep definitions consistent.
