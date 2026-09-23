#!/usr/bin/env bash
# scripts/fast-path.sh
# EXPERIMENTAL Jev fast path, called by generate-prompt.sh before the LLM path.
#
# Usage:
#   bash scripts/fast-path.sh <mode> <raw-request-file> <project-dir> <hints-out-file>
#
# mode (settings fast_path.mode; generate-prompt.sh never calls it with off):
#   auto    compile/pipeline.sh picks a tier: A serves a spec compiled from the
#           reviewed library (no LLM), B hands back a skeleton whose gaps a fast
#           model writes, C hands back repo facts for the full generation prompt
#   ground  never serve: always tier C (grounding + model tier)
#   compose / route are accepted as the v1 names of auto / ground.
#
# Exit 0: prompt on stdout. Exit 3: not served; <hints-out-file> may hold
# FAST_TIER, FAST_GAPFILL, FAST_GROUNDING and FAST_REASON lines. Every Jev
# failure is "not served", so the caller falls back to the unchanged LLM path.
# Settings arrive as $FAST_PATH_JSON (settings → fast_path), exported by load_settings.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE="${1:-}"
RAW_FILE="${2:-}"
PROJECT_DIR="${3:-}"
HINTS="${4:-}"
case "$MODE" in
  auto|compose) MODE=auto ;;
  ground|route) MODE=ground ;;
  *) echo "Usage: $0 auto|ground <raw-file> <project-dir> <hints-file>" >&2; exit 1 ;;
esac
if [ -z "$RAW_FILE" ] || [ ! -f "$RAW_FILE" ] || [ -z "$HINTS" ]; then
  echo "Usage: $0 $MODE <raw-file> <project-dir> <hints-file>" >&2
  exit 1
fi
[ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ] || PROJECT_DIR="$(pwd)"
: >"$HINTS"

FP_JSON="${FAST_PATH_JSON:-}"
[ -n "$FP_JSON" ] || FP_JSON='{}'
if [ "$MODE" = "ground" ]; then
  FP_JSON=$(jq -c '.tiers = ((.tiers // {}) + {a: false, b: false})' <<<"$FP_JSON" 2>/dev/null || echo '{"tiers":{"a":false,"b":false}}')
fi

rc=0
FAST_PATH_JSON="$FP_JSON" bash "$SCRIPT_DIR/compile/pipeline.sh" "$PROJECT_DIR" "$RAW_FILE" "$HINTS" || rc=$?
case "$rc" in
  0) exit 0 ;;
  2) echo "fast-path: jev unavailable or failed; using the LLM path" >&2; : >"$HINTS"; exit 3 ;;
  *) exit 3 ;;
esac
