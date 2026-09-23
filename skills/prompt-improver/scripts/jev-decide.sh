#!/usr/bin/env bash
# scripts/jev-decide.sh
# One Jev (TypeSafe System One) call that answers every fast-path question about
# a raw request in parallel. Decisions only — Jev cannot write the prompt.
#
# Usage:
#   bash scripts/jev-decide.sh decide <raw-request-file> [context-file]
#   bash scripts/jev-decide.sh judge  <raw-request-file> <composed-prompt-file>
#
# Stdout: {"ms": <round-trip ms>, "answers": {…Jev answers…}}
# Exit:   0 ok · 1 usage · 2 Jev unavailable or failed (callers fall back)
#
# State sent to Jev: the redacted request, plus (decide) a trimmed deterministic
# context — tech stack, detected commands, top-level names. The agent-instruction
# excerpt and git history are left out: they are noise for these questions and
# Jev degrades on large irrelevant state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/jev.sh
source "$SCRIPT_DIR/lib/jev.sh"

KIND="${1:-}"
RAW_FILE="${2:-}"
EXTRA_FILE="${3:-}"
QUESTIONS="${PROMPT_IMPROVER_JEV_QUESTIONS:-$ROOT_DIR/assets/fast-templates/questions.json}"

case "$KIND" in
  decide|judge) ;;
  *) echo "Usage: $0 decide|judge <raw-request-file> [context-or-prompt-file]" >&2; exit 1 ;;
esac
if [ -z "$RAW_FILE" ] || [ ! -f "$RAW_FILE" ]; then
  echo "Usage: $0 $KIND <raw-request-file> [context-or-prompt-file]" >&2
  exit 1
fi
if [ "$KIND" = "judge" ] && { [ -z "$EXTRA_FILE" ] || [ ! -f "$EXTRA_FILE" ]; }; then
  echo "Usage: $0 judge <raw-request-file> <composed-prompt-file>" >&2
  exit 1
fi

if ! pi_jev_available; then
  echo "jev: unavailable (needs curl, jq and TYPESAFE_API_KEY or OPENROUTER_API_KEY)" >&2
  exit 2
fi

REQ=$(mktemp -t pi-jev-req.XXXXXX)
OUT=$(mktemp -t pi-jev-out.XXXXXX)
trap 'rm -f "$REQ" "$OUT"' EXIT

# Keep only the sections that bear on the questions; cap the size.
_trim_context() {
  awk '
    /^--- / {
      keep = ($0 ~ /TECH STACK|MONOREPO|CONFIGURATION|STRUCTURE|TEST PATTERNS|TYPECHECK COMMAND|TEST COMMAND|BUILD COMMAND/)
    }
    keep { print }
  ' "$1"
}

# Caps via substring, not `| head -c`: an early-exiting head SIGPIPEs the
# producer and fails the pipeline under pipefail.
REQUEST_TEXT=$(pi_jev_redact <"$RAW_FILE")
REQUEST_TEXT="${REQUEST_TEXT:0:24000}"

if [ "$KIND" = "decide" ]; then
  CONTEXT_TEXT=""
  if [ -n "$EXTRA_FILE" ] && [ -f "$EXTRA_FILE" ]; then
    CONTEXT_TEXT=$(_trim_context "$EXTRA_FILE" | pi_jev_redact || true)
    CONTEXT_TEXT="${CONTEXT_TEXT:0:6000}"
  fi
  jq -n --arg model "$(pi_jev_model)" --arg request "$REQUEST_TEXT" --arg project "$CONTEXT_TEXT" \
    --slurpfile q "$QUESTIONS" \
    '{model: $model,
      state: {request: $request, project: (if $project == "" then "(not available)" else $project end)},
      questions: $q[0].decide}' >"$REQ"
else
  SPEC_TEXT=$(pi_jev_redact <"$EXTRA_FILE")
  SPEC_TEXT="${SPEC_TEXT:0:24000}"
  jq -n --arg model "$(pi_jev_model)" --arg request "$REQUEST_TEXT" --arg spec "$SPEC_TEXT" \
    --slurpfile q "$QUESTIONS" \
    '{model: $model, state: {request: $request, specification: $spec}, questions: $q[0].judge}' >"$REQ"
fi

_now_ms() {
  local t
  t=$(date +%s%N 2>/dev/null || true)
  case "$t" in
    *N|'') echo $(( $(date +%s) * 1000 )) ;;   # BSD date has no %N
    *) echo $(( t / 1000000 )) ;;
  esac
}

START=$(_now_ms)
if ! pi_jev_call "$REQ" "$OUT"; then
  exit 2
fi
END=$(_now_ms)

jq -c --argjson ms "$((END - START))" '{ms: $ms, answers: .answers}' "$OUT"
