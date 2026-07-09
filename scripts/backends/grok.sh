#!/usr/bin/env bash
# scripts/backends/grok.sh
# Invokes Grok Build headless for prompt generation.

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

# Prefer JSON output when available; fall back to plain text
if grok -p "$(cat "$PROMPT_FILE")" --output-format json --yolo 2>/dev/null; then
  exit 0
fi

exec grok -p "$(cat "$PROMPT_FILE")"
