#!/usr/bin/env bash
# scripts/backends/gemini.sh
# Adapter for Gemini CLI headless prompt improvement.
# Honors PROMPT_IMPROVER_MODEL when set.

set -euo pipefail

PROMPT_FILE="${1:-}"

if [ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ]; then
  echo "Usage: $0 <prompt-file>" >&2
  exit 1
fi

if ! command -v gemini >/dev/null 2>&1; then
  echo "gemini CLI not found. Install: npm install -g @google/gemini-cli" >&2
  exit 127
fi

MODEL_ARGS=()
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  MODEL_ARGS=(-m "$PROMPT_IMPROVER_MODEL")
fi

exec gemini -p "$(cat "$PROMPT_FILE")" "${MODEL_ARGS[@]}"
