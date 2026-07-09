#!/usr/bin/env bash
# scripts/backends/opencode.sh
# Adapter for OpenCode CLI.

set -euo pipefail

PROMPT_FILE="${1:-}"

if [ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ]; then
  echo "Usage: $0 <prompt-file>" >&2
  exit 1
fi

if ! command -v opencode >/dev/null 2>&1; then
  echo "opencode CLI not found. Install from https://opencode.ai" >&2
  exit 127
fi

if opencode -p "$(cat "$PROMPT_FILE")" 2>/dev/null; then
  exit 0
fi

exec opencode "$(cat "$PROMPT_FILE")" --non-interactive
