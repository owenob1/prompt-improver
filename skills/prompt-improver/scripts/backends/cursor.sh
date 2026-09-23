#!/usr/bin/env bash
# scripts/backends/cursor.sh
# Cursor CLI headless (`agent -p`, formerly `cursor-agent`). Honors PROMPT_IMPROVER_MODEL.
# `--mode ask` is read-only and --force is never passed, so the generator cannot act.

set -euo pipefail

# shellcheck source=../lib/backend-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/backend-common.sh"
pi_backend_init "${1:-}"
pi_require_cli "See https://cursor.com/docs/cli" cursor-agent agent

ARGS=(--mode ask --output-format text)
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  ARGS+=(--model "$PROMPT_IMPROVER_MODEL")
fi

pi_prompt_fits_argv || pi_too_large_for cursor

code=0
pi_run_bounded "$PI_OUT_FILE" "$PI_ERR_FILE" "$PI_CLI" -p "$(cat "$PI_PROMPT_FILE")" "${ARGS[@]}" || code=$?
pi_finish cursor "$code"
