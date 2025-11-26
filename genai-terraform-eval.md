# Generative AI Model Evaluation for Terraform on k3s

This document defines how to compare different generative AI models at producing Terraform for the final application deployment on the Docker Desktop Kubernetes cluster (single-node) on your machine.

## App context (definitive)
- Cluster: Docker Desktop Kubernetes (single-node); uses the default kubeconfig (for Windows, typically `%USERPROFILE%\.kube\config`).
- Namespace: `semseg`.
- Images (available locally in Docker Desktop):
   - `semantic-segmenter:latest` (used by workers and web APIs)
   - `ingest-api:latest`
   - `redis:7-alpine`
- Deployments (8 total):
   1) `ingest-api` (containerPort 8080)
   2) `results-api` (8081)
   3) `qa-web` (8082)
   4) `convert-ply` (worker)
   5) `part-labeler` (worker)
   6) `redactor` (worker)
   7) `analytics` (worker)
   8) `redis` (6379)
- Services:
   - NodePort `ingest-api` 30080 -> 8080
   - NodePort `results-api` 30081 -> 8081
   - NodePort `qa-web`     30082 -> 8082
   - ClusterIP `redis`     6379
- Persistent storage (default StorageClass on Docker Desktop is typically `hostpath`, accessModes: `ReadWriteOnce`):
   - `sub-pc-frames-pvc` 64Mi
   - `pc-frames-pvc` 128Mi
   - `segments-pvc` 256Mi
- Volumes/mounts mapping:
   - `convert-ply`: mounts `/sub-pc-frames`, `/pc-frames`, `/segments`
   - `part-labeler`: mounts `/pc-frames`, `/segments`
   - `redactor`: mounts `/pc-frames`, `/segments`
   - `analytics`: mounts `/segments`
   - `results-api`: mounts `/segments`
   - `ingest-api`: mounts `/sub-pc-frames`
- Key environment variables:
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
- Probes for web APIs (`ingest-api`, `results-api`, `qa-web`): readiness/liveness HTTP GET `/healthz` on the container port.
- PVC binding: Set `wait_until_bound=false` on Terraform PVC resources to avoid deadlocks even if the StorageClass uses `WaitForFirstConsumer`.

## Comparison aspects (Docker Desktop–focused rubric)
Score each aspect 1–5 (1=poor, 3=adequate, 5=excellent). Include notes and examples.

### Scoring scale (1–5)
- 1 – Poor: Cannot apply or is largely non-functional (missing deployments/services/PVCs, invalid provider/config). Ignores key app wiring. No meaningful modularity.
- 2 – Weak: Applies only after substantial fixes. Multiple broken wires (env, ports, URLs). Minimal or ad-hoc modularity. Not close to ready for local testing.
- 3 – Adequate: Applies with a few targeted fixes and is functionally usable. Some non-idioms (e.g., using NodePort numbers as Service ports) or inconsistencies. Basic submodules or mixed duplication.
- 4 – Good: Applies cleanly or needs only trivial tweaks. Idiomatic Kubernetes wiring (Service port 80 with targetPort), correct envs (e.g., redis://…/0), sensible probes, formatting passes (terraform fmt). Clear submodules with variables/outputs.
- 5 – Excellent: First-try runnable with zero manual fixes. Fully idiomatic networking and k8s patterns, clean module composition including an application composer module, consistent variables/outputs per module, and clear reasoning.

Aspect-specific guidance (what distinguishes 3 vs 5)
- Correctness (Docker Desktop):
   - 3: Needs a few fixes (e.g., missing redis:// or /0, minor syntax issues) but converges.
   - 5: `terraform fmt/init/validate/apply` succeed first try; all 8 deployments, 4 services, 3 PVCs created correctly.
- Kubernetes fit & idioms:
   - 3: Probes/selectors present but some non-idiomatic choices (e.g., in-cluster URLs requiring explicit ports).
   - 5: Probes/selectors sensible; clean rollout defaults; idiomatic Service/targetPort, no in-cluster port suffixes required.
- Storage handling:
   - 3: PVCs present and mostly correct; minor size/mount/SC nits.
   - 5: All PVCs correct with `wait_until_bound=false`, proper mounts per service, correct access modes/SC.
- Image handling realism:
   - 3: Images parameterized; minor pull-policy or tag assumptions.
   - 5: Local images supported out of the box (IfNotPresent), Redis pinned; no unexpected pulls.
- Networking & exposure:
   - 3: Works but requires explicit in-cluster ports or has inconsistent Service ports.
   - 5: NodePorts 30080..30082 map to targetPorts 8080..8082; Service port=80; in-cluster URLs omit ports; Redis ClusterIP 6379.
- Modularity & maintainability:
   - 3: Some reuse (e.g., deployment/service/pvc as patterns) but duplication remains.
   - 5: Clear reusable submodules plus an `app` composer; variables/outputs per module; minimal duplication.
- Clarity of reasoning & justification:
   - 3: Brief notes that partially explain choices.
   - 5: Concise, accurate justification of key choices and k3s specifics, anticipating local Docker Desktop realities.

1. Correctness (Docker Desktop)
   - Applies without errors to Docker Desktop; creates all 8 deployments, 4 services, and 3 PVCs
   - Uses correct provider blocks and syntax; `terraform validate` passes
2. Kubernetes fit & idioms
   - Proper labels/selectors, probes, sensible rollout settings
3. Storage handling
   - `storageClassName: local-path`, correct sizes and mounts
   - PVC resources set `wait_until_bound=false`
4. Image handling realism
   - Uses locally built/loaded Docker images available to the Docker Desktop cluster (no public pulls for private app images)
   - Notes that `docker build`/`docker load` is sufficient on Docker Desktop (no special `k3s ctr` import)
5. Networking & exposure
   - NodePort 30080..30082 wired to 8080..8082; Redis ClusterIP 6379
6. Modularity & maintainability
   - Clear structure; variables and outputs; no duplication
   - Module expectation increases with prompt level:
     - (1) modules optional; a flat structure is acceptable
     - (2) introduce basic reusable submodules (deployment, service, pvc) to reduce duplication
     - (3) full modularization including an application module that composes submodules
7. Clarity of reasoning & justification
   - Explains key choices and k3s specifics succinctly

Summary table per model:

| Aspect | Score (1-5) | Notes |
|-------:|:-----------:|------|
| Correctness (docker) |  |  |
| Kubernetes fit |  |  |
| Storage |  |  |
| Image handling |  |  |
| Networking |  |  |
| Modularity |  |  |
| Reasoning |  |  |
| Overall |  |  |

## Prompt sets (all for Docker Desktop)
Use rising specificity. Copy/paste as-is to query models.

### 1) Minimal Docker Desktop baseline
```
Create Terraform for Docker Desktop Kubernetes (single-node) to deploy the "Semantic Segmenter" app with:
- Namespace: `semseg`
- Deployments: ingest-api, results-api, qa-web, convert-ply, part-labeler, redactor, analytics, redis
- Services: ingest-api, results-api, qa-web, redis

Keep image names as variables and focus on generating the Kubernetes resources via Terraform. Use the default kubeconfig for Docker Desktop (on Windows: `%USERPROFILE%\.kube\config`), but you may accept an optional `kubeconfig` variable. You may assume reasonable service ports, exposure (NodePort vs ClusterIP), and storage details following best practices for Docker Desktop single-node clusters. Apply Terraform best practices for module structure and code quality (clear modules, variables, outputs, pinned providers). Use a shared image variable for workers and web UIs (`shared_image`), a separate image for `ingest-api` (`ingest_image`), and `redis:7-alpine` for Redis. Focus on a working, single-replica deployment; do not include autoscaling (HPA/VPA) or replica tuning. Do not include security hardening (RBAC, PodSecurityPolicy/SCC, NetworkPolicy, Pod/Container securityContext); focus only on the provided information.
At the end, include example Terraform commands to run (fmt, init, validate, apply). For apply, include -var assignments for any variables your solution requires.
```

What to look for: creates the named deployments and services in namespace `semseg`, chooses sensible defaults for exposure and storage without over-specifying, and produces clean Terraform structure.

### 2) Guided (Docker Desktop, explicit wiring)
```
Generate Terraform for Docker Desktop with the following details and wiring:
- Namespace: `semseg`
- Deployments (8): `ingest-api` (8080), `results-api` (8081), `qa-web` (8082), `convert-ply`, `part-labeler`, `redactor`, `analytics`, `redis` (6379)

Images:
- Use a shared image for workers and web UIs (e.g., `semantic-segmenter:latest`) and a separate image for `ingest-api` (e.g., `ingest-api:latest`)
- Use `redis:7-alpine` for Redis
- Prefer parameterizing these as variables (e.g., `image_repo` or `shared_image` for workers/web; `ingest_image` for ingest)

Services and ports:
- NodePorts: `ingest-api` 30080 -> targetPort 8080; `results-api` 30081 -> 8081; `qa-web` 30082 -> 8082
- `redis` as ClusterIP on port 6379

PVCs and volumes:
- Create three PVCs with `storageClassName=hostpath`, sizes: `sub-pc-frames-pvc` 64Mi, `pc-frames-pvc` 128Mi, `segments-pvc` 256Mi
- Set `wait_until_bound=false` on PVC resources (to avoid deadlocks under WaitForFirstConsumer)
- Mounts:
   - `convert-ply`: `/sub-pc-frames`, `/pc-frames`, `/segments`
   - `part-labeler`: `/pc-frames`, `/segments`
   - `redactor`: `/pc-frames`, `/segments`
   - `analytics`: `/segments`
   - `results-api`: `/segments`
   - `ingest-api`: `/sub-pc-frames`

Environment variables:
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

Probes and labels:
- Readiness and liveness HTTP probes on `/healthz` for `ingest-api`, `results-api`, `qa-web`
- All Pods and Services labeled `app=<name>`; Service selectors match labels

Outputs:
- Output three NodePort URLs for ingest, results, and qa.

Project structure:
- Introduce three simple reusable submodules: `deployment`, `service`, and `pvc`. Use these from the root module to reduce duplication.

Follow Terraform best practices for structuring modules, variables, outputs, and provider version pinning. Deploy each Deployment with replicas=1; do not include autoscaling (HPA/VPA) or scaling policies. Do not include security hardening (RBAC, PodSecurityPolicy/SCC, NetworkPolicy, Pod/Container securityContext); focus only on the specified details. At the end, include example Terraform commands to run (fmt, init, validate, apply). For apply, include -var assignments for the variables your solution requires.
```

### 3) Full blueprint (Docker Desktop, complete, first-try runnable)
```
Produce a complete, first-try runnable Terraform project for Docker Desktop with local images that applies cleanly and runs end-to-end without manual fixes. Avoid common pitfalls (service/targetPort mismatches, missing suffixes or prefixes and incorrect worker commands).

Providers and configuration:
- Required providers block with pinned versions.
- Kubernetes provider configured via default kubeconfig; accept an optional `kubeconfig` variable.

Project structure and variables:
- Root variables: `namespace` (default `semseg`), `image_repo` (default `semantic-segmenter:latest`), `ingest_image` (default `ingest-api:latest`), `node_port_base` (default `30080`), `pvc_storage_class_name` (default `hostpath`).
- Reusable submodules: `deployment`, `service`, `pvc`, plus an `app` module that composes all resources using these submodules.
- PVC submodule must set `wait_until_bound=false` and support `access_modes` (default `ReadWriteOnce`).
- File layout: in the root module and in each submodule, place variable declarations in `variables.tf` and outputs in `outputs.tf` (if any); keep resource logic in `main.tf`.

Resources to create (exact):
- Namespace: `semseg`.
- PVCs: `sub-pc-frames-pvc` 64Mi, `pc-frames-pvc` 128Mi, `segments-pvc` 256Mi using `var.pvc_storage_class_name`.
- Deployments (8): `ingest-api`, `results-api`, `qa-web`, `convert-ply`, `part-labeler`, `redactor`, `analytics`, `redis`.
- Services (idiomatic wiring):
  - `ingest-api` NodePort on `var.node_port_base + 0`, Service `port=80`, `target_port=8080`.
  - `results-api` NodePort on `var.node_port_base + 1`, Service `port=80`, `target_port=8081`.
  - `qa-web` NodePort on `var.node_port_base + 2`, Service `port=80`, `target_port=8082`.
  - `redis` ClusterIP `port=6379`.

Deployment wiring details:
- Labels/selectors: all Pods labeled `app=<name>`; Services select `app=<name>`.
- Container images: workers and web APIs use `var.image_repo`; ingest uses `var.ingest_image`; Redis uses `redis:7-alpine` with args `--appendonly yes --save ""`.
- Container ports: ingest 8080; results 8081; qa 8082; redis 6379.
- Image pull policy: default to `IfNotPresent` for app images (shared/ingest) to support local Docker Desktop images.
- Environment variables:
   - Common: `REDIS_URL=redis://redis.${var.namespace}.svc.cluster.local:6379/0`.
   - Streams:
      - `REDIS_STREAM_FRAMES_CONVERTED=s_frames_converted`
      - `REDIS_STREAM_PARTS_LABELED=s_parts_labeled`
      - `REDIS_STREAM_REDACTED_DONE=s_redacted_done`
      - `REDIS_STREAM_ANALYTICS_DONE=s_analytics_done`
   - Groups:
      - `REDIS_GROUP_PART_LABELER=g_part_labeler`
      - `REDIS_GROUP_REDACTOR=g_redactor`
      - `REDIS_GROUP_ANALYTICS=g_analytics`
   - `ingest-api`: `INGEST_OUT_DIR=/sub-pc-frames`.
   - `results-api`: `SEGMENTS_DIR=/segments`.
   - `qa-web`: `RESULTS_API_URL=http://results-api.${var.namespace}.svc.cluster.local` (no port; relies on Service `port=80`).
   - `convert-ply`: `PREVIEW_OUT_DIR=/segments`.
- Commands/args:
  - `results-api`: `bash -lc` with args `uvicorn services.results_api.app:app --host 0.0.0.0 --port 8081 --workers 1`.
  - `qa-web`: `bash -lc` with args `uvicorn services.qa_web.app:app --host 0.0.0.0 --port 8082 --workers 1`.
  - `convert-ply`: command `python3 /semantic-segmenter/services/convert_service/convert-ply` with args `--in-dir /sub-pc-frames --out-dir /pc-frames --preview-out-dir /segments --delete-source --log-level info`.
  - `part-labeler`: `bash -lc` with args `python3 /semantic-segmenter/services/part_labeler/part_labeler.py --log-level info --out-dir /segments --colorized-dir /segments/labels --write-colorized`.
  - `redactor`: `bash -lc` with args `python3 /semantic-segmenter/services/redactor/redactor.py --log-level info --out-dir /segments`.
  - `analytics`: `bash -lc` with args `python3 /semantic-segmenter/services/analytics/analytics.py --log-level info --out-dir /segments`.
- Volumes/mounts:
  - `convert-ply`: `/sub-pc-frames` -> `sub-pc-frames-pvc`, `/pc-frames` -> `pc-frames-pvc`, `/segments` -> `segments-pvc`.
  - `part-labeler`: `/pc-frames` -> `pc-frames-pvc`, `/segments` -> `segments-pvc`.
  - `redactor`: `/pc-frames` -> `pc-frames-pvc`, `/segments` -> `segments-pvc`.
  - `analytics`: `/segments` -> `segments-pvc`.
  - `results-api`: `/segments` -> `segments-pvc`.
  - `ingest-api`: `/sub-pc-frames` -> `sub-pc-frames-pvc`.

Health probes and rollout:
- Readiness and liveness HTTP probes on `/healthz` for `ingest-api`, `results-api`, `qa-web` with sensible initial delays/periods.
- Optional basic `resources` requests/limits (e.g., requests `100m/256Mi`).
- Replicas: 1 for all Deployments; do not include autoscaling (HPA/VPA).
- Security: do not include RBAC/NetworkPolicy/securityContext; defaults are fine.

Outputs:
- Output `ingest_url`, `results_url`, `qa_url` constructed from `localhost:<node_port>` using `var.node_port_base`.

Implementation quality:
 - Follow Terraform best practices for modules, variables, outputs, and provider version pinning.
- Use clean, minimal duplication; place common wiring in the `app` module and expose helpful outputs (e.g., Service names/URLs).
- Ensure all Terraform files are properly formatted and pass `terraform fmt -check`.

Finally, include example commands to run (fmt, init, validate, apply). For apply, show explicit -var assignments for: `namespace`, `image_repo`, `ingest_image`, `node_port_base`, `pvc_storage_class_name`.
```

## Evaluation procedure (Docker Desktop)
1. Prompt the model (use one of the prompts above).
2. Ensure I have a clean test namespace per candidate (or let Terraform create it).
3. Validate locally:
   - `terraform fmt -check`
   - `terraform init -upgrade`
   - `terraform validate`
4. Apply to Docker Desktop (example):
   - `terraform apply -var namespace="semseg" -var image_repo="semantic-segmenter:latest" -var ingest_image="ingest-api:latest" -var node_port_base=30080 -var pvc_storage_class_name="hostpath"`
5. Post-apply checks:
   - `kubectl get all -n semseg`
   - `kubectl get pvc -n semseg`
6. Functional HTTP checks from your desktop:
   - `curl http://localhost:30080/healthz` (ingest)
   - `curl http://localhost:30081/healthz` (results)
   - `curl http://localhost:30082/` (qa)
7. Score per rubric. Record fixes and time-to-first-success.

## Scoring template (per model)
```
Model: <name>
Prompt level: <1..3>
Candidate ID: <id>

Scores (1..5):
- Correctness (docker): 
- Kubernetes fit: 
- Storage: 
- Image handling: 
- Networking: 
- Modularity: 
- Reasoning: 

Overall (avg or weighted): 
Notes:
- 
- 
- 
```

## Appendix: runtime env vars, commands, and args (Docker Desktop)

The following values are extracted from the working Terraform in `infra/terraform/modules/app/main.tf` and assume the namespace `semseg`.

### ingest-api
- Env names: INGEST_OUT_DIR
- Env values:
   - INGEST_OUT_DIR=/sub-pc-frames
- Command: default image entrypoint
- Args: none

### results-api
- Env names: SEGMENTS_DIR, REDIS_URL, REDIS_STREAM_FRAMES_CONVERTED, REDIS_STREAM_PARTS_LABELED, REDIS_STREAM_REDACTED_DONE, REDIS_STREAM_ANALYTICS_DONE
- Env values:
   - SEGMENTS_DIR=/segments
   - REDIS_URL=redis://redis.semseg.svc.cluster.local:6379/0
   - REDIS_STREAM_FRAMES_CONVERTED=s_frames_converted
   - REDIS_STREAM_PARTS_LABELED=s_parts_labeled
   - REDIS_STREAM_REDACTED_DONE=s_redacted_done
   - REDIS_STREAM_ANALYTICS_DONE=s_analytics_done
- Command: bash -lc
- Args: uvicorn services.results_api.app:app --host 0.0.0.0 --port 8081 --workers 1

### qa-web
- Env names: RESULTS_API_URL
- Env values:
   - RESULTS_API_URL=http://results-api.semseg.svc.cluster.local
- Command: bash -lc
- Args: uvicorn services.qa_web.app:app --host 0.0.0.0 --port 8082 --workers 1

### convert-ply
- Env names: REDIS_URL, REDIS_STREAM_FRAMES_CONVERTED, PREVIEW_OUT_DIR
- Env values:
   - REDIS_URL=redis://redis.semseg.svc.cluster.local:6379/0
   - REDIS_STREAM_FRAMES_CONVERTED=s_frames_converted
   - PREVIEW_OUT_DIR=/segments
- Command: python3 /semantic-segmenter/services/convert_service/convert-ply
- Args: --in-dir /sub-pc-frames --out-dir /pc-frames --preview-out-dir /segments --delete-source --log-level info

### part-labeler
- Env names: REDIS_URL, REDIS_STREAM_PARTS_LABELED, REDIS_STREAM_FRAMES_CONVERTED, REDIS_GROUP_PART_LABELER
- Env values:
   - REDIS_URL=redis://redis.semseg.svc.cluster.local:6379/0
   - REDIS_STREAM_PARTS_LABELED=s_parts_labeled
   - REDIS_STREAM_FRAMES_CONVERTED=s_frames_converted
   - REDIS_GROUP_PART_LABELER=g_part_labeler
- Command: bash -lc
- Args: python3 /semantic-segmenter/services/part_labeler/part_labeler.py --log-level info --out-dir /segments --colorized-dir /segments/labels --write-colorized

### redactor
- Env names: REDIS_URL, REDIS_STREAM_PARTS_LABELED, REDIS_STREAM_REDACTED_DONE, REDIS_GROUP_REDACTOR
- Env values:
   - REDIS_URL=redis://redis.semseg.svc.cluster.local:6379/0
   - REDIS_STREAM_PARTS_LABELED=s_parts_labeled
   - REDIS_STREAM_REDACTED_DONE=s_redacted_done
   - REDIS_GROUP_REDACTOR=g_redactor
- Command: bash -lc
- Args: python3 /semantic-segmenter/services/redactor/redactor.py --log-level info --out-dir /segments

### analytics
- Env names: REDIS_URL, REDIS_STREAM_PARTS_LABELED, REDIS_STREAM_ANALYTICS_DONE, REDIS_GROUP_ANALYTICS
- Env values:
   - REDIS_URL=redis://redis.semseg.svc.cluster.local:6379/0
   - REDIS_STREAM_PARTS_LABELED=s_parts_labeled
   - REDIS_STREAM_ANALYTICS_DONE=s_analytics_done
   - REDIS_GROUP_ANALYTICS=g_analytics
- Command: bash -lc
- Args: python3 /semantic-segmenter/services/analytics/analytics.py --log-level info --out-dir /segments

### redis
- Env names: (none)
- Env values: (none)
- Command: default image entrypoint (redis:7-alpine)
- Args: --appendonly yes --save ""

### Redis streams and consumer groups
- Streams: s_frames_converted, s_parts_labeled, s_redacted_done, s_analytics_done
- Groups: g_part_labeler, g_redactor, g_analytics

Typical flow:
- convert-ply produces s_frames_converted
- part-labeler consumes s_frames_converted (group g_part_labeler) and produces s_parts_labeled
- redactor consumes s_parts_labeled (group g_redactor) and produces s_redacted_done
- analytics consumes s_parts_labeled (group g_analytics) and produces s_analytics_done
- results-api reads from these streams for status/lookups

### Directories and volumes
- /sub-pc-frames → PVC sub-pc-frames-pvc (64Mi)
   - Producers/consumers: ingest-api (writes), convert-ply (reads)
- /pc-frames → PVC pc-frames-pvc (128Mi)
   - Producers/consumers: convert-ply (writes), part-labeler (reads), redactor (reads)
- /segments → PVC segments-pvc (256Mi)
   - Producers/consumers: convert-ply (writes previews), part-labeler (writes labels and colorized), redactor (writes), analytics (writes), results-api (reads)
- /segments/labels (subdirectory under /segments)
   - Producer: part-labeler (colorized outputs)

PVC mount mapping by deployment (claim → mount):
- convert-ply: sub-pc-frames-pvc → /sub-pc-frames; pc-frames-pvc → /pc-frames; segments-pvc → /segments
- part-labeler: pc-frames-pvc → /pc-frames; segments-pvc → /segments
- redactor: pc-frames-pvc → /pc-frames; segments-pvc → /segments
- analytics: segments-pvc → /segments
- results-api: segments-pvc → /segments
- ingest-api: sub-pc-frames-pvc → /sub-pc-frames

### Why these URLs?
- In-cluster Service DNS: Kubernetes resolves Services as <service>.<namespace>.svc.cluster.local
   - Example: redis in namespace semseg → redis.semseg.svc.cluster.local
   - That’s why REDIS_URL is redis://redis.semseg.svc.cluster.local:6379/0
   - results-api is reachable in-cluster at http://results-api.semseg.svc.cluster.local
- From my machine (Docker Desktop): NodePorts expose ports on localhost
   - http://localhost:30080 (ingest), http://localhost:30081 (results), http://localhost:30082 (qa)
   - These map to Service targetPorts 8080/8081/8082 respectively

### Docker images and structure

Images used
- semantic-segmenter:latest — shared runtime for workers and web UIs (convert-ply, part-labeler, redactor, analytics, results-api, qa-web)
- ingest-api:latest — dedicated image for ingest-api
- redis:7-alpine — off-the-shelf Redis

Expectations for semantic-segmenter:latest
- Base: Linux image with Python 3.x
- App code present at /semantic-segmenter
- Dependencies from requirements.txt installed
- Contains these entrypoints (invoked by Terraform via command/args):
   - python3 /semantic-segmenter/services/convert_service/convert-ply
   - python3 /semantic-segmenter/services/part_labeler/part_labeler.py
   - python3 /semantic-segmenter/services/redactor/redactor.py
   - python3 /semantic-segmenter/services/analytics/analytics.py
   - uvicorn services.results_api.app:app --host 0.0.0.0 --port 8081 --workers 1
   - uvicorn services.qa_web.app:app --host 0.0.0.0 --port 8082 --workers 1
- Ports expected at runtime
   - 8081 (results-api), 8082 (qa-web)

Expectations for ingest-api:latest
- Also Python 3.x with app code available
- Default image entrypoint runs the API on port 8080 (Terraform does not set command/args)
- Exposes/serves /healthz on 8080

Which deployment uses which image
- Ingest: ingest-api:latest
- Results, QA, Convert, Part-labeler, Redactor, Analytics: semantic-segmenter:latest
- Redis: redis:7-alpine

Docker Desktop note
- Build or load these images locally before terraform apply. Docker Desktop shares the local Docker daemon with the Kubernetes cluster, so locally built images are available to Pods without extra steps.