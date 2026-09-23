#!/usr/bin/env bash
# scripts/backends/cline.sh
# Cline CLI headless. Honors PROMPT_IMPROVER_MODEL (`provider/model` ids).
#
# `-y` skips approval prompts and exits when done (required headless);
# `--plan` keeps it in plan mode so it cannot edit files. Note `-p` is
# --plan in Cline, not "prompt". Large prompts are piped on stdin.

set -euo pipefail

# shellcheck source=../lib/backend-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/backend-common.sh"
pi_backend_init "${1:-}"
pi_require_cli "See https://cline.bot/cli" cline

ARGS=(--plan -y)
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  ARGS+=(-m "$PROMPT_IMPROVER_MODEL")
fi

code=0
if pi_prompt_fits_argv; then
  pi_run_bounded "$PI_OUT_FILE" "$PI_ERR_FILE" cline "${ARGS[@]}" "$(cat "$PI_PROMPT_FILE")" || code=$?
else
  echo "Prompt is $(pi_prompt_size) bytes; passing via stdin." >&2
  pi_run_bounded_stdin "$PI_OUT_FILE" "$PI_ERR_FILE" cline "${ARGS[@]}" "Follow the instructions provided on stdin." || code=$?
fi
pi_finish cline "$code"
