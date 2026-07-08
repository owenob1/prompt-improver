#!/usr/bin/env bash
# scripts/backends/kiro.sh
# Adapter for Kiro CLI.

set -euo pipefail

PROMPT_FILE="$1"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: prompt file required" >&2
  exit 1
fi

# Kiro CLI supports headless for CI/CD.
exec kiro --prompt "$(cat "$PROMPT_FILE")" --headless 2>/dev/null || \
  kiro -p "$(cat "$PROMPT_FILE")" 2>/dev/null || \
  echo "Kiro CLI headless not available in current setup. Check https://kiro.dev/cli for flags."
