#!/usr/bin/env bash
# scripts/backends/agy.sh
# Google Antigravity CLI headless (`agy -p`) — the replacement for Gemini CLI on
# personal Google accounts. Honors PROMPT_IMPROVER_MODEL (see `agy models`).
# No auto-approval flag is passed, so the generator cannot run tools.

set -euo pipefail

# shellcheck source=../lib/backend-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/backend-common.sh"
pi_backend_init "${1:-}"
pi_require_cli "See https://antigravity.google/ (Antigravity CLI)" agy

ARGS=(--output-format text)
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  ARGS+=(--model "$PROMPT_IMPROVER_MODEL")
fi

pi_prompt_fits_argv || pi_too_large_for agy

code=0
pi_run_bounded "$PI_OUT_FILE" "$PI_ERR_FILE" agy -p "$(cat "$PI_PROMPT_FILE")" "${ARGS[@]}" || code=$?
pi_finish agy "$code"
