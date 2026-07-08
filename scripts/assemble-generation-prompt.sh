#!/usr/bin/env bash
# assemble-generation-prompt.sh
#
# Assembles the full materials needed to run prompt-improver's generator
# with any coding CLI that supports a direct/headless prompt.
#
# Usage:
#   bash scripts/assemble-generation-prompt.sh "your raw request here"
#
# Then feed the output to your CLI in headless mode, e.g.:
#   claude -p "$(bash scripts/assemble-generation-prompt.sh 'add rate limiting')"
#   gemini -p "$(bash scripts/assemble-generation-prompt.sh '...')"
#   grok -p "$(bash scripts/assemble-generation-prompt.sh '...')"

set -euo pipefail

RAW_INPUT="${1:-}"

if [ -z "$RAW_INPUT" ]; then
  echo "Usage: $0 \"your raw prompt or request\"" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cat <<'PROMPT'
You are a prompt engineering specialist. Transform a raw user request into a structured XML prompt for a coding agent following these principles and template.
PROMPT

echo ""
echo "=== REFERENCE MATERIALS ==="
echo ""

cat "$ROOT_DIR/references/xml-template.md"
echo ""
cat "$ROOT_DIR/references/prompting-principles.md"
echo ""
cat "$ROOT_DIR/references/prompt-chaining.md"
echo ""
cat "$ROOT_DIR/examples/before-after.md"
echo ""
cat "$ROOT_DIR/assets/generation-agent-prompt.md"

echo ""
echo "=== RAW USER REQUEST ==="
echo ""
echo "$RAW_INPUT"
echo ""
echo "Output only the final improved XML prompt. No explanation outside the XML."