Model: GPT-5 (Thinking set to Auto)
Prompt level: 2
Candidate ID: gpt5-P2

## Base-Prompt
```
Generate Terraform for Docker Desktop with the following details and wiring:
- Namespace: `semseg`
- Deployments (8): `ingest-api` (8080), `results-api` (8081), `qa-web` (8082), `convert-ply`, `part-labeler`, `redactor`, `analytics`, `redis` (6379)

Images
- Use a shared image for workers and web UIs (e.g., `semantic-segmenter:latest`) and a separate image for `ingest-api` (e.g., `ingest-api:latest`)
- Use `redis:7-alpine` for Redis
- Prefer parameterizing these as variables (e.g., `image_repo` or `shared_image` for workers/web; `ingest_image` for ingest)

Services and ports
- NodePorts: `ingest-api` 30080 -> targetPort 8080; `results-api` 30081 -> 8081; `qa-web` 30082 -> 8082
- `redis` as ClusterIP on port 6379

PVCs and volumes
- Create three PVCs with `storageClassName=hostpath`, sizes: `sub-pc-frames-pvc` 64Mi, `pc-frames-pvc` 128Mi, `segments-pvc` 256Mi
- Set `wait_until_bound=false` on PVC resources (to avoid deadlocks under WaitForFirstConsumer)
- Mounts:
   - `convert-ply`: `/sub-pc-frames`, `/pc-frames`, `/segments`
   - `part-labeler`: `/pc-frames`, `/segments`
   - `redactor`: `/pc-frames`, `/segments`
   - `analytics`: `/segments`
   - `results-api`: `/segments`
   - `ingest-api`: `/sub-pc-frames`

Environment variables
- Common: `REDIS_URL=redis://redis.semseg.svc.cluster.local:6379/0`
- Streams/groups:
   - `REDIS_STREAM_FRAMES_CONVERTED=s_frames_converted`
   - `REDIS_STREAM_PARTS_LABELED=s_parts_labeled`
   - `REDIS_STREAM_REDACTED_DONE=s_redacted_done`
   - `REDIS_STREAM_ANALYTICS_DONE=s_analytics_done`
   - `REDIS_GROUP_PART_LABELER=g_part_labeler`
   - `REDIS_GROUP_REDACTOR=g_redactor`
   - `REDIS_GROUP_ANALYTICS=g_analytics`
- API specifics:
   - `ingest-api`: `INGEST_OUT_DIR=/sub-pc-frames`
   - `results-api`: `SEGMENTS_DIR=/segments`
   - `qa-web`: `RESULTS_API_URL=http://results-api.semseg.svc.cluster.local`

Probes and labels
- Readiness and liveness HTTP probes on `/healthz` for `ingest-api`, `results-api`, `qa-web`
- All Pods and Services labeled `app=<name>`; Service selectors match labels

Outputs
- Output three NodePort URLs for ingest, results, and qa.

Project structure
- Introduce three simple reusable submodules: `deployment`, `service`, and `pvc`. Use these from the root module to reduce duplication.

Follow Terraform best practices for structuring modules, variables, outputs, and provider version pinning. Deploy each Deployment with replicas=1; do not include autoscaling (HPA/VPA) or scaling policies. Do not include security hardening (RBAC, PodSecurityPolicy/SCC, NetworkPolicy, Pod/Container securityContext); focus only on the specified details. At the end, include example Terraform commands to run (fmt, init, validate, apply). For apply, include -var assignments for the variables your solution requires.
```

## Provided structure
```
semseg-terraform/
├── main.tf
├── variables.tf
├── outputs.tf
├── modules/
│   ├── deployment/
│   │   ├── main.tf
│   │   └── variables.tf
│   ├── service/
│   │   ├── main.tf
│   │   └── variables.tf
│   └── pvc/
│       ├── main.tf
│       └── variables.tf
```

## Extra prompts needed

### Prompt 1
```
Error: Invalid single-argument block definition
   on modules\service\variables.tf line 15, in variable "node_port":
   15: variable "node_port"   { type = number, default = null }
 Single-line block syntax can include only one argument definition. To define multiple arguments, use the multi-line block syntax with one argument definition per line.
Please fix error.
```

### Prompt 2
```
Error: Unsupported attribute
  on main.tf line 69, in locals:
  69:     { name = "sub-pc-frames", claim = module.pvc_sub_pc_frames.name },
    ├────────────────
    │ module.pvc_sub_pc_frames is a object
This object does not have an attribute named "name".
Error: Unsupported attribute
  on main.tf line 70, in locals:
  70:     { name = "pc-frames",     claim = module.pvc_pc_frames.name     },
    ├────────────────
    │ module.pvc_pc_frames is a object
This object does not have an attribute named "name".
Error: Unsupported attribute
  on main.tf line 71, in locals:
  71:     { name = "segments",      claim = module.pvc_segments.name      },
    ├────────────────
    │ module.pvc_segments is a object
This object does not have an attribute named "name".
Please fix error.
```

### Prompt 3
```
We need to add args to some deployments, please do that based on the information provided below:
results-api: uvicorn services.results_api.app:app --host 0.0.0.0 --port <port> --workers 1
qa-web: uvicorn services.qa_web.app:app --host 0.0.0.0 --port <port> --workers 1
convert: python3 /semantic-segmenter/services/convert_service/convert-ply --in-dir /sub-pc-frames --out-dir /pc-frames --preview-out-dir /segments --delete-source --log-level info
labeler: python3 /semantic-segmenter/services/part_labeler/part_labeler.py --log-level info --out-dir /segments --colorized-dir /segments/labels --write-colorized
redactor: python3 /semantic-segmenter/services/redactor/redactor.py --log-level info --out-dir /segments
analytics: python3 /semantic-segmenter/services/analytics/analytics.py --log-level info --out-dir /segments
```

### Prompt 4
```
Error: Invalid single-argument block definition
  on modules\deployment\main.tf line 43, in resource "kubernetes_deployment" "this":
  43:               http_get { path = var.readiness_path, port = var.port }
Single-line block syntax can include only one argument definition. To define multiple arguments, use the multi-line block syntax with one argument definition
per line.
Error: Invalid single-argument block definition
  on modules\deployment\main.tf line 52, in resource "kubernetes_deployment" "this":
  52:               http_get { path = var.liveness_path, port = var.port }
Single-line block syntax can include only one argument definition. To define multiple arguments, use the multi-line block syntax with one argument definition
per line.
Please fix error.
```

### Prompt 5
```
Visiting qa-web "/" returns 500; logs show httpx.ConnectTimeout when qa-web calls results-api during "/" handling. Diagnose why qa-web times out calling results-api and provide the smallest Terraform-only fix.
```

## Notes
- 1st extra prompt provided good fix for error.
- 2nd prompt provided a fix with adding a new output named claim_name to pvc in a new file outputs.tf. This is an okay fix.
- 3rd extra prompt provided a solution for the args but also made some mistakes and made a working module faulty, but it was only a syntax error that is fixed with 4th extra prompt.
- Manually changed image_pull_policy to IfNotPresent because we have the images locally.
- 5th prompt provided a somewhat acceptable solution for the problem with:
  ```
  # in main.tf, module "deploy_qa_web"
  module "deploy_qa_web" {
    # ...unchanged...
    env = merge(local.common_env, {
      RESULTS_API_URL = "http://results-api.${var.namespace}.svc.cluster.local:30081"
    })
    # ...unchanged...
  }
  ```

## Local test apply command
```powershell
terraform apply `
  -var="shared_image=semantic-segmenter:latest" `
  -var="ingest_image=ingest-api:latest" `
  -var="redis_image=redis:7-alpine" `
  -var="namespace=semseg" `
  -var="node_ip=localhost"
```

---

## Scoring (with notes)

Scores (1..5):

- Correctness (docker): 3 — Primary issue was qa-web → results-api timeout from Service port semantics; adding an explicit port in the URL resolved it and the pipeline ran. Negative: rollout was initially blocked by the port mismatch and required a URL override instead of normalizing Service/targetPort in Terraform.
- Kubernetes fit: 3 — Labels/selectors and probes on web APIs are in place; using NodePort numbers as in-cluster Service ports is non-idiomatic but workable with explicit ports. Negative: Services don’t follow the conventional port 80 + targetPort mapping, which reduces portability.
- Storage: 4 — Three PVCs with correct sizes; `wait_until_bound=false` set to avoid deadlocks; mounts mapped appropriately.
- Image handling: 5 — Shared vs ingest images are parameterized, Redis pinned to 7-alpine, and image_pull_policy IfNotPresent matches local Docker Desktop workflows.
- Networking: 3 — In-cluster DNS correct; current Service port wiring requires an explicit port in RESULTS_API_URL for qa-web, which is functional. Negative: env-level hardcoding of ports increases coupling and deviates from typical Service port abstractions.
- Modularity: 4 — Good reuse via `deployment`, `service`, and `pvc` submodules with clear variables/locals. To reach 5, add a top-level “app” composer module that exports shared URLs/ports as outputs and centralizes wiring.
- Reasoning: 4 — Iterative changes converged with minimal Terraform edits, preserving module structure and addressing rollout blockers efficiently. Negative: didn’t proactively normalize the Service-port idiom to prevent similar issues later.

Overall (avg): 3.7 / 5
