#!/usr/bin/env bash
# scripts/lib/backend-common.sh
# Shared helpers for scripts/backends/*.sh. Sourced, never executed.
#
# - pi_backend_init <prompt-file>        validate the prompt file, set PI_PROMPT_FILE
# - pi_require_cli <hint> <bin>...       first installed binary → PI_CLI, else exit 127
# - pi_prompt_fits_argv                  true when the prompt can go on argv safely
# - pi_run_bounded <out> <err> <cmd>...  run with a timeout; stdin from /dev/null
# - pi_run_bounded_stdin <out> <err> <cmd>...  same, prompt file on stdin
# - pi_finish <name> <code> [hang_ok]    print stdout/stderr, map exit code, exit
#
# Like lib/settings.sh this must not assign SCRIPT_DIR.

# Linux caps a single argv string at MAX_ARG_STRLEN (32 pages = 128 KiB) no matter
# how large ARG_MAX is; exceeding it fails with E2BIG ("Argument list too long").
# Stay well under both limits.
_PI_ARG_STRLEN_CAP=120000

PI_PROMPT_FILE=""
PI_CLI=""
PI_OUT_FILE=""
PI_ERR_FILE=""

pi_backend_init() {
  PI_PROMPT_FILE="${1:-}"
  if [ -z "$PI_PROMPT_FILE" ] || [ ! -f "$PI_PROMPT_FILE" ]; then
    echo "Usage: $0 <prompt-file>" >&2
    exit 1
  fi
  PI_OUT_FILE=$(mktemp -t pi-be-out.XXXXXX)
  PI_ERR_FILE=$(mktemp -t pi-be-err.XXXXXX)
  trap 'rm -f "$PI_OUT_FILE" "$PI_ERR_FILE"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

pi_require_cli() {
  local hint="$1" bin
  shift
  for bin in "$@"; do
    if command -v "$bin" >/dev/null 2>&1; then
      PI_CLI="$bin"
      return 0
    fi
  done
  echo "$1 CLI not found on PATH. $hint" >&2
  exit 127
}

pi_prompt_fits_argv() {
  local size arg_max limit
  size=$(wc -c <"$PI_PROMPT_FILE" | tr -d ' ')
  arg_max=$(getconf ARG_MAX 2>/dev/null || echo 262144)
  limit=$(( arg_max / 2 ))
  [ "$limit" -gt "$_PI_ARG_STRLEN_CAP" ] && limit=$_PI_ARG_STRLEN_CAP
  [ "$size" -lt "$limit" ]
}

pi_prompt_size() {
  wc -c <"$PI_PROMPT_FILE" | tr -d ' '
}

# Fail cleanly when the prompt is too large for argv and the CLI has no
# documented file or stdin input. Exit 2 = hard error → caller tries next backend.
pi_too_large_for() {
  echo "Prompt is $(pi_prompt_size) bytes — too large for argv, and $1 has no known file/stdin prompt input." >&2
  exit 2
}

_pi_timeout_secs() {
  local t="${PROMPT_IMPROVER_BACKEND_TIMEOUT:-300}"
  case "$t" in
    ''|*[!0-9]*) t=300 ;;
  esac
  echo "$t"
}

# Run "$@" bounded by PROMPT_IMPROVER_BACKEND_TIMEOUT seconds (0 = unbounded).
# Timeout exits 124 like coreutils `timeout`. stdin comes from $PI_STDIN.
_pi_bounded() {
  local out="$1" err="$2"
  shift 2
  local secs code=0
  secs=$(_pi_timeout_secs)

  if [ "$secs" -eq 0 ]; then
    "$@" >"$out" 2>"$err" <"$PI_STDIN" || code=$?
    return "$code"
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout --kill-after=5 "$secs" "$@" >"$out" 2>"$err" <"$PI_STDIN" || code=$?
    return "$code"
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout --kill-after=5 "$secs" "$@" >"$out" 2>"$err" <"$PI_STDIN" || code=$?
    return "$code"
  fi

  # Stock macOS has neither: pure-bash watchdog. Its stdio goes to /dev/null so a
  # lingering `sleep` never holds the caller's pipes open.
  local flag pid wd
  flag=$(mktemp -t pi-be-to.XXXXXX)
  rm -f "$flag"
  "$@" >"$out" 2>"$err" <"$PI_STDIN" &
  pid=$!
  (
    sleep "$secs"
    if kill -0 "$pid" 2>/dev/null; then
      : >"$flag"
      kill -TERM "$pid" 2>/dev/null
      sleep 5
      kill -KILL "$pid" 2>/dev/null
    fi
  ) >/dev/null 2>&1 </dev/null &
  wd=$!
  wait "$pid" || code=$?
  kill "$wd" 2>/dev/null || true
  wait "$wd" 2>/dev/null || true
  if [ -e "$flag" ]; then
    rm -f "$flag"
    return 124
  fi
  return "$code"
}

pi_run_bounded() {
  PI_STDIN=/dev/null _pi_bounded "$@"
}

pi_run_bounded_stdin() {
  PI_STDIN="$PI_PROMPT_FILE" _pi_bounded "$@"
}

# Emit the captured output and exit with a contract-friendly code.
# hang_ok=true: a timeout/kill with non-empty stdout counts as success (CLIs that
# print the answer and then fail to exit).
pi_finish() {
  local name="$1" code="$2" hang_ok="${3:-false}"
  local timed_out=false

  case "$code" in
    124|137|143) timed_out=true ;;
  esac

  if [ -s "$PI_ERR_FILE" ]; then
    sed "s/^/[$name stderr] /" "$PI_ERR_FILE" >&2 || true
  fi

  if [ -s "$PI_OUT_FILE" ]; then
    cat "$PI_OUT_FILE"
    if [ "$code" -eq 0 ]; then
      exit 0
    fi
    if [ "$timed_out" = true ] && [ "$hang_ok" = true ]; then
      echo "WARNING: $name exited $code (timeout/hang) but produced output; using stdout." >&2
      exit 0
    fi
  elif [ "$code" -eq 0 ]; then
    # Exit 0 with empty stdout: limit/auth text sometimes lands on stderr only.
    # Replay it on stdout so the caller's limit detection can see it.
    if [ -s "$PI_ERR_FILE" ]; then
      cat "$PI_ERR_FILE"
    fi
    echo "$name exited 0 but produced no output." >&2
    exit 1
  fi

  if [ "$timed_out" = true ]; then
    echo "$name timed out after $(_pi_timeout_secs)s (exit $code)." >&2
    exit 124
  fi
  exit "$code"
}
