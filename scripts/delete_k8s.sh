#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K8S_DIR="${K8S_DIR:-$ROOT_DIR/deploy/k8s}"
NAMESPACE="${NAMESPACE:-semseg}"

manifests=(
  "50-redactor.yaml"
  "40-part-labeler.yaml"
  "20-convert.yaml"
  "10-ingest-api.yaml"
  "05-redis.yaml"
  "03-pvc.yaml"
  "00-namespace.yaml"
)

clear_path() {
  local deploy="$1" path="$2"
  echo "Clearing $path via $deploy"
  if ! kubectl exec "deploy/${deploy}" -n "$NAMESPACE" -- sh -c "rm -rf ${path}/*" >/dev/null 2>&1; then
    echo "  (unable to clean $path on $deploy)" >&2
  fi
}

echo "Clearing PVC contents (if deployments are running)"
clear_path "ingest-api" "/sub-pc-frames"
clear_path "convert-ply" "/pc-frames"
# convert service does not drop a ready file; segments cleanup unchanged
clear_path "part-labeler" "/segments"


# The part-labeler may delete inputs itself, but explicitly clear its colorized outputs
clear_path "part-labeler" "/segments/labels"
# Redactor output
clear_path "redactor" "/segments"

echo "Deleting Kubernetes resources from $K8S_DIR"
for manifest in "${manifests[@]}"; do
  file="$K8S_DIR/$manifest"
  if [[ ! -f "$file" ]]; then
    echo "Skipping missing manifest: $file" >&2
    continue
  fi
  echo "--- kubectl delete -f $manifest"
  kubectl delete -f "$file" --ignore-not-found >/dev/null
  echo "  ok"
done

echo
echo "Remaining workloads in namespace $NAMESPACE:"
kubectl get pods -n "$NAMESPACE"