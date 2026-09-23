#!/usr/bin/env bash
# scripts/fast-path.sh
# EXPERIMENTAL Jev fast path, called by generate-prompt.sh before the LLM path.
#
# Usage:
#   bash scripts/fast-path.sh <mode> <raw-request-file> <context-file|""> <hints-out-file>
#
# mode: route | compose | auto (generate-prompt.sh never calls it with off).
#   compose  one Jev decision call → if every gate passes, a template-composed
#            prompt (no LLM), checked by validate-prompt.sh and a Jev judge call
#   route    one Jev decision call → hints for the LLM path: model tier + reference pruning
#   auto     compose when the gates pass, otherwise route
# An input that is already an execution-ready spec (and validates) is passed through.
#
# Exit 0: prompt on stdout — the fast path served the request.
# Exit 3: not served; <hints-out-file> may hold KEY=value lines (FAST_TIER, FAST_PRUNE).
# Every Jev failure is "not served": the caller falls back to the unchanged LLM path.
# Thresholds come from $FAST_PATH_JSON (settings → fast_path), exported by load_settings.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE="${1:-}"
RAW_FILE="${2:-}"
CTX_FILE="${3:-}"
HINTS="${4:-}"
case "$MODE" in
  route|compose|auto) ;;
  *) echo "Usage: $0 route|compose|auto <raw-file> <context-file> <hints-file>" >&2; exit 1 ;;
esac
if [ -z "$RAW_FILE" ] || [ ! -f "$RAW_FILE" ] || [ -z "$HINTS" ]; then
  echo "Usage: $0 $MODE <raw-file> <context-file> <hints-file>" >&2
  exit 1
fi
: >"$HINTS"

FP_JSON="${FAST_PATH_JSON:-}"
[ -n "$FP_JSON" ] || FP_JSON='{}'
_thr() { jq -r --arg k "$1" --arg d "$2" '.thresholds[$k] // ($d | tonumber)' <<<"$FP_JSON" 2>/dev/null || echo "$2"; }

DEC=$(mktemp -t pi-fp-dec.XXXXXX)
JUD=$(mktemp -t pi-fp-jud.XXXXXX)
CMP=$(mktemp -t pi-fp-cmp.XXXXXX)
trap 'rm -f "$DEC" "$JUD" "$CMP"' EXIT

log() { echo "fast-path: $*" >&2; }

if ! bash "$SCRIPT_DIR/jev-decide.sh" decide "$RAW_FILE" "$CTX_FILE" >"$DEC" 2>/dev/null; then
  log "jev unavailable or failed — using the LLM path"
  exit 3
fi

_a() { jq -r "$1 // empty" "$DEC" 2>/dev/null || true; }
# Numeric comparison helpers (awk handles floats; missing values fail closed).
_le() { [ -n "$1" ] && awk -v a="$1" -v b="$2" 'BEGIN { exit !(a <= b) }'; }
_ge() { [ -n "$1" ] && awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'; }

JEV_MS=$(_a '.ms')
TRIAGE=$(_a '.answers.triage.choice')
TRIAGE_CONF=$(_a '.answers.triage.confidence')
ARCH=$(_a '.answers.archetype.choice')
ARCH_CONF=$(_a '.answers.archetype.confidence')
COMPLEXITY=$(_a '.answers.complexity.score')
RISK=$(_a '.answers.risk.score')
MULTI=$(_a '.answers.multi_task.noul')
VAGUE=$(_a '.answers.vague.noul')
log "jev decide ${JEV_MS:-?}ms — triage=${TRIAGE:-?} archetype=${ARCH:-?}(${ARCH_CONF:-?}) complexity=${COMPLEXITY:-?} risk=${RISK:-?} multi=${MULTI:-?} vague=${VAGUE:-?}"

# S1: already an execution-ready spec → pass it through unchanged.
if [ "$TRIAGE" = "ready" ] && _ge "$TRIAGE_CONF" "$(_thr ready_confidence 0.8)" \
  && bash "$SCRIPT_DIR/validate-prompt.sh" "$RAW_FILE" >/dev/null 2>&1; then
  log "passthrough (input is already an execution-ready spec)"
  cat "$RAW_FILE"
  exit 0
fi

# S3 + S4: compose from templates when every gate passes, then judge.
if [ "$MODE" = "compose" ] || [ "$MODE" = "auto" ]; then
  reason=""
  _ge "$ARCH_CONF" "$(_thr archetype_confidence 0.6)" || reason="archetype confidence ${ARCH_CONF:-none}"
  [ -z "$reason" ] && { _le "$COMPLEXITY" "$(_thr max_complexity 1.0)" || reason="complexity ${COMPLEXITY:-none}"; }
  [ -z "$reason" ] && { _le "$RISK" "$(_thr max_risk 0.5)" || reason="risk ${RISK:-none}"; }
  [ -z "$reason" ] && { _le "$MULTI" "$(_thr max_multi_task 0.25)" || reason="multi-task ${MULTI:-none}"; }
  [ -z "$reason" ] && { _le "$VAGUE" "$(_thr max_vague 0.3)" || reason="vague ${VAGUE:-none}"; }

  if [ -z "$reason" ]; then
    if ! bash "$SCRIPT_DIR/fast-compose.sh" "$DEC" "$RAW_FILE" "$CTX_FILE" >"$CMP" 2>/dev/null; then
      reason="no template for archetype ${ARCH:-none}"
    elif ! bash "$SCRIPT_DIR/validate-prompt.sh" "$CMP" >/dev/null 2>&1; then
      reason="composed prompt failed validation"
    fi
  fi

  judged=""
  if [ -z "$reason" ] && [ "$(jq -r 'if .judge == false then "false" else "true" end' <<<"$FP_JSON" 2>/dev/null || echo true)" = "true" ]; then
    if bash "$SCRIPT_DIR/jev-decide.sh" judge "$RAW_FILE" "$CMP" >"$JUD" 2>/dev/null; then
      FAITHFUL=$(jq -r '.answers.faithful.noul // empty' "$JUD")
      FIT=$(jq -r '.answers.fit.score // empty' "$JUD")
      judged=" + judge $(jq -r '.ms' "$JUD")ms faithful=${FAITHFUL:-?} fit=${FIT:-?}"
      _ge "$FAITHFUL" "$(_thr min_faithful 0.7)" || reason="judge: faithful ${FAITHFUL:-none}"
      [ -z "$reason" ] && { _ge "$FIT" "$(_thr min_fit 1.5)" || reason="judge: fit ${FIT:-none}"; }
    else
      reason="judge call failed"
    fi
  fi

  if [ -z "$reason" ]; then
    log "compose (archetype $ARCH, jev ${JEV_MS}ms${judged})"
    cat "$CMP"
    exit 0
  fi
  log "compose declined — $reason${judged}"
fi

# S2: route hints for the LLM path.
if [ "$MODE" = "route" ] || [ "$MODE" = "auto" ]; then
  tier="high"
  if _le "$COMPLEXITY" 1.0 && _le "$RISK" 0.5 && _le "$MULTI" 0.5; then
    tier="low"
  fi
  prune=false
  if [ "$(jq -r 'if .route_prune_references == false then "false" else "true" end' <<<"$FP_JSON" 2>/dev/null || echo true)" = "true" ] \
    && _le "$COMPLEXITY" 1.0 && _le "$MULTI" 0.5; then
    prune=true
  fi
  printf 'FAST_TIER=%s\nFAST_PRUNE=%s\n' "$tier" "$prune" >"$HINTS"
  log "route (tier $tier, prune references $prune)"
fi
exit 3
