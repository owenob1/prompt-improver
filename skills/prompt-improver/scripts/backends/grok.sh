#!/usr/bin/env bash
# scripts/backends/grok.sh
# Invokes Grok Build headlessly for prompt generation.
#
# Known CLI quirks (grok 0.2.x observed):
# - Process may hang after writing the final answer (never exits).
# - --prompt-file hangs more often than -p for short prompts; large -p can hit ARG_MAX.
# Mitigation: prefer -p under ARG_MAX/2; else --prompt-file; always bound with timeout;
# non-empty stdout + timeout (124/137/143) => success.

set -euo pipefail

PROMPT_FILE="${1:-}"

if [ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ]; then
  echo "Usage: $0 <prompt-file>" >&2
  exit 1
fi

if ! command -v grok >/dev/null 2>&1; then
  echo "grok CLI not found on PATH" >&2
  exit 127
fi

MODEL_ARGS=()
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  MODEL_ARGS=(-m "$PROMPT_IMPROVER_MODEL")
fi

TIMEOUT_SECS="${PROMPT_IMPROVER_GROK_TIMEOUT:-180}"
MAX_TURNS="${PROMPT_IMPROVER_GROK_MAX_TURNS:-3}"
ARG_MAX=$(getconf ARG_MAX 2>/dev/null || echo 262144)
# Leave headroom for env + argv overhead
SIZE_LIMIT=$(( ARG_MAX / 2 ))
FILE_SIZE=$(wc -c <"$PROMPT_FILE" | tr -d ' ')

OUT_FILE=$(mktemp -t pi-grok-out.XXXXXX)
ERR_FILE=$(mktemp -t pi-grok-err.XXXXXX)
trap 'rm -f "$OUT_FILE" "$ERR_FILE"' EXIT

COMMON=(
  --output-format plain
  --always-approve
  --no-subagents
  --no-plan
  --disable-web-search
  --max-turns "$MAX_TURNS"
  "${MODEL_ARGS[@]}"
)

if [ "$FILE_SIZE" -lt "$SIZE_LIMIT" ]; then
  # -p often exits cleanly for modest payloads
  GROK_CMD=(grok -p "$(cat "$PROMPT_FILE")" "${COMMON[@]}")
else
  echo "Prompt is ${FILE_SIZE} bytes (limit ${SIZE_LIMIT}); using --prompt-file." >&2
  GROK_CMD=(grok --prompt-file "$PROMPT_FILE" "${COMMON[@]}")
fi

run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout --signal=TERM --kill-after=5 "$TIMEOUT_SECS" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout --signal=TERM --kill-after=5 "$TIMEOUT_SECS" "$@"
  else
    "$@"
  fi
}

set +e
run_with_timeout "${GROK_CMD[@]}" >"$OUT_FILE" 2>"$ERR_FILE"
CODE=$?
set -e

if [ -s "$ERR_FILE" ]; then
  sed 's/^/[grok stderr] /' "$ERR_FILE" >&2 || true
fi

if [ -s "$OUT_FILE" ]; then
  if [ "$CODE" -ne 0 ] && { [ "$CODE" -eq 124 ] || [ "$CODE" -eq 137 ] || [ "$CODE" -eq 143 ]; }; then
    echo "WARNING: grok exited $CODE (timeout/hang) but produced output; using stdout." >&2
  fi
  cat "$OUT_FILE"
  # Non-empty body wins even on hang/timeout
  if [ "$CODE" -eq 0 ] || [ "$CODE" -eq 124 ] || [ "$CODE" -eq 137 ] || [ "$CODE" -eq 143 ]; then
    exit 0
  fi
  # Other non-zero with body (e.g. limit message on stdout) — pass through code for cascade
  exit "$CODE"
fi

if [ "$CODE" -eq 124 ] || [ "$CODE" -eq 137 ] || [ "$CODE" -eq 143 ]; then
  echo "grok timed out after ${TIMEOUT_SECS}s with no output (exit $CODE)." >&2
  exit 124
fi

echo "grok failed with exit ${CODE:-1} and empty stdout." >&2
exit "${CODE:-1}"
