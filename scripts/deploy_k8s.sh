#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K8S_DIR="${K8S_DIR:-$ROOT_DIR/deploy/k8s}"
NAMESPACE="${NAMESPACE:-semseg}"

manifests=(
  "00-namespace.yaml"
  "03-pvc.yaml"
  "05-redis.yaml"
  "06-postgres.yaml"
  "10-ingest-api.yaml"
  "20-convert.yaml"
  "40-part-labeler.yaml"
  "50-redactor.yaml"
  "60-analytics.yaml"
  "70-results-api.yaml"
  "80-qa-web.yaml"
)

echo "Applying Kubernetes manifests from $K8S_DIR"
for manifest in "${manifests[@]}"; do
  file="$K8S_DIR/$manifest"
  if [[ ! -f "$file" ]]; then
    echo "Missing manifest: $file" >&2
    exit 1
  fi
  echo "--- kubectl apply -f $manifest"
  kubectl apply -f "$file"
done

echo
echo "Workloads in namespace $NAMESPACE:"
kubectl get pods -n "$NAMESPACE"