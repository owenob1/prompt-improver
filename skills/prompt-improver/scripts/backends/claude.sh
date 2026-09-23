#!/usr/bin/env bash
# scripts/backends/claude.sh
# Claude Code headless (`claude -p`). Honors PROMPT_IMPROVER_MODEL.
#
# The generator must never do the user's work, so every built-in tool is
# disabled (`--tools ""`) and anything else is denied (`--permission-mode
# dontAsk`). `--bare` is deliberately not used: it ignores OAuth/keychain
# auth, which would break subscription users.
# `--tools` is variadic — keep it directly before another flag, never before
# the positional prompt.

set -euo pipefail

# shellcheck source=../lib/backend-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/backend-common.sh"
pi_backend_init "${1:-}"
pi_require_cli "Install: npm install -g @anthropic-ai/claude-code" claude

ARGS=(--tools "" --output-format text --no-session-persistence --permission-mode dontAsk)
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  ARGS+=(--model "$PROMPT_IMPROVER_MODEL")
fi

code=0
if pi_prompt_fits_argv; then
  pi_run_bounded "$PI_OUT_FILE" "$PI_ERR_FILE" claude -p "$(cat "$PI_PROMPT_FILE")" "${ARGS[@]}" || code=$?
else
  echo "Prompt is $(pi_prompt_size) bytes; passing via stdin." >&2
  pi_run_bounded_stdin "$PI_OUT_FILE" "$PI_ERR_FILE" claude -p "${ARGS[@]}" || code=$?
fi
pi_finish claude "$code"
