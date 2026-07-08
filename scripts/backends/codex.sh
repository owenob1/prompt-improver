#!/usr/bin/env bash
# scripts/backends/codex.sh
# Adapter for Codex / OpenAI style CLI (if using codex or similar).

set -euo pipefail

PROMPT_FILE="$1"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: prompt file required" >&2
  exit 1
fi

# Placeholder for Codex-like: often `codex exec` or openai cli.
exec codex exec -c "$(cat "$PROMPT_FILE")" 2>/dev/null || \
  echo "Codex/OpenAI CLI headless. Use 'openai' or custom. Update this adapter with your command."
