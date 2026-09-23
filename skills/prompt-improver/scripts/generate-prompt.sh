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
#   # Safer for arbitrary user text (no shell expansion, no argv size limit):
#   bash scripts/generate-prompt.sh --mode plan --raw-input-file - <<'REQ'
#   your vague request
#   REQ
#
# Exit codes (load-bearing — SKILL.md and callers branch on them):
#   0  Success — improved XML on stdout
#   1  Invalid usage / missing args
#   2  Headless generation failed (hard error, only when fallback_strategy=error)
#   3  Host bounce — stdout starts HOST_BOUNCE:NO_HEADLESS or HOST_BOUNCE:RATE_LIMITED;
#      the HOST must complete the user request in-session
#   4  Generated, but validate-prompt.sh rejected it (body still printed)
# Any other failure is reported as 2.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh"
# shellcheck source=lib/backend-common.sh
source "$SCRIPT_DIR/lib/backend-common.sh"

TMP_PROMPT=""
TMP_CTX=""
TMP_RAW=""
TMP_OUT=""
TMP_ERR=""
TMP_BODY=""
TMP_HINTS=""

_cleanup() {
  local rc=$?
  rm -f ${TMP_PROMPT:+"$TMP_PROMPT"} ${TMP_CTX:+"$TMP_CTX"} ${TMP_RAW:+"$TMP_RAW"} \
    ${TMP_OUT:+"$TMP_OUT"} ${TMP_ERR:+"$TMP_ERR"} ${TMP_BODY:+"$TMP_BODY"} ${TMP_HINTS:+"$TMP_HINTS"}
  # Keep the exit-code contract: unexpected failures (126 E2BIG, 127, 141 SIGPIPE,
  # jq errors, …) become 2. Ctrl-C stays 130.
  case "$rc" in
    0|1|2|3|4|130) exit "$rc" ;;
    *) exit 2 ;;
  esac
}
trap _cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

usage() {
  cat <<'HELP'
Usage: bash scripts/generate-prompt.sh (--raw-input "..." | --raw-input-file <path|->) [options]

Options:
  --mode <execute|plan>              Mode label for the generator (default: execute)
  --raw-input <text>                 The vague request to improve
  --raw-input-file <path|->          Read the request from a file, or stdin with '-'
                                     (use this for text containing $, backticks or quotes)
  --model <id>                       Per-run generator model override (beats settings/env)
  --conversation-summary <text>      Optional session context
  --cwd <dir>                        Project directory (default: pwd). Also selects
                                     <dir>/.prompt-improver/settings.json
  --reference-materials-file <path>  Optional pre-built references file
  --skip-validate                    Print generation output even if validation fails
  -h, --help                         Show this help

Model resolution order:
  1. --model / per-prompt model: token
  2. PROMPT_IMPROVER_MODEL or settings.model
  3. settings.default_models[backend] (shipped: claude=opus, codex=gpt-6-sol,
     grok=grok-4.7, gemini=gemini-3.8-flash; other CLIs use their own default)
  4. Backend CLI default

Exit codes: 0 ok · 1 usage · 2 hard failure · 3 host bounce · 4 validation failed
HELP
}

_need_value() {
  if [ "$#" -lt 2 ]; then
    echo "Error: $1 requires a value." >&2
    echo "Run with --help for usage." >&2
    exit 1
  fi
}

MODE="execute"
RAW_INPUT=""
RAW_INPUT_SET=false
RAW_INPUT_FILE=""
CONVERSATION_SUMMARY="No prior conversation context."
CWD="$(pwd)"
REFERENCE_FILE=""
CLI_SKIP_VALIDATE=false
MODEL_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --mode) _need_value "$@"; MODE="$2"; shift 2 ;;
    --raw-input) _need_value "$@"; RAW_INPUT="$2"; RAW_INPUT_SET=true; shift 2 ;;
    --raw-input-file) _need_value "$@"; RAW_INPUT_FILE="$2"; shift 2 ;;
    --conversation-summary) _need_value "$@"; CONVERSATION_SUMMARY="$2"; shift 2 ;;
    --cwd) _need_value "$@"; CWD="$2"; shift 2 ;;
    --reference-materials-file) _need_value "$@"; REFERENCE_FILE="$2"; shift 2 ;;
    --model) _need_value "$@"; MODEL_OVERRIDE="$2"; shift 2 ;;
    --skip-validate) CLI_SKIP_VALIDATE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; echo "Run with --help for usage." >&2; exit 1 ;;
  esac
done

MODE=$(printf '%s' "$MODE" | tr '[:upper:]' '[:lower:]')
case "$MODE" in
  execute|plan) ;;
  *) echo "Error: --mode must be 'execute' or 'plan' (got '$MODE')." >&2; exit 1 ;;
esac

if [ ! -d "$CWD" ]; then
  echo "Error: --cwd '$CWD' is not a directory." >&2
  exit 1
fi
CWD="$(cd "$CWD" && pwd)"

if [ "$RAW_INPUT_SET" = true ] && [ -n "$RAW_INPUT_FILE" ]; then
  echo "Error: use either --raw-input or --raw-input-file, not both." >&2
  exit 1
fi
if [ -n "$RAW_INPUT_FILE" ]; then
  if [ "$RAW_INPUT_FILE" = "-" ]; then
    RAW_INPUT=$(cat)
  elif [ -f "$RAW_INPUT_FILE" ] && [ -r "$RAW_INPUT_FILE" ]; then
    RAW_INPUT=$(cat "$RAW_INPUT_FILE")
  else
    echo "Error: --raw-input-file '$RAW_INPUT_FILE' is not a readable file." >&2
    exit 1
  fi
fi

if [ -z "${RAW_INPUT//[[:space:]]/}" ]; then
  echo "Error: --raw-input (or --raw-input-file) is required and must not be empty" >&2
  echo "Run with --help for usage." >&2
  exit 1
fi

if [ -n "$REFERENCE_FILE" ] && [ ! -f "$REFERENCE_FILE" ]; then
  echo "Error: --reference-materials-file '$REFERENCE_FILE' not found." >&2
  exit 1
fi

pi_set_project_dir "$CWD"
load_settings
if [ "$CLI_SKIP_VALIDATE" = true ]; then
  SKIP_VALIDATE=true
fi

# Model ids end up on CLI command lines (and in eval'd templates): plain id characters only.
if [ -n "$MODEL_OVERRIDE" ]; then
  MODEL_OVERRIDE=$(_pi_strip_model_prefix "$MODEL_OVERRIDE")
  if ! pi_is_safe_model_id "$MODEL_OVERRIDE"; then
    echo "Error: invalid model id '$MODEL_OVERRIDE' (allowed: letters, digits, . _ - : / @ + [ ])." >&2
    exit 1
  fi
fi
if [ -n "$MODEL" ]; then
  MODEL=$(_pi_strip_model_prefix "$MODEL")
  if ! pi_is_safe_model_id "$MODEL"; then
    echo "Error: invalid model id '$MODEL' in settings/PROMPT_IMPROVER_MODEL." >&2
    exit 1
  fi
fi

# Print the machine-readable bounce marker (stdout) plus a human banner (stderr), exit 3.
host_bounce() {
  local kind="$1" detail="$2"
  cat >&2 <<EOF
=== HOST_BOUNCE:${kind} ===
${detail}
instruction: The host agent (this CLI session) MUST complete the user's original request in-session.
Do NOT re-run headless generation in a loop. Do NOT treat the block below as the improved prompt.
Optionally do a brief light improve yourself, then execute (or plan) the raw request.
=== END_HOST_BOUNCE ===
EOF
  printf 'HOST_BOUNCE:%s\n%s\nraw_request: %s\n' "$kind" "$detail" "$RAW_INPUT"
  exit 3
}

# --- Assemble the full prompt for the generator model ---
TMP_PROMPT=$(mktemp -t prompt-improver-gen.XXXXXX)
TMP_RAW=$(mktemp -t prompt-improver-raw.XXXXXX)
TMP_OUT=$(mktemp -t pi-be-out.XXXXXX)
TMP_ERR=$(mktemp -t pi-be-err.XXXXXX)
printf '%s\n' "$RAW_INPUT" >"$TMP_RAW"

# Deterministic context: shell gather-context only (no headless AI search/grep/glob).
CONTEXT_MODE="${CONTEXT_MODE:-deterministic}"
if [ "$CONTEXT_MODE" = "off" ] || [ "$CONTEXT_MODE" = "none" ]; then
  echo "Context gathering disabled (generation.context_mode=off)." >&2
  unset PROMPT_IMPROVER_PROJECT_CONTEXT_FILE || true
else
  if [ "$CONTEXT_MODE" != "deterministic" ] && [ "$CONTEXT_MODE" != "on" ]; then
    echo "WARNING: generation.context_mode=$CONTEXT_MODE — still pre-gathering; agent search remains forbidden by default." >&2
  fi
  TMP_CTX=$(mktemp -t prompt-improver-ctx.XXXXXX)
  _ctx_rc=0
  bash "$SCRIPT_DIR/gather-context.sh" "$CWD" >"$TMP_CTX" 2>/dev/null </dev/null || _ctx_rc=$?
  if [ "$_ctx_rc" -ne 0 ] || [ ! -s "$TMP_CTX" ]; then
    echo "WARNING: deterministic gather-context produced little/no output (rc=$_ctx_rc)." >&2
    [ -s "$TMP_CTX" ] || echo "(no project context gathered)" >"$TMP_CTX"
  else
    echo "Gathered deterministic project context ($(wc -c <"$TMP_CTX" | tr -d ' ') bytes)." >&2
  fi
  export PROMPT_IMPROVER_PROJECT_CONTEXT_FILE="$TMP_CTX"
fi

GENERATED=""
_generation_ok=false
TRIED_ATTEMPTS=""
LAST_FAILURE_KIND="error"   # rate_limit | error
FAST_TIER=""

# --- EXPERIMENTAL Jev fast path (settings fast_path.mode; default off) ---
# Jev only makes typed decisions (~70-500 ms). compose/auto may serve the request
# from templates with no LLM; route/auto otherwise hands back a model tier and
# reference pruning for the LLM path below. Any failure falls through unchanged.
if [ "${FAST_PATH_MODE:-off}" != "off" ] && [ -z "$CUSTOM_COMMAND" ]; then
  TMP_HINTS=$(mktemp -t prompt-improver-hints.XXXXXX)
  _fp_rc=0
  bash "$SCRIPT_DIR/fast-path.sh" "$FAST_PATH_MODE" "$TMP_RAW" "${TMP_CTX:-}" "$TMP_HINTS" \
    >"$TMP_OUT" 2>"$TMP_ERR" </dev/null || _fp_rc=$?
  [ -s "$TMP_ERR" ] && cat "$TMP_ERR" >&2
  if [ "$_fp_rc" -eq 0 ] && [ -s "$TMP_OUT" ]; then
    GENERATED=$(cat "$TMP_OUT")
    _generation_ok=true
    TRIED_ATTEMPTS="fast-path"
  else
    while IFS='=' read -r _hk _hv; do
      case "$_hk" in
        FAST_TIER) FAST_TIER="$_hv" ;;
        FAST_PRUNE)
          if [ "$_hv" = "true" ]; then
            export PROMPT_IMPROVER_GEN_INCLUDE_CHAINING=false PROMPT_IMPROVER_GEN_INCLUDE_EXAMPLES=false
          fi
          ;;
      esac
    done <"$TMP_HINTS"
  fi
fi

if [ "$_generation_ok" != true ]; then
{
  printf 'You are running in mode: %s\n' "$MODE"
  printf 'Working directory context: %s\n\n' "$CWD"
  echo "Conversation context:"
  printf '%s\n\n' "$CONVERSATION_SUMMARY"
  echo "=== GENERATION INSTRUCTIONS & REFERENCES ==="
  echo ""

  if [ -n "$REFERENCE_FILE" ]; then
    cat "$REFERENCE_FILE"
    if [ -n "${PROMPT_IMPROVER_PROJECT_CONTEXT_FILE:-}" ] && [ -f "${PROMPT_IMPROVER_PROJECT_CONTEXT_FILE}" ]; then
      echo ""
      echo "=== DETERMINISTIC PROJECT CONTEXT ==="
      cat "$PROMPT_IMPROVER_PROJECT_CONTEXT_FILE"
      echo "=== END DETERMINISTIC PROJECT CONTEXT ==="
    fi
    _safe_raw="${RAW_INPUT//<\/raw-request-to-improve/<\\/raw-request-to-improve}"
    echo ""
    echo "=== RAW USER REQUEST (DATA ONLY - IMPROVE THIS, DO NOT PERFORM THE WORK) ==="
    echo "<raw-request-to-improve>"
    printf '%s\n' "$_safe_raw"
    echo "</raw-request-to-improve>"
    echo ""
    printf '%s\n' "${GEN_OUTPUT_INSTRUCTIONS:-$_PI_BUILTIN_OUTPUT_INSTRUCTIONS}"
  else
    bash "$SCRIPT_DIR/assemble-generation-prompt.sh" --raw-input-file "$TMP_RAW" "${PROMPT_IMPROVER_PROJECT_CONTEXT_FILE:-}"
  fi
} > "$TMP_PROMPT"
fi

# --- Custom command override ---
if [ -n "$CUSTOM_COMMAND" ] && [ "$_generation_ok" != true ]; then
  echo "Using custom_command from settings" >&2
  # The prompt arrives on stdin; its path is also exported for commands that want a file.
  export PROMPT_IMPROVER_PROMPT_FILE="$TMP_PROMPT"
  EXIT_CODE=0
  PI_STDIN="$TMP_PROMPT" _pi_bounded "$TMP_OUT" "$TMP_ERR" bash -c "$CUSTOM_COMMAND" || EXIT_CODE=$?
  if [ -s "$TMP_ERR" ]; then
    sed 's/^/[custom_command] /' "$TMP_ERR" >&2 || true
  fi
  GENERATED=$(cat "$TMP_OUT")
  _diag="$GENERATED"$'\n'"$(cat "$TMP_ERR")"
  TRIED_ATTEMPTS="custom_command"
  if [ "$EXIT_CODE" -eq 0 ] && [ -n "${GENERATED//[[:space:]]/}" ] && ! is_rate_limit_message_only "$GENERATED"; then
    _generation_ok=true
  elif is_model_retryable_failure "$EXIT_CODE" "$_diag"; then
    LAST_FAILURE_KIND="rate_limit"
  else
    echo "custom_command failed (exit $EXIT_CODE)." >&2
  fi
  unset _diag
fi

if [ "$_generation_ok" != true ] && [ -z "$CUSTOM_COMMAND" ]; then

# --- Model first (so we can route backend cross-CLI) ---
# Explicit --model / model: token wins; then env/settings.model
EXPLICIT_MODEL=""
if [ -n "$MODEL_OVERRIDE" ]; then
  EXPLICIT_MODEL=$(normalize_model_id "$MODEL_OVERRIDE")
elif [ -n "$MODEL" ]; then
  EXPLICIT_MODEL=$(normalize_model_id "$MODEL")
fi

# --- Determine backend (host-matched defaults; no PATH auto-pick for the default) ---
# Priority:
#   1) model: / settings.model → infer CLI from model family (cross-host OK)
#   2) settings.backend when not auto
#   3) host CLI (Claude session → claude + opus, Codex → codex + gpt-6-sol, …)
#   4) else headless blocked → host bounce
read -r -a PREFS <<<"$(parse_preferred_backends)" || true
HOST_BACKEND=$(detect_host_backend)
INFERRED_BACKEND=""
if [ -n "$EXPLICIT_MODEL" ]; then
  INFERRED_BACKEND=$(infer_backend_for_model "$EXPLICIT_MODEL")
fi

BACKEND_TO_USE=""
SELECTION_REASON=""

if [ -n "$INFERRED_BACKEND" ]; then
  # model:gpt-6-sol → codex when installed (even if host is Claude)
  if pi_backend_available "$INFERRED_BACKEND"; then
    BACKEND_TO_USE="$INFERRED_BACKEND"
    SELECTION_REASON="model-family ($EXPLICIT_MODEL → $BACKEND_TO_USE)"
  else
    echo "WARNING: model '$EXPLICIT_MODEL' wants backend '$INFERRED_BACKEND' but that CLI is not on PATH." >&2
  fi
fi

[ "$BACKEND" = "openai" ] && BACKEND="codex"
if [ -z "$BACKEND_TO_USE" ] && [ "$BACKEND" != "auto" ]; then
  if is_supported_backend "$BACKEND"; then
    BACKEND_TO_USE="$BACKEND"
    SELECTION_REASON="settings.backend"
  else
    echo "WARNING: settings.backend '$BACKEND' is not a supported backend (see supported_backends, or use custom_command); ignoring it." >&2
  fi
fi

if [ -z "$BACKEND_TO_USE" ] && [ -n "$HOST_BACKEND" ] && is_supported_backend "$HOST_BACKEND"; then
  if pi_backend_available "$HOST_BACKEND"; then
    BACKEND_TO_USE="$HOST_BACKEND"
    SELECTION_REASON="host CLI ($HOST_BACKEND)"
  else
    echo "WARNING: host looks like '$HOST_BACKEND' but that CLI is not on PATH for headless." >&2
  fi
fi

if [ -z "$BACKEND_TO_USE" ]; then
  echo "Headless generation blocked: no host-matched generator and no model:/backend override." >&2
  echo "  host=${HOST_BACKEND:-none}  Set model:<id>, PROMPT_IMPROVER_BACKEND, or PROMPT_IMPROVER_HOST." >&2
  if [ "$FALLBACK_STRATEGY" = "error" ]; then
    echo "fallback_strategy=error: failing instead of bouncing to the host." >&2
    exit 2
  fi
  host_bounce "NO_HEADLESS" "host: ${HOST_BACKEND:-unknown}
reason: no supported headless generator for this host (not PATH auto-picking)"
fi
PRIMARY_BACKEND="$BACKEND_TO_USE"

# Vendor CLIs whose model ids follow the family tables (aliases + fallback chains).
_is_family_backend() {
  case "$1" in
    claude|grok|gemini|codex) return 0 ;;
  esac
  return 1
}

# Model to request from a given backend. An explicit model only goes to the CLI
# that can serve it; every other CLI gets its own default, never another
# family's id (grok -m opus would just fail).
_model_for_backend() {
  local b="$1"
  if [ -n "$EXPLICIT_MODEL" ]; then
    if [ "$INFERRED_BACKEND" = "$b" ]; then
      echo "$EXPLICIT_MODEL"; return 0
    fi
    if [ "$b" = "$PRIMARY_BACKEND" ] && { [ -z "$INFERRED_BACKEND" ] || ! _is_family_backend "$b"; }; then
      echo "$EXPLICIT_MODEL"; return 0
    fi
    if [ "$b" = "$PRIMARY_BACKEND" ]; then
      echo "WARNING: '$EXPLICIT_MODEL' is not a $b model; using $b's default." >&2
    fi
  fi
  # Fast-path route tier (only when the user did not pick a model).
  if [ -z "$EXPLICIT_MODEL" ] && [ -n "$FAST_TIER" ]; then
    local routed
    routed=$(pi_route_model "$b" "$FAST_TIER")
    if [ -n "$routed" ]; then
      echo "$routed"; return 0
    fi
  fi
  get_default_model_for_backend "$b"
}

_first_model=$(_model_for_backend "$BACKEND_TO_USE" 2>/dev/null)
echo "Using backend: $BACKEND_TO_USE via $SELECTION_REASON (model: ${_first_model:-CLI default})" >&2

# --- Invoke backends with model + CLI fallback, then host bounce ---
# Account-wide limits skip remaining models on that CLI and try another backend.
LAST_OUTPUT=""
LAST_DIAG=""

run_headless_once() {
  local backend_try="$1"
  local model_try="$2"
  local backend_script="$SCRIPT_DIR/backends/${backend_try}.sh"
  local code=0 inv=""

  export PROMPT_IMPROVER_MODEL="$model_try"
  : >"$TMP_OUT"
  : >"$TMP_ERR"

  # stdout and stderr are captured separately: stderr is shown as diagnostics and
  # used for limit detection, but never becomes part of the improved prompt.
  if [ -f "$backend_script" ] && should_use_backend_script "$backend_try"; then
    # Backend scripts bound their CLI with the timeout themselves.
    bash "$backend_script" "$TMP_PROMPT" >"$TMP_OUT" 2>"$TMP_ERR" </dev/null || code=$?
  else
    inv=$(get_backend_command "$backend_try" "$TMP_PROMPT" "$model_try")
    if [ -z "$inv" ]; then
      LAST_OUTPUT=""
      LAST_DIAG="no command template for backend '$backend_try'"
      return 127
    fi
    PI_STDIN=/dev/null _pi_bounded "$TMP_OUT" "$TMP_ERR" bash -c "$inv" || code=$?
  fi

  if [ -s "$TMP_ERR" ]; then
    sed "s/^/[${backend_try}] /" "$TMP_ERR" >&2 || true
  fi
  LAST_OUTPUT=$(cat "$TMP_OUT")
  LAST_DIAG="$LAST_OUTPUT"$'\n'"$(cat "$TMP_ERR")"

  # Limit messages sometimes arrive with exit 0
  if [ "$code" -eq 0 ] && is_rate_limit_message_only "$LAST_OUTPUT"; then
    return 1
  fi
  return "$code"
}

# Build ordered backend try list: primary first, then preferred_backends on PATH
_backend_try_list=("$BACKEND_TO_USE")
for _b in ${PREFS[@]+"${PREFS[@]}"}; do
  [ -z "$_b" ] && continue
  [ "$_b" = "openai" ] && _b="codex"
  case " ${_backend_try_list[*]} " in
    *" $_b "*) continue ;;
  esac
  is_supported_backend "$_b" || continue
  if pi_backend_available "$_b"; then
    _backend_try_list+=("$_b")
  fi
done

for BACKEND_TRY in "${_backend_try_list[@]}"; do
  _model_for_chain=$(_model_for_backend "$BACKEND_TRY")

  MODEL_TRY_LIST=()
  _SEEN_MODELS=" "
  if [ -n "$_model_for_chain" ]; then
    if _is_family_backend "$BACKEND_TRY"; then
      _chain=$(get_model_fallback_chain "$_model_for_chain")
    else
      # Multi-provider CLIs: the requested id, then the CLI's own default.
      _chain="$_model_for_chain"
    fi
    for _m in $_chain; do
      case "$_SEEN_MODELS" in
        *" $_m "*) continue ;;
      esac
      _SEEN_MODELS="$_SEEN_MODELS$_m "
      MODEL_TRY_LIST+=("$_m")
    done
    if [ "${#MODEL_TRY_LIST[@]}" -eq 0 ]; then
      MODEL_TRY_LIST=("$_model_for_chain")
    fi
    if ! _is_family_backend "$BACKEND_TRY"; then
      MODEL_TRY_LIST+=("")
    fi
  else
    MODEL_TRY_LIST=("")
  fi

  _skip_rest_of_backend=false
  for TRY_MODEL in "${MODEL_TRY_LIST[@]}"; do
    if [ "$_skip_rest_of_backend" = true ]; then
      break
    fi
    echo "Trying backend: $BACKEND_TRY (model: ${TRY_MODEL:-CLI default})" >&2
    TRIED_ATTEMPTS="${TRIED_ATTEMPTS}${BACKEND_TRY}/${TRY_MODEL:-default} "
    EXIT_CODE=0
    run_headless_once "$BACKEND_TRY" "$TRY_MODEL" || EXIT_CODE=$?
    GENERATED="$LAST_OUTPUT"

    if [ "$EXIT_CODE" -eq 0 ] && [ -n "${GENERATED//[[:space:]]/}" ] && ! is_rate_limit_message_only "$GENERATED"; then
      _generation_ok=true
      break
    fi

    if is_account_limit_failure "$LAST_DIAG"; then
      LAST_FAILURE_KIND="rate_limit"
      echo "Account/org limit on '$BACKEND_TRY' — skipping remaining models on this CLI." >&2
      _skip_rest_of_backend=true
      continue
    fi

    if is_model_retryable_failure "$EXIT_CODE" "$LAST_DIAG"; then
      LAST_FAILURE_KIND="rate_limit"
      echo "Model '${TRY_MODEL:-default}' failed (retryable: access/limit/unavailable). Trying next fallback…" >&2
      continue
    fi

    # Non-retryable failure (bad flags, auth, crash, timeout) — try next backend if any
    LAST_FAILURE_KIND="error"
    echo "Headless generation with $BACKEND_TRY / ${TRY_MODEL:-default} failed (exit $EXIT_CODE)." >&2
    _skip_rest_of_backend=true
  done

  if [ "$_generation_ok" = true ]; then
    break
  fi
  echo "Trying next available generator CLI…" >&2
done

fi  # end built-in backends

if [ "$_generation_ok" != true ]; then
  echo "Headless generation failed after trying: $TRIED_ATTEMPTS" >&2
  if [ "$LAST_FAILURE_KIND" = "rate_limit" ] || [ "$FALLBACK_STRATEGY" != "error" ]; then
    # Bounce to the host CLI/agent that invoked this skill so *it* completes the user work.
    host_bounce "RATE_LIMITED" "tried: ${TRIED_ATTEMPTS}
failure_kind: ${LAST_FAILURE_KIND}"
  fi
  echo "You may need to authenticate, install the target CLI, or pick another model." >&2
  exit 2
fi

# Unwrap CLI envelopes (e.g. --output-format json → { "text": "..." } / { "result": "..." })
if _pi_have_jq; then
  _unwrapped=$(jq -r 'if type=="object" then (.result // .text // .content // .message // empty) | strings else empty end' <<<"$GENERATED" 2>/dev/null || true)
  if [ -n "${_unwrapped:-}" ]; then
    GENERATED="$_unwrapped"
  fi
  unset _unwrapped
fi

# Drop CLI narration ahead of the XML (grok --output-format plain prefixes a
# line like "I'll read the full offloaded prompt ..." before <context>), and a
# dangling closing code fence when the model wrapped its answer in ```.
# Single awk pass with no early exit — an exiting reader would SIGPIPE the
# producer under `set -o pipefail`. Falls through untouched when no XML is
# present, so validation still reports the real body.
_stripped=$(printf '%s\n' "$GENERATED" | awk '
  started { lines[n++] = $0; next }
  /^[[:space:]]*<[a-zA-Z]/ { started = 1; lines[n++] = $0 }
  END {
    last = n - 1
    while (last >= 0 && lines[last] ~ /^[[:space:]]*$/) last--
    fences = 0
    for (i = 0; i <= last; i++) if (lines[i] ~ /^[[:space:]]*```/) fences++
    if (last >= 0 && fences % 2 == 1 && lines[last] ~ /^[[:space:]]*```[[:space:]]*$/) last--
    for (i = 0; i <= last; i++) print lines[i]
  }
')
if [ -n "${_stripped:-}" ]; then
  GENERATED="$_stripped"
fi
unset _stripped

# --- Validate ---
if [ "$SKIP_VALIDATE" = true ] || [ "$SKIP_VALIDATE" = "true" ]; then
  printf '%s\n' "$GENERATED"
  exit 0
fi

TMP_BODY=$(mktemp -t prompt-improver-body.XXXXXX)
printf '%s\n' "$GENERATED" >"$TMP_BODY"
if bash "$SCRIPT_DIR/validate-prompt.sh" "$TMP_BODY" >&2; then
  printf '%s\n' "$GENERATED"
  exit 0
fi

echo "Validation failed for generated prompt." >&2
echo "Re-run with --skip-validate to inspect raw output, or revise the request." >&2
# Still print the body so callers can inspect/retry
printf '%s\n' "$GENERATED"
exit 4
