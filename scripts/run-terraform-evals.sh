#!/usr/bin/env bash
set -euo pipefail

# Configuration (env overrides supported)
SERVER_URL=${SERVER_URL:-http://127.0.0.1:8000}
TEMP=${TEMP:-0.22}
TOP_P=${TOP_P:-0.9}
TOP_K=${TOP_K:-40}
REPEAT_PENALTY=${REPEAT_PENALTY:-1.12}
REPEAT_LAST_N=${REPEAT_LAST_N:-256}
OUT_DIR=${OUT_DIR:-eval}
PROMPT_DIR=${PROMPT_DIR:-prompts}

mkdir -p "$OUT_DIR"

check_dep() { command -v "$1" >/dev/null || { echo "Missing dependency: $1" >&2; exit 1; }; }
check_dep jq
check_dep curl

health=$(curl -s "$SERVER_URL/health" || true)
if [[ -z "$health" ]]; then
  echo "[WARN] Health endpoint returned empty response. Server might be down: $SERVER_URL/health" >&2
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") -f <prompt_file> [-s <system_file>] [-n <n_predict>] [-o <out_name>] [--]

Required:
  -f <prompt_file>   Path to prompt text. If relative, resolved under \"$PROMPT_DIR\".

Optional:
  -s <system_file>   Path to a system/base prompt to prepend (acts as \"Terraform professional\").
  -n <n_predict>     Tokens to generate (default: 3072)
  -o <out_name>      Base name for output files (default: derived from prompt file)

Environment overrides:
  SERVER_URL, TEMP, TOP_P, TOP_K, REPEAT_PENALTY, REPEAT_LAST_N, OUT_DIR, PROMPT_DIR
EOF
}

run_prompt() {
  local out_name=$1 prompt_file=$2 np=$3
  if [[ ! -f "$prompt_file" ]]; then
    # try resolving under PROMPT_DIR
    if [[ -f "$PROMPT_DIR/$prompt_file" ]]; then
      prompt_file="$PROMPT_DIR/$prompt_file"
    else
      echo "[ERROR] Prompt file not found: $prompt_file" >&2
      return 1
    fi
  fi

  local req info_system=""
  # If a system prompt file is specified, resolve it similarly
  if [[ -n "$SYSTEM_FILE" ]]; then
    local sys_file="$SYSTEM_FILE"
    if [[ ! -f "$sys_file" && -f "$PROMPT_DIR/$sys_file" ]]; then
      sys_file="$PROMPT_DIR/$sys_file"
    fi
    if [[ -f "$sys_file" ]]; then
      info_system=" with system=$(basename "$sys_file")"
      req=$(jq -n \
        --rawfile s "$sys_file" \
        --rawfile p "$prompt_file" \
        '{prompt:($s+"\n\n"+$p), input:($s+"\n\n"+$p), n_predict:'"$np"', temperature:'"$TEMP"', top_p:'"$TOP_P"', top_k:'"$TOP_K"', repeat_penalty:'"$REPEAT_PENALTY"', repeat_last_n:'"$REPEAT_LAST_N"', stream:false}')
    else
      echo "[WARN] System file not found: $SYSTEM_FILE (skipping)" >&2
      req=$(jq -n --rawfile p "$prompt_file" '{prompt:$p, input:$p, n_predict:'"$np"', temperature:'"$TEMP"', top_p:'"$TOP_P"', top_k:'"$TOP_K"', repeat_penalty:'"$REPEAT_PENALTY"', repeat_last_n:'"$REPEAT_LAST_N"', stream:false}')
    fi
  else
    # No system prompt; just the user prompt
    req=$(jq -n --rawfile p "$prompt_file" '{prompt:$p, input:$p, n_predict:'"$np"', temperature:'"$TEMP"', top_p:'"$TOP_P"', top_k:'"$TOP_K"', repeat_penalty:'"$REPEAT_PENALTY"', repeat_last_n:'"$REPEAT_LAST_N"', stream:false}')
  fi
  printf '%s' "$req" > "$OUT_DIR/${out_name}-request.json"
  echo "[INFO] -> $out_name (n_predict=$np) using $(realpath -m "$prompt_file")$info_system" >&2
  local start_ts end_ts
  start_ts=$(date +%s%3N 2>/dev/null || date +%s)
  curl -sS -X POST "$SERVER_URL/completion" -H "Content-Type: application/json" --data-binary @"$OUT_DIR/${out_name}-request.json" > "$OUT_DIR/${out_name}.json"
  end_ts=$(date +%s%3N 2>/dev/null || date +%s)
  jq -r '.content // empty' "$OUT_DIR/${out_name}.json" > "$OUT_DIR/${out_name}-content.txt"
  jq '.timings // empty' "$OUT_DIR/${out_name}.json" > "$OUT_DIR/${out_name}-timings.json" 2>/dev/null || true
  echo "manual_elapsed_ms=$((end_ts-start_ts))" > "$OUT_DIR/${out_name}-elapsed.txt" 2>/dev/null || true
}

# CLI parsing
NP_DEFAULT=3072
PROMPT_FILE=""
OUT_NAME=""
while [[ ${1:-} ]]; do
  case "$1" in
    -f|--file) PROMPT_FILE=$2; shift 2 ;;
    -s|--system) SYSTEM_FILE=$2; shift 2 ;;
    -n|--n-predict) NP_DEFAULT=$2; shift 2 ;;
    -o|--out) OUT_NAME=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -z "$PROMPT_FILE" ]] && { echo "[ERROR] -f <prompt_file> is required" >&2; usage; exit 1; }

mkdir -p "$OUT_DIR"

if [[ -z "$OUT_NAME" ]]; then
  base=$(basename "$PROMPT_FILE")
  OUT_NAME="${base%.*}"
fi

run_prompt "$OUT_NAME" "$PROMPT_FILE" "$NP_DEFAULT"

echo "[DONE] Output files in $OUT_DIR with base: $OUT_NAME"
