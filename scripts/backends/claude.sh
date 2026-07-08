#!/usr/bin/env bash
# scripts/backends/claude.sh
# Invokes Claude Code headless.

set -euo pipefail

PROMPT_FILE="$1"

if [ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ]; then
  echo "Usage: $0 <prompt-file>" >&2
  exit 1
fi

exec claude -p "$(cat "$PROMPT_FILE")" --print
