#!/usr/bin/env bash
# scripts/backends/opencode.sh
# opencode headless (`opencode run`). Honors PROMPT_IMPROVER_MODEL
# (`provider/model` ids, e.g. anthropic/claude-sonnet-5).

set -euo pipefail

# shellcheck source=../lib/backend-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/backend-common.sh"
pi_backend_init "${1:-}"
pi_require_cli "See https://opencode.ai/docs/cli/" opencode

ARGS=(run)
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  ARGS+=(-m "$PROMPT_IMPROVER_MODEL")
fi

pi_prompt_fits_argv || pi_too_large_for opencode

code=0
pi_run_bounded "$PI_OUT_FILE" "$PI_ERR_FILE" opencode "${ARGS[@]}" "$(cat "$PI_PROMPT_FILE")" || code=$?
pi_finish opencode "$code"
