#!/usr/bin/env bash
# assemble-generation-prompt.sh
#
# Low-level assembler. Most users should use `scripts/generate-prompt.sh` instead,
# which handles settings, backend detection, and calling the right CLI headlessly.

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
echo "=== RAW USER REQUEST (DATA ONLY - IMPROVE THIS, DO NOT PERFORM THE WORK) ==="
echo ""
echo "<raw-request-to-improve>"
echo "$RAW_INPUT"
echo "</raw-request-to-improve>"
echo ""
echo "Output ONLY the final improved XML prompt. No explanation, no execution of the request, nothing outside the XML."