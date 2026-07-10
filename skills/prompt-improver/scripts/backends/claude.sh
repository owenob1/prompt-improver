#!/usr/bin/env bash
# scripts/backends/claude.sh
# Invokes Claude Code headless for prompt generation.
# Honors PROMPT_IMPROVER_MODEL when set (generator model — prefer cheap/fast).

set -euo pipefail

PROMPT_FILE="${1:-}"

if [ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ]; then
  echo "Usage: $0 <prompt-file>" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "claude CLI not found on PATH" >&2
  exit 127
fi

MODEL_ARGS=()
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  MODEL_ARGS=(--model "$PROMPT_IMPROVER_MODEL")
fi

# Assembled prompts embed every reference file and can grow past ARG_MAX. Above the
# limit, pass the prompt on stdin (`claude --print` reads it there) instead of argv,
# which would otherwise fail with an opaque E2BIG.
ARG_MAX=$(getconf ARG_MAX 2>/dev/null || echo 262144)
SIZE_LIMIT=$(( ARG_MAX / 2 ))
FILE_SIZE=$(wc -c <"$PROMPT_FILE" | tr -d ' ')

if [ "$FILE_SIZE" -lt "$SIZE_LIMIT" ]; then
  exec claude -p "$(cat "$PROMPT_FILE")" --print "${MODEL_ARGS[@]}"
fi

echo "Prompt is ${FILE_SIZE} bytes (limit ${SIZE_LIMIT}); passing via stdin." >&2
exec claude --print "${MODEL_ARGS[@]}" <"$PROMPT_FILE"
