#!/usr/bin/env bash
# scripts/standalone-improve.sh
# Basic standalone wrapper for prompt-improver.
# Requires a provider CLI or API key setup.
# Usage: bash scripts/standalone-improve.sh "your raw prompt" [mode]

set -euo pipefail

RAW="$1"
MODE="${2:-plan}"

if [ -z "$RAW" ]; then
  echo "Usage: $0 \"raw request\" [execute|plan]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use the main generator with settings
bash "$SCRIPT_DIR/generate-prompt.sh" \
  --mode "$MODE" \
  --raw-input "$RAW" \
  --conversation-summary "Standalone usage" \
  --cwd "$(pwd)"
