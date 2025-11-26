# Utility Scripts

## Bash Versions (Git Bash / WSL)
- `deploy_k8s.sh` – applies manifests under `deploy/k8s` in the required order.
- `delete_k8s.sh` – deletes the manifest set in reverse and attempts to wipe PVC contents before removal.
- `test_pipeline.sh` – waits for pods, uploads sample `.drc` frames, then lists `/pc-frames` and `/segments` via `kubectl exec`.

## PowerShell Versions (Windows-native)
- `deploy_k8s.ps1`, `delete_k8s.ps1`, `test_pipeline.ps1` mirror the bash scripts and are safe to run when `bash` is blocked.
- Run with `powershell -File scripts/deploy_k8s.ps1` (or execute directly via `./scripts/deploy_k8s.ps1`).
- Optional overrides can be supplied through environment variables (`NAMESPACE`, `K8S_DIR`, `FRAMES`, etc.) or as explicit parameters.
- `delete_k8s.ps1` clears the mounted PVC directories (`/sub-pc-frames`, `/pc-frames`, `/segments`) before deleting the resources.

> Ensure `kubectl`, `curl`, and Docker Desktop’s Kubernetes cluster are accessible from the shell you use.