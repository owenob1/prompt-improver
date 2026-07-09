#!/usr/bin/env bash
# scripts/backends/cline.sh
# Adapter for Cline CLI (headless mode when available).

set -euo pipefail

PROMPT_FILE="${1:-}"

if [ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ]; then
  echo "Usage: $0 <prompt-file>" >&2
  exit 1
fi

if ! command -v cline >/dev/null 2>&1; then
  echo "cline CLI not found. See https://cline.bot/cli" >&2
  exit 127
fi

if cline --prompt "$(cat "$PROMPT_FILE")" --headless 2>/dev/null; then
  exit 0
fi

exec cline -p "$(cat "$PROMPT_FILE")"
