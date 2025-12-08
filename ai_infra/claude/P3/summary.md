Model: Sonnet 4.5
Prompt level: 3
Candidate ID: sonnet4.5-P3

## Base-Prompt
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
```

## Scoring (with notes)

Scores (1..5):
- Correctness (docker): 5 — One extra prompt was required (per summary.txt); applies after ≤2 fixes per revised rubric.
- Kubernetes fit: 5 — Commands use `bash -lc` with args and correct probes/selectors/labels, matching clarified criteria.
- Storage: 5 — Three PVCs with `hostpath` class, sizes 64Mi/128Mi/256Mi, and `wait_until_bound=false`; mounts match the required paths.
- Image handling: 5 — Parameterized shared vs ingest images; Redis pinned to 7-alpine; default `IfNotPresent` policy across modules suits local images.
- Networking: 5 — Idiomatic Service `port=80` with `target_port` 8080/8081/8082; NodePorts on 30080/1/2; in-cluster URLs omit explicit ports (confirmed to meet 5 per clarification).
- Modularity: 4 — Submodules present; app module exists but root declares resources individually instead of invoking app once, per clarified rubric for score 5.
- Reasoning: 4 — Clear, minimal iteration to resolve a provider/schema nuance; concise and accurate justification.

Overall (avg): 4.7 / 5

## Evidence and highlights
- Root `main.tf`: Services specify `service_port = 80` and pass `port = 808x`, with NodePort computed from `node_port_base`.
- `modules/app`: builds probes when `enable_health_probes = true` and `port != null`; passes through env, command/args, and volumes.
- `modules/deployment`: defaults `image_pull_policy = IfNotPresent`; supports env maps, volume mounts, and HTTP probes.
- Redis declared via `modules/app` with `image = redis:7-alpine` and args `--appendonly yes --save ""`.
- Outputs: `ingest_url`, `results_url`, `qa_url` map to localhost NodePorts.

## Comparison
- Versus gpt5/P1 (overall 3.4): Much stronger on Networking (80/targetPort idiom) and Modularity (has an app composer); fewer manual corrections required.
- Versus gpt5/P2 (overall 3.7): Improves Networking by avoiding explicit in-cluster ports and ships an app composer; similar Storage/Image handling.
- Versus gpt5/P3 (overall 4.3): Higher Correctness and same idiomatic Networking; comparable Modularity and Storage; both use IfNotPresent and pinned Redis.
- Versus claude/P1 (overall 2.6): Significant improvements across all dimensions, especially Storage sizing/class and Networking idioms.
- Versus claude/P2 (overall 4.1): Removes need for `:8081` URL suffixes by adopting port=80 Services; adds an app composer and cleaner health probes.
- Versus main: Matches the baseline idioms (80/targetPort, hostpath PVCs with small sizes, Redis URL suffix /0, IfNotPresent), with modular composition.

## Local test apply command
```powershell
terraform -chdir=ai_infra/claude/P3/terraform-k8s-semseg apply
```