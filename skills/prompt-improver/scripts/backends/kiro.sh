#!/usr/bin/env bash
# scripts/backends/kiro.sh
# Kiro CLI headless (`kiro-cli chat --no-interactive`). Honors PROMPT_IMPROVER_MODEL.
# Tools are not pre-trusted (no --trust-all-tools), so the generator cannot act.

set -euo pipefail

# shellcheck source=../lib/backend-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/backend-common.sh"
pi_backend_init "${1:-}"
pi_require_cli "See https://kiro.dev/docs/cli/" kiro-cli kiro

ARGS=(chat --no-interactive)
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  ARGS+=(--model "$PROMPT_IMPROVER_MODEL")
fi

pi_prompt_fits_argv || pi_too_large_for kiro

code=0
pi_run_bounded "$PI_OUT_FILE" "$PI_ERR_FILE" "$PI_CLI" "${ARGS[@]}" "$(cat "$PI_PROMPT_FILE")" || code=$?
pi_finish kiro "$code"
