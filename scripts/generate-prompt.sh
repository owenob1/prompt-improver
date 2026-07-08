#!/usr/bin/env bash
# scripts/generate-prompt.sh
#
# The main portable generator for prompt-improver.
# - Loads settings (with overrides)
# - Detects or uses configured backend
# - Assembles the full generator prompt
# - Invokes the chosen CLI headlessly
# - Validates the result
#
# Usage:
#   bash scripts/generate-prompt.sh \
#     --mode "plan" \
#     --raw-input "your vague request" \
#     --conversation-summary "..." \
#     --cwd "."

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh"

load_settings

MODE="execute"
RAW_INPUT=""
CONVERSATION_SUMMARY=""
CWD="$(pwd)"
REFERENCE_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --mode) MODE="$2"; shift 2 ;;
    --raw-input) RAW_INPUT="$2"; shift 2 ;;
    --conversation-summary) CONVERSATION_SUMMARY="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --reference-materials-file) REFERENCE_FILE="$2"; shift 2 ;;
    *) echo "Unknown option $1"; exit 1 ;;
  esac
done

if [ -z "$RAW_INPUT" ]; then
  echo "Error: --raw-input is required" >&2
  exit 1
fi

# --- Assemble the full prompt for the generator model ---
TMP_PROMPT=$(mktemp)
trap 'rm -f "$TMP_PROMPT"' EXIT

# Base generator instructions + references
{
  echo "You are running in mode: $MODE"
  echo "Conversation context:"
  echo "$CONVERSATION_SUMMARY"
  echo ""
  echo "Raw user request:"
  echo "$RAW_INPUT"
  echo ""
  echo "=== GENERATION INSTRUCTIONS & REFERENCES ==="
  echo ""

  if [ -n "$REFERENCE_FILE" ] && [ -f "$REFERENCE_FILE" ]; then
    cat "$REFERENCE_FILE"
  else
    # Fallback to full assemble
    bash "$SCRIPT_DIR/assemble-generation-prompt.sh" "$RAW_INPUT"
  fi
} > "$TMP_PROMPT"

# --- Determine backend ---
BACKEND_TO_USE="$BACKEND"

if [ "$BACKEND_TO_USE" = "auto" ]; then
  # Parse preferred list (simple)
  if command -v jq >/dev/null 2>&1; then
    mapfile -t PREFS < <(jq -r '.[]' <<< "$PREFERRED_BACKENDS" 2>/dev/null || echo "grok claude gemini cline opencode kimi kiro codex")
  else
    PREFS=(grok claude gemini cline opencode kimi kiro codex)
  fi
  BACKEND_TO_USE=$(detect_backend "${PREFS[@]}")
fi

if [ "$BACKEND_TO_USE" = "unknown" ] || [ -z "$BACKEND_TO_USE" ]; then
  echo "WARNING: Could not detect a supported coding CLI with headless support." >&2
  echo "Falling back to manual mode. You will receive the assembled prompt." >&2

  if [ "$FALLBACK_STRATEGY" = "error" ]; then
    exit 4
  fi

  # Output the prompt for the user to use manually
  cat "$TMP_PROMPT"
  exit 0
fi

echo "Using backend: $BACKEND_TO_USE (model: ${MODEL:-default})" >&2

# --- Build invocation ---
BACKEND_SCRIPT="$SCRIPT_DIR/backends/$BACKEND_TO_USE.sh"

if [ -x "$BACKEND_SCRIPT" ]; then
  # Preferred: explicit backend adapter
  GENERATED=$("$BACKEND_SCRIPT" "$TMP_PROMPT")
  EXIT_CODE=$?
else
  INVOCATION=$(get_backend_command "$BACKEND_TO_USE" "$TMP_PROMPT")

  if [ -n "$MODEL" ]; then
    case "$BACKEND_TO_USE" in
      grok)   INVOCATION="$INVOCATION -m $MODEL" ;;
      claude) INVOCATION="$INVOCATION --model $MODEL" ;;
      gemini) INVOCATION="$INVOCATION -m $MODEL" ;;
    esac
  fi

  if [ -z "$INVOCATION" ]; then
    echo "No headless template for backend '$BACKEND_TO_USE'. Falling back to manual." >&2
    cat "$TMP_PROMPT"
    exit 0
  fi

  set +e
  GENERATED=$(eval "$INVOCATION" 2>&1)
  EXIT_CODE=$?
  set -e
fi

if [ $EXIT_CODE -ne 0 ]; then
  echo "Headless generation with $BACKEND_TO_USE failed (exit $EXIT_CODE)." >&2
  echo "You may need to authenticate or the CLI may not support headless in this context." >&2

  if [ "$FALLBACK_STRATEGY" = "manual" ]; then
    echo "=== FALLBACK: Here is the assembled prompt you can use manually ===" >&2
    cat "$TMP_PROMPT"
  fi
  exit $EXIT_CODE
fi

# --- Validate ---
echo "$GENERATED" | bash "$SCRIPT_DIR/validate-prompt.sh" || {
  echo "Validation failed. Retrying once with feedback..." >&2
  # Simple retry logic could be added here
  echo "$GENERATED"
  exit 4
}

echo "$GENERATED"