#!/usr/bin/env bash
# scripts/backends/gemini.sh
# Adapter for Gemini CLI headless prompt improvement.
# Usage: bash scripts/backends/gemini.sh <prompt-file>

set -euo pipefail

PROMPT_FILE="$1"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: prompt file required" >&2
  exit 1
fi

# Gemini CLI headless: gemini -p "prompt"
# Note: May need --model or other flags depending on version.
exec gemini -p "$(cat "$PROMPT_FILE")" 2>/dev/null || echo "Gemini CLI not available or failed. Install with 'npm install -g @google/gemini-cli' or equivalent."
