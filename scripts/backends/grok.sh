#!/usr/bin/env bash
# scripts/backends/grok.sh
# Invokes Grok Build headless for prompt generation.

set -euo pipefail

PROMPT_FILE="$1"

if [ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ]; then
  echo "Usage: $0 <prompt-file>" >&2
  exit 1
fi

# Use the current grok CLI in headless mode
# Adjust flags as the grok CLI evolves
exec grok -p "$(cat "$PROMPT_FILE")" --output-format json --yolo 2>/dev/null || \
  grok -p "$(cat "$PROMPT_FILE")" 
