#!/usr/bin/env bash
# scripts/backends/codex.sh
# Adapter for OpenAI Codex CLI.
# Honors PROMPT_IMPROVER_MODEL when set.
#
# Known CLI quirks (codex 0.145.x observed):
# - `codex exec` streams its whole session log to stdout: version banner,
#   workdir/model/provider/approval/sandbox/session-id block, `hook:` lines,
#   MCP/skill-loading ERROR lines, the echoed prompt, and a trailing
#   `tokens used` count. Piping that straight through makes the log the
#   "improved prompt".
# - It also reads inherited stdin ("Reading additional input from stdin..."),
#   which appends a duplicate <stdin> block to the prompt.
# Mitigation: take the agent's final message from `-o/--output-last-message`,
# close stdin, and run read-only so the generator cannot execute the request.
# On failure the session log still goes to stdout so the caller's rate-limit
# detection can sniff it.

set -euo pipefail

PROMPT_FILE="${1:-}"

if [ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ]; then
  echo "Usage: $0 <prompt-file>" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "codex CLI not found. Install OpenAI Codex CLI, or set custom_command in settings." >&2
  exit 127
fi

MODEL_ARGS=()
if [ -n "${PROMPT_IMPROVER_MODEL:-}" ]; then
  MODEL_ARGS=(-m "$PROMPT_IMPROVER_MODEL")
fi

MSG_FILE=$(mktemp -t pi-codex-msg.XXXXXX)
LOG_FILE=$(mktemp -t pi-codex-log.XXXXXX)
ERR_FILE=$(mktemp -t pi-codex-err.XXXXXX)
trap 'rm -f "$MSG_FILE" "$LOG_FILE" "$ERR_FILE"' EXIT

set +e
codex exec \
  "${MODEL_ARGS[@]}" \
  --output-last-message "$MSG_FILE" \
  --sandbox read-only \
  --skip-git-repo-check \
  --color never \
  "$(cat "$PROMPT_FILE")" \
  >"$LOG_FILE" 2>"$ERR_FILE" </dev/null
CODE=$?
set -e

if [ -s "$ERR_FILE" ]; then
  sed 's/^/[codex stderr] /' "$ERR_FILE" >&2 || true
fi

if [ "$CODE" -eq 0 ] && [ -s "$MSG_FILE" ]; then
  cat "$MSG_FILE"
  exit 0
fi

# Failure (or empty final message): surface the session log so the caller can
# detect rate/usage limits and cascade, and keep the exit code intact.
sed 's/^/[codex log] /' "$LOG_FILE" >&2 || true
if [ -s "$LOG_FILE" ]; then
  cat "$LOG_FILE"
fi

if [ "$CODE" -eq 0 ]; then
  echo "codex exec exited 0 but wrote no final message." >&2
  exit 1
fi

exit "$CODE"
