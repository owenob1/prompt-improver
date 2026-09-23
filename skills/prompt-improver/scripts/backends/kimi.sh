#!/usr/bin/env bash
# scripts/backends/kimi.sh
# Kimi Code CLI (MoonshotAI) headless (`kimi -p`). Honors PROMPT_IMPROVER_MODEL.
#
# Caution: in -p mode Kimi applies its `auto` permission policy to regular
# tool calls (static deny rules still apply). There is no read-only switch, so
# kimi is not in the default preferred_backends fallback list.

set -euo pipefail

# shellcheck source=../lib/backend-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/backend-common.sh"
pi_backend_init "${1:-}"
pi_require_cli "See https://moonshotai.github.io/kimi-code/" kimi

ARGS=(--output-format text)
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  ARGS+=(-m "$PROMPT_IMPROVER_MODEL")
fi

pi_prompt_fits_argv || pi_too_large_for kimi

code=0
pi_run_bounded "$PI_OUT_FILE" "$PI_ERR_FILE" kimi -p "$(cat "$PI_PROMPT_FILE")" "${ARGS[@]}" || code=$?
pi_finish kimi "$code"
