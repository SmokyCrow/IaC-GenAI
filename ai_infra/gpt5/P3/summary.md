Model: GPT-5 (Thinking: Auto)
Prompt level: 3
Candidate ID: gpt5-P3

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

Finally, include example commands to run (fmt, init, validate, apply). For apply, show explicit -var assignments for: `namespace`, `image_repo`, `ingest_image`, `node_port_base`, `pvc_storage_class_name`.
```

---

## Scoring (with notes)

Scores (1..5):
 Correctness (docker): 4 — Three extra prompts were required (per summary.txt); applies after 3–4 fixes under the revised rubric.
 Kubernetes fit: 5 — Commands use `bash -lc` with args and correct probes/selectors/labels, matching clarified criteria.
 Storage: 5 — PVCs sized exactly to baseline (64Mi/128Mi/256Mi) and mounted to correct paths; submodule sets `wait_until_bound=false` and `ReadWriteOnce`.
 Networking: 5 — Idiomatic Service `port=80` with `target_port` 8080/8081/8082; in-cluster URLs without ports; NodePorts exposed at 30080..30082 (confirmed to meet 5 per clarification).
- Networking: 5 — Idiomatic Service `port=80` with `target_port` 8080/8081/8082; in-cluster URLs without ports; NodePorts exposed at 30080..30082.
 Modularity: 5 — Clean `deployment`, `service`, and `pvc` submodules plus an `app` composer module; variables/outputs present per module. (Per clarification, P3 modularity 5 applies except for claude/P3.)
- Reasoning: 4 — Iterative fixes converged efficiently with minimal changes to achieve a first-try runnable structure after adjustments.

Overall (avg): 4.9 / 5

- Versus P1 (overall 3.4): P3 is stronger in Networking (5 vs 3) due to idiomatic Service wiring, and in Modularity (5 vs 3) with a proper `app` composer. Correctness similar (both required fixes), but P3 resolves to a cleaner end-state.
- Versus P2 (overall 3.7): P3 improves Networking (5 vs 3) by removing the need for explicit in-cluster ports and improves Modularity (5 vs 4) with an app-level composer module and clean file layout. Correctness remains at 3 due to initial syntax and entrypoint issues.
- Versus main (baseline expectations): P3 matches main on Networking idioms and modular composition. Minor deviations are limited to initial generation errors that were corrected.

## Local test apply command
```powershell
terraform apply `
  -var "namespace=semseg" `
  -var "image_repo=semantic-segmenter:latest" `
  -var "ingest_image=ingest-api:latest" `
  -var "node_port_base=30080" `
  -var "pvc_storage_class_name=hostpath" `
  -var 'kubeconfig=~/.kube/config'
```

## Notes
- Extra Prompt 1 fixed dynamic blocks but introduced single-line `http_get` usage; Extra Prompt 2 corrected the `http_get` blocks. Extra Prompt 3 removed the ingest-api command/args to use the image’s default entrypoint, resolving ModuleNotFoundError.