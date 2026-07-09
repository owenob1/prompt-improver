#!/usr/bin/env bash
# scripts/backends/codex.sh
# Adapter for OpenAI Codex CLI.

set -euo pipefail

PROMPT_FILE="${1:-}"

if [ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ]; then
  echo "Usage: $0 <prompt-file>" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "codex CLI not found. Install OpenAI Codex CLI, or set custom_command in settings." >&2
  exit 127
fi

exec codex exec "$(cat "$PROMPT_FILE")"
