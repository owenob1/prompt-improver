#!/usr/bin/env bash
# scripts/backends/kiro.sh
# Adapter for Kiro CLI.

set -euo pipefail

PROMPT_FILE="${1:-}"

if [ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ]; then
  echo "Usage: $0 <prompt-file>" >&2
  exit 1
fi

if ! command -v kiro >/dev/null 2>&1; then
  echo "kiro CLI not found. Check https://kiro.dev/cli for install and flags." >&2
  exit 127
fi

if kiro --prompt "$(cat "$PROMPT_FILE")" --headless 2>/dev/null; then
  exit 0
fi

exec kiro -p "$(cat "$PROMPT_FILE")"
