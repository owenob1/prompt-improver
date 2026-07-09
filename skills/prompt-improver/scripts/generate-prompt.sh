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
  3. settings.default_models[backend] (shipped: sonnet, grok-composer-2.5-fast, gemini-2.5-pro, gpt-5.5)
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

# --- Model first (so we can route backend cross-CLI) ---
# Explicit --model / model: token wins; then env/settings.model
if [ -n "$MODEL_OVERRIDE" ]; then
  MODEL=$(normalize_model_id "$MODEL_OVERRIDE")
elif [ -n "$MODEL" ]; then
  MODEL=$(normalize_model_id "$MODEL")
fi

# --- Determine backend ---
# shellcheck disable=SC2207
PREFS=( $(parse_preferred_backends) )
INFERRED_BACKEND=""
if [ -n "$MODEL" ]; then
  INFERRED_BACKEND=$(infer_backend_for_model "$MODEL")
fi

if [ "$BACKEND" = "auto" ]; then
  BACKEND_TO_USE=$(detect_backend "${PREFS[@]}")
  # model:gpt-5.5 → prefer codex if installed; model:sonnet / model:fable-5 → prefer claude
  if [ -n "$INFERRED_BACKEND" ]; then
    BACKEND_TO_USE=$(prefer_backend_if_available "$INFERRED_BACKEND" "$BACKEND_TO_USE")
  fi
else
  BACKEND_TO_USE="$BACKEND"
  # Even with a forced backend, re-route when model clearly belongs to another installed CLI
  if [ -n "$INFERRED_BACKEND" ] && [ "$INFERRED_BACKEND" != "$BACKEND_TO_USE" ]; then
    BACKEND_TO_USE=$(prefer_backend_if_available "$INFERRED_BACKEND" "$BACKEND_TO_USE")
  fi
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

# Fill model from per-backend defaults if still empty
if [ -z "$MODEL" ]; then
  MODEL=$(resolve_generator_model "$BACKEND_TO_USE")
fi

if [ -z "$MODEL" ]; then
  echo "WARNING: no generator model for backend '$BACKEND_TO_USE'." >&2
  echo "  Using CLI default. Prefer: --model <id> or default_models in settings." >&2
  echo "Using backend: $BACKEND_TO_USE (model: CLI default)" >&2
else
  if [ -n "$INFERRED_BACKEND" ] && [ "$INFERRED_BACKEND" != "$BACKEND_TO_USE" ]; then
    echo "Using backend: $BACKEND_TO_USE (model: $MODEL; preferred CLI for model was $INFERRED_BACKEND)" >&2
  else
    echo "Using backend: $BACKEND_TO_USE (model: $MODEL)" >&2
  fi
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
      codex|openai) INVOCATION="$INVOCATION -m $MODEL" ;;
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
