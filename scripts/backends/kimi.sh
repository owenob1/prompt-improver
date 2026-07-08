#!/usr/bin/env bash
# scripts/backends/kimi.sh
# Adapter for Kimi Code CLI (MoonshotAI).

set -euo pipefail

PROMPT_FILE="$1"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: prompt file required" >&2
  exit 1
fi

exec kimi "$(cat "$PROMPT_FILE")" --headless 2>/dev/null || \
  echo "Kimi CLI not found. See https://github.com/MoonshotAI/kimi-code or kimi-code docs for headless usage."
