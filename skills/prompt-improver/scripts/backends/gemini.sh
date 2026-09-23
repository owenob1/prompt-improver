#!/usr/bin/env bash
# scripts/backends/gemini.sh
# Google Gemini CLI headless (`gemini -p`). Honors PROMPT_IMPROVER_MODEL.
#
# Since 2026-06-18 Gemini CLI serves only paid Gemini API keys, Enterprise Agent
# Platform keys and Code Assist Standard/Enterprise. Personal Google accounts
# should use the `agy` (Antigravity CLI) backend instead.
# `--approval-mode default` means tools that need approval are unavailable in
# headless mode, so the generator cannot edit files or run shell commands.

set -euo pipefail

# shellcheck source=../lib/backend-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/backend-common.sh"
pi_backend_init "${1:-}"
pi_require_cli "Install: npm install -g @google/gemini-cli (personal accounts: use the agy backend)" gemini

ARGS=(--output-format text --approval-mode default)
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  ARGS+=(-m "$PROMPT_IMPROVER_MODEL")
fi

code=0
if pi_prompt_fits_argv; then
  pi_run_bounded "$PI_OUT_FILE" "$PI_ERR_FILE" gemini -p "$(cat "$PI_PROMPT_FILE")" "${ARGS[@]}" || code=$?
else
  # Gemini CLI appends piped stdin to the -p prompt.
  echo "Prompt is $(pi_prompt_size) bytes; passing via stdin." >&2
  pi_run_bounded_stdin "$PI_OUT_FILE" "$PI_ERR_FILE" gemini -p "Follow the instructions provided on stdin." "${ARGS[@]}" || code=$?
fi
pi_finish gemini "$code"
