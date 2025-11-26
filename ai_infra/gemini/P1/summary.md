Model: Gemini 2.5 pro
Prompt level: 1
Candidate ID: gemini2.5pro-P1

## Base-Prompt
```
Create Terraform for Docker Desktop Kubernetes (single-node) to deploy the "Semantic Segmenter" app with:
- Namespace: `semseg`
- Deployments: ingest-api, results-api, qa-web, convert-ply, part-labeler, redactor, analytics, redis
- Services: ingest-api, results-api, qa-web, redis

Keep image names as variables and focus on generating the Kubernetes resources via Terraform. Use the default kubeconfig for Docker Desktop (on Windows: `%USERPROFILE%\.kube\config`), but you may accept an optional `kubeconfig` variable. You may assume reasonable service ports, exposure (NodePort vs ClusterIP), and storage details following best practices for Docker Desktop single-node clusters. Apply Terraform best practices for module structure and code quality (clear modules, variables, outputs, pinned providers). Use a shared image variable for workers and web UIs (`shared_image`), a separate image for `ingest-api` (`ingest_image`), and `redis:7-alpine` for Redis. Focus on a working, single-replica deployment; do not include autoscaling (HPA/VPA) or replica tuning. Do not include security hardening (RBAC, PodSecurityPolicy/SCC, NetworkPolicy, Pod/Container securityContext); focus only on the provided information.
At the end, include example Terraform commands to run (fmt, init, validate, apply). For apply, include -var assignments for any variables your solution requires.
```

## Scoring (with notes)

Scores (1..5):
- Correctness (docker): 3 — Applies after several fixes. Initial schema/structure mistakes (e.g., `env` list vs block, `ports` vs `port`, duplicate `depends_on`) and a Redis DNS failure caused by Service/Deployment ordering. After removing the Service dependency and addressing schema issues, rollout proceeds.
- Kubernetes fit: 3 — Labels/selectors consistent; qa-web has HTTP probe, others used TCP/none. Some exposure/port conventions are inconsistent (mixed `port=80` and `port=8080`), and readiness endpoints aren’t standardized on `/healthz`.
- Storage: 4 — PVCs for sub-pc-frames, pc-frames, segments, plus redis-data are present and mounted correctly. Did not set `wait_until_bound=false`, which is preferred on Docker Desktop.
- Image handling: 5 — Uses `shared_image` and `ingest_image`; Redis pinned to `redis:7-alpine`; `image_pull_policy=IfNotPresent` matches local workflows.
- Networking: 3 — In-cluster DNS wiring correct; qa-web maps Service `port=80` → container `3000`, but other Services use service port equal to container port (non-idiomatic). Initial dependency ordering created a cycle/race but was resolved.
- Modularity: 3 — Single-root module with locals; no reusable `deployment`/`service`/`pvc` modules or app-level composer.
- Reasoning: 3 — Multiple prompt-driven iterations; some edits introduced unrelated regressions (double args, cycles) that needed manual cleanup.

Overall (avg): 3.4 / 5

## Evidence and highlights
- Services: mixed conventions — `qa-web` Service `port=80` (targetPort 3000), others often `port=8080`; NodePorts exposed. Removing Service→Deployment dependency eliminated DNS failures during pod start.
- PVCs: correct mounts for `/sub-pc-frames`, `/pc-frames`, `/segments`, plus Redis data at `/data`.
- Env/commands: redis URL normalized to include `/0`; commands/args added for results, qa, convert, labeler, redactor, analytics.
- Providers/layout: variables/outputs at root; additional redis-data PVC; image pull policy set to `IfNotPresent`.

- Versus claude/P1 (overall 2.6): Better Storage/Image handling and fewer structural deviations; still weaker on Networking idioms and Modularity (no submodules).
- Versus gpt5/P1 (overall 3.4): Comparable end-state and effort: both needed fixes; Networking and Modularity are similarly mid-level.
- Versus gpt5/P2 (overall 3.7)/P3 (overall 4.3): Trails on Networking (port 80/targetPort idiom) and Modularity (no app composer). Image handling comparable.

## Suggested remediation to reach 4–5
- Networking: normalize Services to `port=80` with `target_port` 8080/8081/3000 and remove explicit in-cluster ports from URLs.
- Kubernetes fit: add HTTP `/healthz` probes for ingest, results, and qa; standardize probe timings.
- Storage: set `wait_until_bound=false` on PVC resources for Docker Desktop.
- Modularity: introduce `deployment`, `service`, and `pvc` submodules and optionally an `app` composer module with shared outputs.
- Process: avoid broad edits that introduce regressions; keep changes localized to requested fixes.

## Provided structure (from candidate)
```
semseg-terraform/
├── semseg-terraform/
│   ├── main.tf                    
│   ├── variables.tf               
│   ├── outputs.tf                 
│   └── versions.tf                          
```

## Local test apply command
```powershell
terraform apply
```
