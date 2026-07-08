#!/usr/bin/env bash
# scripts/backends/cline.sh
# Adapter for Cline CLI (headless mode).
# Cline supports --prompt and --headless or similar.

set -euo pipefail

PROMPT_FILE="$1"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: prompt file required" >&2
  exit 1
fi

# Example invocation (adjust based on actual Cline CLI flags)
exec cline --prompt "$(cat "$PROMPT_FILE")" --headless 2>/dev/null || \
  cline -p "$(cat "$PROMPT_FILE")" 2>/dev/null || \
  echo "Cline CLI not found or no headless support in this version. See https://cline.bot/cli"
