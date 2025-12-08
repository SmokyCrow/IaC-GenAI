Model: Gemini 2.5 pro
Prompt level: 3
Candidate ID: gemini2.5pro-P3

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
  - `results-api`: single-string bash -lc invocation of uvicorn with app path.
  - `qa-web`: single-string bash -lc invocation of uvicorn with app path.
  - `convert-ply`: direct python3 script + args.
  - `part-labeler`: single-string bash -lc python invocation.
  - `redactor`: single-string bash -lc python invocation.
  - `analytics`: single-string bash -lc python invocation.
- Volumes/mounts:
  - `convert-ply`: `/sub-pc-frames`, `/pc-frames`, `/segments`.
  - `part-labeler`: `/pc-frames`, `/segments`.
  - `redactor`: `/pc-frames`, `/segments`.
  - `analytics`: `/segments`.
  - `results-api`: `/segments`.
  - `ingest-api`: `/sub-pc-frames`.

Health probes and rollout:
- HTTP readiness and liveness probes on `/healthz` for `ingest-api`, `results-api`, `qa-web`.
- Basic resources requests/limits optional.
- Replicas: 1 each; no autoscaling.
- No security hardening.

Outputs:
- `ingest_url`, `results_url`, `qa_url` from localhost NodePorts.

Implementation quality:
- Terraform formatting, pinned provider, module separation, composition via `app`.
```

## Scoring (with notes)
Scores (1..5):
- Correctness (docker): 5 — Two extra prompts were required (per summary.txt); applies after ≤2 fixes under the revised rubric.
- Kubernetes fit: 5 — Commands use `bash -lc` with args and correct probes/selectors/labels, matching clarified criteria.
- Storage: 5 — Three PVCs sized 64Mi/128Mi/256Mi, `hostpath` class via variable, `wait_until_bound=false`, mounts exactly match specified paths.
- Image handling: 5 — Shared vs ingest images parameterized; Redis pinned to 7-alpine; default `IfNotPresent` pull policy on deployment module (public Redis can use Always safely). Meets all prompt requirements.
- Networking: 5 — NodePorts consecutive from base; in-cluster URLs omit ports relying on Service abstraction; confirmed to meet 5 per clarification.
- Modularity: 5 — Reusable `deployment`, `service`, `pvc` modules plus an `app` composition module and structured outputs. Clear separation of variables/outputs.
- Reasoning: 4 — Prompt-driven corrections were minimal and targeted; issues resolved without introducing regressions. Deduction of proper single-string bash usage shows solid adjustment.

Overall (avg): 4.9 / 5

## Evidence and highlights
- versions.tf: pinned kubernetes provider `~> 2.31.0`.
- modules/app/main.tf: Service definitions use `port=80` / `target_port` pattern; env `RESULTS_API_URL` excludes explicit port.
- deployment module: fixed approach uses direct attribute assignment for `command`/`args` (no invalid dynamic blocks).
- pvc module: includes `wait_until_bound = var.wait_until_bound` with default false.
- outputs.tf: exposes `ingest_url`, `results_url`, `qa_url` using `node_port_base` arithmetic.
- app outputs: service names exported for composition.

## Versus other runs
- Versus gemini/P2 (overall 3.9): P3 improves Networking (5 vs 3) and Modularity (5 vs 4) with app-level composition and removal of explicit port in env URL; Storage/Image handling unchanged (5); Correctness similar (3).
- Versus gpt5/P3 (overall 4.3): Slightly higher due to Storage=5 vs 4 (gpt5/P3 lacked explicit wait_until_bound evidence or minor deviation) and Modularity parity; Correctness both at 3; Networking identical idiom.
- Versus claude/P2 (overall 4.1): Gains in Networking (5 vs 3) and Modularity (5 vs 4); same top scores for Storage/Image handling.

## Suggested remediation to reach perfect (5 across all)
- Correctness: eliminate need for post-generation fixes by validating command/args patterns at generation time.
- Kubernetes fit: optionally add uniform probe timing objects (shared local) and consider adding basic readiness grace period variable.
- Reasoning: preempt bash tokenization pitfall by standardizing single-string commands in initial output.

## Local test apply command
```powershell
terraform apply -var "namespace=semseg" -var "image_repo=semantic-segmenter:latest" -var "ingest_image=ingest-api:latest" -var "node_port_base=30080" -var "pvc_storage_class_name=hostpath" -var "kubeconfig=$HOME/.kube/config"
```
