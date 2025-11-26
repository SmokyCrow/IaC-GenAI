#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-semseg}"
HOST="${INGEST_HOST:-127.0.0.1}"
PORT="${INGEST_PORT:-30080}"
FRAMES="${FRAMES:-0 1 2 3}"
WAIT_SECONDS="${WAIT_SECONDS:-20}"

rollout() {
  local deploy="$1"
  echo "Waiting for deployment $deploy to be ready..."
  kubectl rollout status --timeout=120s "deployment/$deploy" -n "$NAMESPACE"
}

rollout ingest-api
rollout convert-ply
rollout part-labeler

echo
for frame in $FRAMES; do
  frame_id=$(printf "%05d" "$frame")
  file="$ROOT_DIR/0-${frame_id}.drc"
  if [[ ! -f "$file" ]]; then
    echo "Missing test payload: $file" >&2
    exit 1
  fi
  echo "Uploading frame $frame_id from $file"
  curl --fail --silent --show-error \
    -H 'Content-Type: application/octet-stream' \
    --data-binary @"$file" \
    "http://${HOST}:${PORT}/frames/${frame_id}" >/dev/null
  echo "  ok"
done

echo
if [[ "$WAIT_SECONDS" -gt 0 ]]; then
  echo "Waiting $WAIT_SECONDS seconds for processing to finish..."
  sleep "$WAIT_SECONDS"
fi

echo "Converted PLY files (convert-ply /pc-frames):"
if ! kubectl exec deploy/convert-ply -n "$NAMESPACE" -- ls -1 /pc-frames; then
  echo "  (merge deployment not reachable)" >&2
fi



echo
echo "Part labels (part-labeler /segments):"
if ! kubectl exec deploy/part-labeler -n "$NAMESPACE" -- sh -c "ls -1 /segments | grep '^labels' || true"; then
  echo "  (part-labeler deployment not reachable)" >&2
fi

echo
echo "Converter previews (convert-ply /segments):"
if ! kubectl exec deploy/convert-ply -n "$NAMESPACE" -- sh -c "ls -1 /segments | grep '^preview-' || true"; then
  echo "  (convert-ply deployment not reachable)" >&2
fi

echo
echo "Redactor outputs (redactor /segments):"
if ! kubectl exec deploy/redactor -n "$NAMESPACE" -- sh -c "ls -1 /segments | grep '^anonymized' || true"; then
  echo "  (redactor deployment not reachable)" >&2
fi