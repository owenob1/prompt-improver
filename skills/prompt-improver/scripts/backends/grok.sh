#!/usr/bin/env bash
# scripts/backends/grok.sh
# Invokes Grok Build headless for prompt generation.
# Honors PROMPT_IMPROVER_MODEL when set (generator model — prefer cheap/fast).

set -euo pipefail

PROMPT_FILE="${1:-}"

if [ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ]; then
  echo "Usage: $0 <prompt-file>" >&2
  exit 1
fi

if ! command -v grok >/dev/null 2>&1; then
  echo "grok CLI not found on PATH" >&2
  exit 127
fi

MODEL_ARGS=()
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  MODEL_ARGS=(-m "$PROMPT_IMPROVER_MODEL")
fi

# plain = improved prompt text only (json wraps body in .text and breaks validation)
exec grok -p "$(cat "$PROMPT_FILE")" "${MODEL_ARGS[@]}" --output-format plain --yolo
