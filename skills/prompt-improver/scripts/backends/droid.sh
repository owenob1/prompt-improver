#!/usr/bin/env bash
# scripts/backends/droid.sh
# Factory Droid headless (`droid exec`). Honors PROMPT_IMPROVER_MODEL.
# Default autonomy is read-only (no --auto), and the prompt is read from the
# file with -f, so there is no argv size limit.

set -euo pipefail

# shellcheck source=../lib/backend-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/backend-common.sh"
pi_backend_init "${1:-}"
pi_require_cli "See https://docs.factory.ai/" droid

ARGS=(exec -f "$PI_PROMPT_FILE")
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  ARGS+=(-m "$PROMPT_IMPROVER_MODEL")
fi

code=0
pi_run_bounded "$PI_OUT_FILE" "$PI_ERR_FILE" droid "${ARGS[@]}" || code=$?
pi_finish droid "$code"
