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

exec claude -p "$(cat "$PROMPT_FILE")" --print "${MODEL_ARGS[@]}"
