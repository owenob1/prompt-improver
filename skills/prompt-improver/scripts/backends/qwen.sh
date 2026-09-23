#!/usr/bin/env bash
# scripts/backends/qwen.sh
# Qwen Code headless (`qwen -p`). Honors PROMPT_IMPROVER_MODEL.
# `--approval-mode default` leaves approval-gated tools unavailable headless.

set -euo pipefail

# shellcheck source=../lib/backend-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/backend-common.sh"
pi_backend_init "${1:-}"
pi_require_cli "Install: npm install -g @qwen-code/qwen-code" qwen

ARGS=(--output-format text --approval-mode default)
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  ARGS+=(-m "$PROMPT_IMPROVER_MODEL")
fi

code=0
if pi_prompt_fits_argv; then
  pi_run_bounded "$PI_OUT_FILE" "$PI_ERR_FILE" qwen -p "$(cat "$PI_PROMPT_FILE")" "${ARGS[@]}" || code=$?
else
  echo "Prompt is $(pi_prompt_size) bytes; passing via stdin." >&2
  pi_run_bounded_stdin "$PI_OUT_FILE" "$PI_ERR_FILE" qwen -p "Follow the instructions provided on stdin." "${ARGS[@]}" || code=$?
fi
pi_finish qwen "$code"
