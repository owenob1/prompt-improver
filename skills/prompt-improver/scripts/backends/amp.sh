#!/usr/bin/env bash
# scripts/backends/amp.sh
# Amp execute mode (`amp -x`). Amp picks its own model (modes, not model ids),
# so PROMPT_IMPROVER_MODEL is ignored. Without --dangerously-allow-all, tools
# that need approval are refused. The prompt is piped on stdin.

set -euo pipefail

# shellcheck source=../lib/backend-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/backend-common.sh"
pi_backend_init "${1:-}"
pi_require_cli "See https://ampcode.com/" amp

if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  echo "amp has no model flag; ignoring model '$PROMPT_IMPROVER_MODEL'." >&2
fi

code=0
pi_run_bounded_stdin "$PI_OUT_FILE" "$PI_ERR_FILE" amp -x || code=$?
pi_finish amp "$code"
