#!/usr/bin/env bash
#!/usr/bin/env bash
# Copy PLY files from part-labeler and redactor pods into
# separate subfolders under an output directory.
# Usage: ./copy_redacted_ply.sh [NAMESPACE] [OUT_DIR]

set -euo pipefail

NAMESPACE="${1:-semseg}"
OUT_DIR="${2:-./out_ply}"

lab_dir="$OUT_DIR/labeler"
red_dir="$OUT_DIR/redactor"
mkdir -p "$lab_dir" "$red_dir"

copy_list() {
  local ns="$1" pod="$2" list_cmd="$3" dest_dir="$4"
  mapfile -t files < <(kubectl exec -n "$ns" "$pod" -- sh -lc "$list_cmd" 2>/dev/null || true)
  local count=0
  for f in "${files[@]}"; do
    [[ -z "$f" ]] && continue
    local leaf
    leaf=$(basename "$f")
    kubectl cp "$ns/$pod:$f" "$dest_dir/$leaf"
    ((count++)) || true
  done
  echo "  copied $count file(s) to $dest_dir"
}

:

# Part-labeler: colorized previews under /segments/labels
lab_pod=$(kubectl get pod -n "$NAMESPACE" -l app=part-labeler -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "$lab_pod" ]]; then
  echo "Part-labeler -> $lab_dir"
  copy_list "$NAMESPACE" "$lab_pod" 'ls -1 /segments/labels/*.ply 2>/dev/null || true' "$lab_dir"
else
  echo "part-labeler pod not found" >&2
fi

# Redactor: anonymized-*.ply in /segments
red_pod=$(kubectl get pod -n "$NAMESPACE" -l app=redactor -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "$red_pod" ]]; then
  echo "Redactor -> $red_dir"
  copy_list "$NAMESPACE" "$red_pod" 'ls -1 /segments/anonymized-*.ply 2>/dev/null || true' "$red_dir"
else
  echo "redactor pod not found" >&2
fi

echo "Done. Output folders:"
echo "  - $lab_dir"
echo "  - $red_dir"
