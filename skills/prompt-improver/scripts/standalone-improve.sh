#!/usr/bin/env bash
# scripts/standalone-improve.sh
# Basic standalone wrapper for prompt-improver.
# Requires a provider CLI (or custom_command in settings).
#
# Usage:
#   bash scripts/standalone-improve.sh "your raw prompt" [mode]
#
# Examples:
#   bash scripts/standalone-improve.sh "Add rate limiting to the API"
#   bash scripts/standalone-improve.sh "Refactor auth" plan
#   PROMPT_IMPROVER_BACKEND=claude bash scripts/standalone-improve.sh "Fix flaky tests"

set -euo pipefail

RAW="${1:-}"
MODE="${2:-plan}"

if [ -z "$RAW" ]; then
  echo "Usage: $0 \"raw request\" [execute|plan]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$SCRIPT_DIR/generate-prompt.sh" \
  --mode "$MODE" \
  --raw-input "$RAW" \
  --conversation-summary "Standalone usage" \
  --cwd "$(pwd)"
