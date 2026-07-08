#!/usr/bin/env bash
# scripts/backends/opencode.sh
# Adapter for OpenCode CLI.

set -euo pipefail

PROMPT_FILE="$1"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: prompt file required" >&2
  exit 1
fi

# OpenCode typically supports direct prompts or specific flags for non-interactive.
exec opencode "$(cat "$PROMPT_FILE")" --non-interactive 2>/dev/null || \
  opencode -p "$(cat "$PROMPT_FILE")" 2>/dev/null || \
  echo "OpenCode not available. Install from https://opencode.ai"
