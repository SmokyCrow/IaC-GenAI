# Results API

Simple FastAPI application that serves generated artifacts from the `/segments` PVC and provides lightweight listing and download endpoints.

## Endpoints
- `GET /healthz` – readiness/liveness.
- `GET /frames` – list frames with artifact presence plus a small summary from `metrics-*.json` (if present).

- `GET /frames/{frame_id}/labels.json` – part labeler output.
- `GET /frames/{frame_id}/metrics.json` – analytics output.
- `GET /frames/{frame_id}/labels-colored.ply` – colorized preview PLY.
- `GET /frames/{frame_id}/anonymized.ply` – redacted PLY.
- `GET /frames/{frame_id}/preview.png` – 2D preview (produced upstream; no on-demand generation).

## Run locally
```bash
uvicorn services.results_api.app:app --reload --port 8081
```

## Kubernetes
A deployment and service are available in `deploy/k8s/70-results-api.yaml`. The service is exposed as NodePort `30081` by default. The upstream converter publishes to `s_frames_converted`.