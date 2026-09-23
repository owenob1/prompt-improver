#!/usr/bin/env bash
# scripts/backends/codex.sh
# OpenAI Codex CLI (`codex exec`). Honors PROMPT_IMPROVER_MODEL.
#
# Known CLI quirks (codex 0.14x–0.15x observed):
# - `codex exec` streams its whole session log to stdout (banner, config block,
#   hook/MCP lines, echoed prompt, token count). The agent's answer is taken
#   from `--output-last-message` instead.
# - It reads inherited stdin, appending a duplicate <stdin> block; stdin is
#   closed unless the prompt itself is passed there (`codex exec -`).
# - `--sandbox read-only` keeps the generator from executing the request;
#   `--ephemeral` keeps generator runs out of the user's session history.
# On failure the session log goes to stdout so the caller's limit detection
# can sniff it.

set -euo pipefail

# shellcheck source=../lib/backend-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/backend-common.sh"
pi_backend_init "${1:-}"
pi_require_cli "Install OpenAI Codex CLI (npm install -g @openai/codex), or set custom_command." codex

MSG_FILE=$(mktemp -t pi-codex-msg.XXXXXX)
trap 'rm -f "$PI_OUT_FILE" "$PI_ERR_FILE" "$MSG_FILE"' EXIT

ARGS=(exec --output-last-message "$MSG_FILE" --sandbox read-only --skip-git-repo-check --ephemeral --color never)
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  ARGS+=(-m "$PROMPT_IMPROVER_MODEL")
fi

code=0
if pi_prompt_fits_argv; then
  pi_run_bounded "$PI_OUT_FILE" "$PI_ERR_FILE" codex "${ARGS[@]}" "$(cat "$PI_PROMPT_FILE")" || code=$?
else
  echo "Prompt is $(pi_prompt_size) bytes; passing via stdin." >&2
  pi_run_bounded_stdin "$PI_OUT_FILE" "$PI_ERR_FILE" codex "${ARGS[@]}" - || code=$?
fi

if [ "$code" -eq 0 ] && [ -s "$MSG_FILE" ]; then
  if [ -s "$PI_ERR_FILE" ]; then
    sed 's/^/[codex stderr] /' "$PI_ERR_FILE" >&2 || true
  fi
  cat "$MSG_FILE"
  exit 0
fi

# Failure or empty final message: surface the session log (stdout) for limit sniffing.
if [ "$code" -eq 0 ]; then
  echo "codex exec exited 0 but wrote no final message." >&2
  code=1
fi
pi_finish codex "$code"
