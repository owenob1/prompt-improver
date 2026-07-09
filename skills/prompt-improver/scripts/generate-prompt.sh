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
#
# Exit codes:
#   0  Success — improved XML on stdout
#   1  Invalid usage / missing args
#   2  Headless generation failed
#   3  Reserved
#   4  Validation failed (or fallback_strategy=error with no backend)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh"

load_settings

MODE="execute"
RAW_INPUT=""
CONVERSATION_SUMMARY="No prior conversation context."
CWD="$(pwd)"
REFERENCE_FILE=""
SKIP_VALIDATE=false
MODEL_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --mode) MODE="$2"; shift 2 ;;
    --raw-input) RAW_INPUT="$2"; shift 2 ;;
    --conversation-summary) CONVERSATION_SUMMARY="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --reference-materials-file) REFERENCE_FILE="$2"; shift 2 ;;
    --model) MODEL_OVERRIDE="$2"; shift 2 ;;
    --skip-validate) SKIP_VALIDATE=true; shift ;;
    -h|--help)
      cat <<'HELP'
Usage: bash scripts/generate-prompt.sh --raw-input "..." [options]

Options:
  --mode <execute|plan>              Mode label for the generator (default: execute)
  --raw-input <text>                 Required. Vague request to improve.
  --model <id>                       Per-run generator model override (beats settings/env)
  --conversation-summary <text>      Optional session context
  --cwd <dir>                        Working directory context (default: pwd)
  --reference-materials-file <path>  Optional pre-built references file
  --skip-validate                    Print generation output even if validation fails
  -h, --help                         Show this help

Model resolution order:
  1. --model / per-prompt model: token
  2. PROMPT_IMPROVER_MODEL or settings.model
  3. settings.default_models[backend] (shipped defaults: haiku, grok-composer-2.5-fast, …)
  4. Backend CLI default (discouraged)
HELP
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$RAW_INPUT" ]; then
  echo "Error: --raw-input is required" >&2
  echo "Run with --help for usage." >&2
  exit 1
fi

# --- Assemble the full prompt for the generator model ---
TMP_PROMPT=$(mktemp -t prompt-improver-gen.XXXXXX)
trap 'rm -f "$TMP_PROMPT"' EXIT

{
  echo "You are running in mode: $MODE"
  echo "Working directory context: $CWD"
  echo ""
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
    bash "$SCRIPT_DIR/assemble-generation-prompt.sh" "$RAW_INPUT"
  fi
} > "$TMP_PROMPT"

# --- Custom command override ---
if [ -n "$CUSTOM_COMMAND" ]; then
  echo "Using custom_command from settings" >&2
  set +e
  # shellcheck disable=SC2086
  GENERATED=$(eval "$CUSTOM_COMMAND" < "$TMP_PROMPT" 2>&1)
  EXIT_CODE=$?
  set -e
  if [ $EXIT_CODE -ne 0 ]; then
    echo "custom_command failed (exit $EXIT_CODE)." >&2
    exit 2
  fi
  echo "$GENERATED"
  exit 0
fi

# --- Determine backend ---
BACKEND_TO_USE="$BACKEND"

if [ "$BACKEND_TO_USE" = "auto" ]; then
  # shellcheck disable=SC2207
  PREFS=( $(parse_preferred_backends) )
  BACKEND_TO_USE=$(detect_backend "${PREFS[@]}")
fi

# Normalize aliases
if [ "$BACKEND_TO_USE" = "openai" ]; then
  BACKEND_TO_USE="codex"
fi

if [ "$BACKEND_TO_USE" = "unknown" ] || [ -z "$BACKEND_TO_USE" ]; then
  echo "WARNING: Could not detect a supported coding CLI with headless support." >&2
  echo "Falling back to manual mode. Printing the assembled generator prompt." >&2

  if [ "$FALLBACK_STRATEGY" = "error" ]; then
    exit 4
  fi

  cat "$TMP_PROMPT"
  exit 0
fi

# Model resolution: explicit override > env/settings.model > default_models[backend]
if [ -n "$MODEL_OVERRIDE" ]; then
  MODEL="$MODEL_OVERRIDE"
elif [ -z "$MODEL" ]; then
  MODEL=$(resolve_generator_model "$BACKEND_TO_USE")
fi

if [ -z "$MODEL" ]; then
  echo "WARNING: no generator model for backend '$BACKEND_TO_USE'." >&2
  echo "  Using CLI default (may be expensive). Prefer: --model <id> or default_models in settings." >&2
  echo "Using backend: $BACKEND_TO_USE (model: CLI default)" >&2
else
  echo "Using backend: $BACKEND_TO_USE (model: $MODEL)" >&2
fi

# Export so backend adapters can attach -m / --model
export PROMPT_IMPROVER_MODEL="${MODEL}"

# --- Invoke backend ---
BACKEND_SCRIPT="$SCRIPT_DIR/backends/$BACKEND_TO_USE.sh"
GENERATED=""
EXIT_CODE=0

if [ -x "$BACKEND_SCRIPT" ]; then
  set +e
  GENERATED=$("$BACKEND_SCRIPT" "$TMP_PROMPT")
  EXIT_CODE=$?
  set -e
else
  INVOCATION=$(get_backend_command "$BACKEND_TO_USE" "$TMP_PROMPT")

  if [ -n "$MODEL" ] && [ -n "$INVOCATION" ]; then
    case "$BACKEND_TO_USE" in
      grok)   INVOCATION="$INVOCATION -m $MODEL" ;;
      claude) INVOCATION="$INVOCATION --model $MODEL" ;;
      gemini) INVOCATION="$INVOCATION -m $MODEL" ;;
    esac
  fi

  if [ -z "$INVOCATION" ]; then
    echo "No headless template for backend '$BACKEND_TO_USE'. Falling back to manual." >&2
    if [ "$FALLBACK_STRATEGY" = "error" ]; then
      exit 4
    fi
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
    echo "=== FALLBACK: Assembled prompt for manual use ===" >&2
    cat "$TMP_PROMPT"
    exit 0
  fi
  exit 2
fi

# --- Validate ---
if [ "$SKIP_VALIDATE" = true ]; then
  echo "$GENERATED"
  exit 0
fi

if echo "$GENERATED" | bash "$SCRIPT_DIR/validate-prompt.sh" >&2; then
  echo "$GENERATED"
  exit 0
fi

echo "Validation failed for generated prompt." >&2
echo "Re-run with --skip-validate to inspect raw output, or revise the request." >&2
# Still print the body so callers can inspect/retry
echo "$GENERATED"
exit 4
