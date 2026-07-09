#!/usr/bin/env bash
# scripts/backends/kimi.sh
# Adapter for Kimi Code CLI (MoonshotAI).

set -euo pipefail

PROMPT_FILE="${1:-}"

if [ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ]; then
  echo "Usage: $0 <prompt-file>" >&2
  exit 1
fi

if ! command -v kimi >/dev/null 2>&1; then
  echo "kimi CLI not found. See MoonshotAI / kimi-code docs for install and headless flags." >&2
  exit 127
fi

exec kimi "$(cat "$PROMPT_FILE")" --headless
