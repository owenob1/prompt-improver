#!/usr/bin/env bash
# scripts/backends/copilot.sh
# GitHub Copilot CLI headless (`copilot -p`). Honors PROMPT_IMPROVER_MODEL.
# No --allow-all-tools, and shell/write are explicitly denied, so the generator
# cannot act. -s prints only the agent's answer; --no-ask-user never blocks.

set -euo pipefail

# shellcheck source=../lib/backend-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/backend-common.sh"
pi_backend_init "${1:-}"
pi_require_cli "Install: npm install -g @github/copilot" copilot

ARGS=(-s --no-ask-user --deny-tool shell --deny-tool write)
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  ARGS+=(--model "$PROMPT_IMPROVER_MODEL")
fi

pi_prompt_fits_argv || pi_too_large_for copilot

code=0
pi_run_bounded "$PI_OUT_FILE" "$PI_ERR_FILE" copilot -p "$(cat "$PI_PROMPT_FILE")" "${ARGS[@]}" || code=$?
pi_finish copilot "$code"
