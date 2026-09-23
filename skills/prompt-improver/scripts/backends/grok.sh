#!/usr/bin/env bash
# scripts/backends/grok.sh
# xAI Grok Build CLI headless. Honors PROMPT_IMPROVER_MODEL.
#
# Known CLI quirks (observed on 0.2.x; still guarded on 1.x):
# - The process may hang after writing the final answer (never exits).
# - --prompt-file hangs more often than -p for short prompts.
# Mitigation: -p when the prompt fits argv, else --prompt-file; always bounded
# by a timeout (generation.grok_timeout_secs, default 180); non-empty stdout
# plus a timeout exit (124/137/143) counts as success.

set -euo pipefail

# shellcheck source=../lib/backend-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/backend-common.sh"
pi_backend_init "${1:-}"
pi_require_cli "See https://docs.x.ai/build/overview" grok

export PROMPT_IMPROVER_BACKEND_TIMEOUT="${PROMPT_IMPROVER_GROK_TIMEOUT:-${PROMPT_IMPROVER_BACKEND_TIMEOUT:-180}}"
MAX_TURNS="${PROMPT_IMPROVER_GROK_MAX_TURNS:-3}"

ARGS=(
  --output-format plain
  --always-approve
  --no-subagents
  --no-plan
  --disable-web-search
  --max-turns "$MAX_TURNS"
)
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  ARGS+=(-m "$PROMPT_IMPROVER_MODEL")
fi

code=0
if pi_prompt_fits_argv; then
  pi_run_bounded "$PI_OUT_FILE" "$PI_ERR_FILE" grok -p "$(cat "$PI_PROMPT_FILE")" "${ARGS[@]}" || code=$?
else
  echo "Prompt is $(pi_prompt_size) bytes; using --prompt-file." >&2
  pi_run_bounded "$PI_OUT_FILE" "$PI_ERR_FILE" grok --prompt-file "$PI_PROMPT_FILE" "${ARGS[@]}" || code=$?
fi
pi_finish grok "$code" true
