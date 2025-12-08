# Automated Deployment of a Microservice Using Generative AI Support

This repository accompanies a thesis with the title above. It contains:
- Python code for each microservice in `services/`
- Manually implemented Terraform stack in `infra/terraform/`
- Kubernetes YAML manifests for local testing in `deploy/k8s/`
- Prompts used for AI generation in `prompts/`
- Test and helper scripts in `scripts/`
- AI-generated implementations and summaries in `ai_infra/` (per AI and prompt complexity)

## Prerequisites
- Docker (Docker Desktop recommended; any Kubernetes cluster works)
- Terraform
- A Kubernetes context configured (Docker Desktop or k3s)

If using local images with Docker Desktop, the Kubernetes cluster can pull images from the local Docker engine when `imagePullPolicy: IfNotPresent` is used by the manifests/modules.

## Build local images
Two images are needed for a full local run:
- The shared app image from the root `Dockerfile`
- The `ingest-api` image from `services/ingest_api/Dockerfile`

From the repository root:

```powershell
# Build shared app image (tags as semantic-segmenter:latest by default)
docker build . -t semantic-segmenter:latest

# Build ingest-api image
docker build ./services/ingest_api -t ingest-api:latest
```

These default tags match the Terraform `variables.tf` defaults:
- `image_repo = "semantic-segmenter:latest"`
- `ingest_image = "ingest-api:latest"`

## Deploy with Terraform
Navigate to `infra/terraform/` and apply:

```powershell
terraform init
terraform plan
terraform apply
```

Type `yes` when prompted. Provisioning may take some time; check pod readiness:

```powershell
kubectl get pods -n semseg
```

### Outputs
Terraform exposes four URLs (NodePort services), as defined in `infra/terraform/outputs.tf`:
- `redis_url`
- `results_url`
- `qa_url`
- `ingest_url`

You can open `qa_url` in a browser to access the QA web UI. Use `ingest_url` to send frames to the pipeline.

## Send test frames
Use the test script to push 10 example frames from `full_frames/drc/`:

```powershell
# From repo root
./scripts/test_pipeline.ps1
```

By default, it targets `localhost` NodePorts (`ingest=30080`, `results=30081`, `qa-web=30082`) and uploads frames `0..9`. You can override via environment variables (e.g., `INGEST_HOST`, `INGEST_PORT`, `RESULTS_PORT`, `FRAMES`, `WAIT_SECONDS`).

After sending frames, refresh the QA web UI to see processing progress. You can open each frame to view analytics, redacted preview, labeled preview, and the original frame.

## Clean up
Destroy the stack when finished:

```powershell
terraform destroy
```

Type `yes` when prompted.

## Notes
- Check `infra/terraform/variables.tf` for defaults and environment-specific settings (e.g., storage class and volume binding mode for Docker Desktop vs k3s).
- For multi-environment setups, consider separate Terraform roots or using `tfvars` files (see `infra/terraform/envs/`).
- For production, prefer Ingress or LoadBalancer over NodePort.
