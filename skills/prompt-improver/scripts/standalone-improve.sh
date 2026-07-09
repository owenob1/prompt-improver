#!/usr/bin/env bash
# scripts/standalone-improve.sh
# Basic standalone wrapper for prompt-improver.
# Requires a provider CLI (or custom_command in settings).
#
# Usage:
#   bash scripts/standalone-improve.sh "your raw prompt" [mode] [model]
#
# Examples:
#   bash scripts/standalone-improve.sh "Add rate limiting to the API"
#   bash scripts/standalone-improve.sh "Refactor auth" plan
#   bash scripts/standalone-improve.sh "Fix flaky tests" plan haiku
#   PROMPT_IMPROVER_BACKEND=claude bash scripts/standalone-improve.sh "Fix flaky tests"

set -euo pipefail

RAW="${1:-}"
MODE="${2:-plan}"
MODEL_ARG="${3:-}"

if [ -z "$RAW" ]; then
  echo "Usage: $0 \"raw request\" [execute|plan] [model]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ARGS=(
  --mode "$MODE"
  --raw-input "$RAW"
  --conversation-summary "Standalone usage"
  --cwd "$(pwd)"
)
if [ -n "$MODEL_ARG" ]; then
  ARGS+=(--model "$MODEL_ARG")
fi

bash "$SCRIPT_DIR/generate-prompt.sh" "${ARGS[@]}"
