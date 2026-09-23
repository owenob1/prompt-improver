#!/usr/bin/env bash
# scripts/compile/pipeline.sh
# Jev v2 fast path: the library is written offline (the "compile-time LLM");
# at request time Jev only decides, and the spec is compiled from reviewed items.
#
# Usage: bash pipeline.sh <repo-root> <request-file> <hints-out-file>
#
# Exit 0  a spec on stdout: Tier A (compiled, no LLM), or the request itself when
#         it is already an execution-ready spec that validates.
# Exit 3  not served; <hints-out-file> gets KEY=value lines for generate-prompt.sh:
#           FAST_TIER=low|high      model tier for the LLM call
#           FAST_GAPFILL=<file>     Tier B: skeleton + gaps (compile/gapfill.sh writes only the gaps)
#           FAST_GROUNDING=<file>   Tier C: repo facts Jev selected, added to the generation prompt
#           FAST_REASON=<text>
# Exit 2  Jev unavailable or failed: the caller runs the unchanged LLM path.
#
# Layers (docs/investigations/jev-v2-architecture.md):
#   L0 candidates.sh (+ target.sh)  deterministic, cached per repository state
#   L1 one wide call (request only) ∥ prior call (repo only, cached) ∥ L1b (request + target)
#   L2/L3 compile.jq                guarded items, slots from verbatim candidates, coverage
#   L4 tier                         A serve · B gap-fill · C grounded LLM
#   L5 every Jev answer is cached by a hash of its request JSON (deterministic replay)
#
# Env: FAST_PATH_JSON (settings.fast_path), PROMPT_IMPROVER_FAST_TRACE_DIR (keep the
#      working files there), PROMPT_IMPROVER_CACHE_DIR, PROMPT_IMPROVER_JEV_MODEL.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../lib/jev.sh
source "$HERE/../lib/jev.sh"

ROOT="${1:-}"
REQ_FILE="${2:-}"
HINTS="${3:-}"
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ] || [ -z "$REQ_FILE" ] || [ ! -f "$REQ_FILE" ] || [ -z "$HINTS" ]; then
  echo "Usage: $0 <repo-root> <request-file> <hints-out-file>" >&2
  exit 1
fi
: >"$HINTS"

log() { echo "fast-path: $*" >&2; }

if ! pi_jev_available; then
  log "jev unavailable (needs curl, jq and TYPESAFE_API_KEY or OPENROUTER_API_KEY)"
  exit 2
fi

CFG="${FAST_PATH_JSON:-}"
[ -n "$CFG" ] || CFG='{}'
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$CFG" || CFG='{}'
_cfg() { jq -r --arg k "$1" --arg d "$2" 'getpath($k | split(".")) as $v | if $v == null then $d else $v end' <<<"$CFG" 2>/dev/null || echo "$2"; }

LIB_DIR="${PROMPT_IMPROVER_LIBRARY_DIR:-$SKILL_DIR/assets/library}"
QUESTIONS="$LIB_DIR/_questions.json"
export PROMPT_IMPROVER_JEV_MODEL="${PROMPT_IMPROVER_JEV_MODEL:-$(_cfg jev_model jev-1.13.0)}"
export PROMPT_IMPROVER_JEV_TIMEOUT_MS="${PROMPT_IMPROVER_JEV_TIMEOUT_MS:-$(_cfg timeout_ms 4000)}"
MODEL=$(pi_jev_model)
CACHE_BASE="${PROMPT_IMPROVER_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/prompt-improver}"
USE_CACHE=$(_cfg cache true)

# Thresholds (all overridable under fast_path.thresholds).
T_JSON=$(jq -c '{
    margin: (.guard_margin // 0.05),
    allow_unreviewed: (if .allow_unreviewed == null then false else .allow_unreviewed end),
    cell_min: (.thresholds.cell_min // 0.5),
    slot_min: (.thresholds.slot_min // 0.5),
    rule_min: (.thresholds.rule_min // 0.75),
    rule_max: (.thresholds.rule_max // 6),
    rule_floor: (.thresholds.rule_floor // 0.45),
    command_min: (.thresholds.command_min // 0.6),
    test_min: (.thresholds.test_min // 0.5),
    target_min: (.thresholds.target_min // 0.6),
    target_margin: (.thresholds.target_margin // 0.15),
    ready_min: (.thresholds.ready_min // 0.8),
    max_multi_task: (.thresholds.max_multi_task // 0.35),
    min_clarity: (.thresholds.min_clarity // 1.2),
    max_risk: (.thresholds.max_risk // 1.2),
    max_complexity: (.thresholds.max_complexity // 2.2),
    low_tier_complexity: (.thresholds.low_tier_complexity // 1.0),
    low_tier_risk: (.thresholds.low_tier_risk // 0.5)
  }' <<<"$CFG")
_t() { jq -r --arg k "$1" '.[$k]' <<<"$T_JSON"; }

W=$(mktemp -d -t pi-v2.XXXXXX)
_cleanup() {
  if [ -n "${PROMPT_IMPROVER_FAST_TRACE_DIR:-}" ]; then
    mkdir -p "$PROMPT_IMPROVER_FAST_TRACE_DIR" 2>/dev/null && cp -R "$W"/. "$PROMPT_IMPROVER_FAST_TRACE_DIR"/ 2>/dev/null || true
  fi
  rm -rf "$W"
}
trap _cleanup EXIT

_now_ms() {
  local t
  t=$(date +%s%N 2>/dev/null || true)
  case "$t" in
    *N|'') echo $(( $(date +%s) * 1000 )) ;;
    *) echo $(( t / 1000000 )) ;;
  esac
}
_hash() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{ print substr($1, 1, 40) }'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{ print substr($1, 1, 40) }'
  else cksum | awk '{ print $1 "-" $2 }'
  fi
}

# Jev call through the answer cache. Writes <out>; <out>.meta = "cache" or the round trip in ms.
_jev() {
  local req="$1" out="$2" key f s
  key=$(_hash <"$req")
  f="$CACHE_BASE/jev/$key.json"
  if [ "$USE_CACHE" = true ] && [ -s "$f" ]; then
    cp "$f" "$out"
    echo "cache" >"$out.meta"
    return 0
  fi
  s=$(_now_ms)
  pi_jev_call "$req" "$out" || return 1
  echo "$(( $(_now_ms) - s ))ms" >"$out.meta"
  if [ "$USE_CACHE" = true ] && mkdir -p "$CACHE_BASE/jev" 2>/dev/null; then
    cp "$out" "$f.$$" 2>/dev/null && mv -f "$f.$$" "$f" 2>/dev/null || rm -f "$f.$$"
  fi
}

START=$(_now_ms)

# ---------------------------------------------------------------- L0
cp "$REQ_FILE" "$W/request.txt"
if ! bash "$HERE/candidates.sh" "$ROOT" "$REQ_FILE" >"$W/cands.json" 2>"$W/cands.err"; then
  log "candidates failed: $(tail -n 1 "$W/cands.err" 2>/dev/null)"
  exit 2
fi
REPO=$(cd "$ROOT" && git rev-parse --show-toplevel 2>/dev/null || (cd "$ROOT" && pwd))

# Library: every cell file (names starting with _ are engine data).
_cells=""
for f in "$LIB_DIR"/*.json; do
  [ -f "$f" ] || continue
  case "${f##*/}" in _*) continue ;; esac
  _cells="$_cells$f"$'\n'
done
if [ -n "$_cells" ]; then
  printf '%s' "$_cells" | tr '\n' '\0' | xargs -0 jq -s '.' >"$W/lib.json"
else
  echo '[]' >"$W/lib.json"
fi
NCELLS=$(jq 'length' "$W/lib.json")

# Target resolved without Jev: every file entity that resolves at all resolves to the same one path.
SPEC_TARGET=$(jq -r '[.entities[] | select((.kind == "file" or .kind == "code" or .kind == "path") and ((.paths // []) | length) == 1) | .paths[0]] | unique
                     | if length == 1 then .[0] else empty end' "$W/cands.json")
L0_MS=$(( $(_now_ms) - START ))

# ---------------------------------------------------------------- L1 ∥ prior ∥ L1b
jq -n --slurpfile c "$W/cands.json" --slurpfile lib "$W/lib.json" --slurpfile q "$QUESTIONS" \
  --arg model "$MODEL" -f "$HERE/l1.jq" >"$W/l1.req.json"
jq -n --slurpfile c "$W/cands.json" --slurpfile q "$QUESTIONS" --arg model "$MODEL" -f "$HERE/prior.jq" >"$W/prior.req.json"

_l1b_build() {  # [target-path]; with no path the guards are asked about the request alone
  if [ -n "${1:-}" ]; then
    bash "$HERE/target.sh" "$REPO" "$1" >"$W/target.json" 2>"$W/target.err" || return 1
  else
    jq -n --slurpfile q "$QUESTIONS" '{path: $q[0].no_target, name: "", stem: "", summary: "", usage: "", lines: [], refs: [], callers: [], none: true}' >"$W/target.json"
  fi
  jq -n --slurpfile c "$W/cands.json" --slurpfile lib "$W/lib.json" --slurpfile q "$QUESTIONS" \
    --slurpfile t "$W/target.json" --argjson cells "$(jq -c '[range(0; length)]' "$W/lib.json")" \
    --arg model "$MODEL" -f "$HERE/l1b.jq" >"$W/l1b.req.json"
}

_jev "$W/l1.req.json" "$W/l1.json" & P_L1=$!
_jev "$W/prior.req.json" "$W/prior.json" & P_PRIOR=$!
P_L1B=""
TARGET=""
if [ -n "$SPEC_TARGET" ] && _l1b_build "$SPEC_TARGET"; then
  TARGET="$SPEC_TARGET"
  _jev "$W/l1b.req.json" "$W/l1b.json" & P_L1B=$!
fi

rc=0; wait "$P_L1" || rc=$?
if [ "$rc" -ne 0 ]; then
  log "jev L1 call failed; using the LLM path"
  exit 2
fi
rc=0; wait "$P_PRIOR" || rc=$?
[ "$rc" -eq 0 ] || echo '{"answers":{}}' >"$W/prior.json"

# Jev's file relevance: the clear favourite, if any, and the score of the L0 target.
read -r REL_TOP REL_TARGET_P <<<"$(jq -r --slurpfile c "$W/cands.json" --arg cur "$TARGET" \
  --argjson tmin "$(_t target_min)" --argjson tmar "$(_t target_margin)" '
  [.answers | to_entries[] | select(.key | startswith("file_")) | {path: $c[0].files[(.key | ltrimstr("file_") | tonumber)].path, p: .value.noul}]
  | sort_by(-.p) as $r
  | (if ($r | length) > 0 and $r[0].p >= $tmin and ($r[0].p - (($r[1].p) // 0)) >= $tmar then $r[0].path else "-" end) as $top
  | ([$r[] | select(.path == $cur) | .p] | first // 0) as $curp
  | "\($top) \($curp)"' "$W/l1.json" 2>/dev/null || echo "- 0")"

# The L0 target is only a guess from the request's file names ("the broken link
# to docs/X.md in the README" names both); Jev's relevance overrides a clear miss.
if [ -n "$TARGET" ] && [ "$REL_TOP" != "-" ] && [ "$REL_TOP" != "$TARGET" ] \
  && awk -v a="$REL_TARGET_P" -v m="$(_t target_margin)" 'BEGIN { exit !(a < 0.5 - m) }'; then
  rc=0; wait "$P_L1B" || rc=$?
  log "target corrected by relevance: $TARGET -> $REL_TOP"
  TARGET="$REL_TOP"
  _l1b_build "$TARGET" || { TARGET=""; _l1b_build ""; }
  _jev "$W/l1b.req.json" "$W/l1b.json" & P_L1B=$!
fi

# Target from relevance when L0 could not resolve it.
if [ -z "$TARGET" ]; then
  [ "$REL_TOP" != "-" ] && TARGET="$REL_TOP"
  [ -n "$TARGET" ] && _l1b_build "$TARGET" || { TARGET=""; _l1b_build ""; }
  _jev "$W/l1b.req.json" "$W/l1b.json" & P_L1B=$!
fi
rc=0; wait "$P_L1B" || rc=$?
[ "$rc" -eq 0 ] || { echo '{"answers":{}}' >"$W/l1b.json"; log "jev L1b call failed; guards will fail closed"; }
# The stub target used for request-only guards is not a real file.
if [ -z "$TARGET" ]; then mv "$W/target.json" "$W/target.l1b.json"; echo '{}' >"$W/target.json"; fi
JEV_MS=$(( $(_now_ms) - START - L0_MS ))

jq -n --slurpfile c "$W/cands.json" --slurpfile lib "$W/lib.json" --slurpfile a1 "$W/l1.json" \
  --slurpfile ap "$W/prior.json" --slurpfile ab "$W/l1b.json" --slurpfile t "$W/target.json" \
  --argjson cfg "$T_JSON" -f "$HERE/understand.jq" >"$W/understanding.json"

_u() { jq -r "$1 // empty" "$W/understanding.json" 2>/dev/null || true; }
_le() { [ -n "$1" ] && awk -v a="$1" -v b="$2" 'BEGIN { exit !(a <= b) }'; }
_ge() { [ -n "$1" ] && awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'; }

# A cell may name the slot that locates its target (tests.add: the code under
# test, not the test file). The target is then the file defining that entity.
_TF=$(jq -r --argjson ci "$(_u '.cell.index // -1')" 'if $ci >= 0 then (.[$ci].target_from // empty) else empty end' "$W/lib.json" 2>/dev/null || true)
if [ -n "$_TF" ]; then
  _NT=$(jq -r --arg s "$_TF" --slurpfile c "$W/cands.json" -f "$HERE/target-from.jq" "$W/understanding.json" 2>"$W/target-from.err" || true)
  if [ -n "$_NT" ] && [ "$_NT" != "$TARGET" ] && [ -f "$REPO/$_NT" ] && _l1b_build "$_NT"; then
    log "target from slot $_TF: $_NT"
    TARGET="$_NT"
    if _jev "$W/l1b.req.json" "$W/l1b.json"; then
      jq -n --slurpfile c "$W/cands.json" --slurpfile lib "$W/lib.json" --slurpfile a1 "$W/l1.json" \
        --slurpfile ap "$W/prior.json" --slurpfile ab "$W/l1b.json" --slurpfile t "$W/target.json" \
        --argjson cfg "$T_JSON" -f "$HERE/understand.jq" >"$W/understanding.json"
    else
      echo '{"answers":{}}' >"$W/l1b.json"
    fi
  fi
fi

TRIAGE=$(_u '.core.triage.choice'); TRIAGE_P=$(_u '.core.triage.p')
MULTI=$(_u '.core.multi_task'); CLARITY=$(_u '.core.clarity'); RISK=$(_u '.core.risk'); CPLX=$(_u '.core.complexity')
CELL_ID=$(_u '.cell.id'); CELL_I=$(_u '.cell.index'); FIT_OK=$(_u '.cell.fit_ok'); REVIEWED=$(_u '.cell.reviewed')
_src() { local m; m=$(cat "$1.meta" 2>/dev/null || echo "-"); echo "$m"; }
log "jev L1 $(_src "$W/l1.json"), prior $(_src "$W/prior.json"), L1b $( [ -n "$P_L1B" ] && _src "$W/l1b.json" || echo none) — triage=${TRIAGE:-?} cell=${CELL_ID:-none} fit=${FIT_OK:-?} target=${TARGET:-none} multi=${MULTI:-?} clarity=${CLARITY:-?} risk=${RISK:-?} complexity=${CPLX:-?}"

TIER_MODEL=high
if _le "$CPLX" "$(_t low_tier_complexity)" && _le "$RISK" "$(_t low_tier_risk)" && _le "$MULTI" 0.5; then
  TIER_MODEL=low
fi

# Ready specs pass through untouched.
if [ "$(_cfg tiers.a true)" = true ] && [ "$TRIAGE" = "ready" ] && _ge "$TRIAGE_P" "$(_t ready_min)" \
  && bash "$SKILL_DIR/scripts/validate-prompt.sh" "$REQ_FILE" >/dev/null 2>&1; then
  log "passthrough: the request is already an execution-ready spec ($(( $(_now_ms) - START ))ms)"
  cat "$REQ_FILE"
  exit 0
fi

REASON=""
GATES_OK=true
_le "$MULTI" "$(_t max_multi_task)" || { GATES_OK=false; REASON="multi-part request (${MULTI:-?})"; }
[ "$GATES_OK" = true ] && { _ge "$CLARITY" "$(_t min_clarity)" || { GATES_OK=false; REASON="unclear request (clarity ${CLARITY:-?})"; }; }
[ "$GATES_OK" = true ] && { _le "$RISK" "$(_t max_risk)" || { GATES_OK=false; REASON="high risk (${RISK:-?})"; }; }
[ "$GATES_OK" = true ] && { _le "$CPLX" "$(_t max_complexity)" || { GATES_OK=false; REASON="high complexity (${CPLX:-?})"; }; }

COMPILED=false
if [ -n "$CELL_I" ] && [ "$FIT_OK" = "true" ]; then
  : >"$W/target-source.txt"
  if [ -n "$TARGET" ] && [ -f "$REPO/$TARGET" ]; then
    awk 'NR <= 20000' "$REPO/$TARGET" >"$W/target-source.txt" 2>/dev/null || true
  fi
  if jq -n --slurpfile c "$W/cands.json" --slurpfile lib "$W/lib.json" --slurpfile u "$W/understanding.json" \
      --slurpfile ab "$W/l1b.json" --slurpfile t "$W/target.json" --rawfile src "$W/target-source.txt" \
      --argjson ci "$CELL_I" --argjson cfg "$T_JSON" -f "$HERE/compile.jq" >"$W/compiled.json" 2>"$W/compile.err"; then
    COMPILED=true
    jq -r '.xml' "$W/compiled.json" >"$W/spec.xml"
  else
    log "compile failed: $(tail -n 1 "$W/compile.err")"
  fi
elif [ -n "$CELL_ID" ]; then
  REASON="${REASON:-cell $CELL_ID did not fit}"
else
  REASON="${REASON:-no library cell matches}"
fi

# Tier B only completes a cell that fits: the description and desired behaviour
# must be compiled, and at most two required sections may be left to the LLM.
FILL_OK='[.gaps[] | select(.mode == "fill")] | (map(.section) | (index("description") == null and index("desired") == null)) and length <= 2'
TIER=C
if [ "$COMPILED" = true ]; then
  C_OK=$(jq -r '.ok' "$W/compiled.json")
  NGAPS=$(jq -r '.gaps | length' "$W/compiled.json")
  STATS=$(jq -r '.stats | "\(.emitted)/\(.items) items, \(.dropped) dropped by guards or slots"' "$W/compiled.json")
  VALID=false; WARNS=0
  if bash "$SKILL_DIR/scripts/validate-prompt.sh" "$W/spec.xml" >"$W/validate.out" 2>&1; then
    VALID=true
    WARNS=$(grep -c 'WARN' "$W/validate.out" || true)
  fi
  if [ "$C_OK" != true ]; then
    REASON="${REASON:-cell $CELL_ID $(jq -r '.reason' "$W/compiled.json")}"
  elif [ "$REVIEWED" != true ] && [ "$(_t allow_unreviewed)" != true ]; then
    REASON="${REASON:-cell $CELL_ID is not reviewed (fast_path.allow_unreviewed=false)}"
  elif [ "$GATES_OK" != true ]; then
    :
  elif [ "$NGAPS" -eq 0 ] && [ "$VALID" = true ] && [ "$(_cfg tiers.a true)" = true ]; then
    TIER=A
  elif [ "$NGAPS" -gt 0 ] && [ "$(_cfg tiers.b true)" = true ] && [ "$(jq -r "$FILL_OK" "$W/compiled.json")" = true ]; then
    TIER=B
  elif [ "$NGAPS" -gt 0 ]; then
    REASON="${REASON:-cell $CELL_ID leaves too much unfilled ($(jq -r '[.gaps[] | select(.mode == "fill") | .section] | join(", ")' "$W/compiled.json"))}"
  else
    REASON="${REASON:-compiled spec failed validation}"
  fi
  log "compiled $CELL_ID: $STATS; gaps=$NGAPS valid=$VALID warnings=$WARNS"
fi

TOTAL_MS=$(( $(_now_ms) - START ))
jq -n --arg tier "$TIER" --arg reason "$REASON" --arg target "$TARGET" --arg cell "${CELL_ID:-}" \
  --argjson l0 "$L0_MS" --argjson jev "$JEV_MS" --argjson total "$TOTAL_MS" --arg model_tier "$TIER_MODEL" \
  '{tier: $tier, reason: $reason, target: $target, cell: $cell, model_tier: $model_tier, ms: {l0: $l0, jev: $jev, total: $total}}' >"$W/decision.json"

case "$TIER" in
  A)
    log "tier A: compiled from $CELL_ID in ${TOTAL_MS}ms (L0 ${L0_MS}ms, Jev ${JEV_MS}ms)"
    cat "$W/spec.xml"
    exit 0
    ;;
  B)
    GF=$(mktemp -t pi-gapfill.XXXXXX)
    jq --slurpfile t "$W/target.json" --slurpfile u "$W/understanding.json" --rawfile req "$W/request.txt" \
      --arg repo "$REPO" '{skeleton: .xml, gaps: .gaps, target: ($t[0] // {}), rules: ($u[0].rules // []), request: $req, repo: $repo}' \
      "$W/compiled.json" >"$GF"
    printf 'FAST_TIER=low\nFAST_GAPFILL=%s\nFAST_REASON=%s\n' "$GF" "gaps: $(jq -r '[.gaps[] | .section] | join(", ")' "$W/compiled.json")" >"$HINTS"
    log "tier B: compiled from $CELL_ID, an LLM writes only $(jq -r '[.gaps[] | "\(.section) (\(.mode))"] | join(", ")' "$W/compiled.json") (${TOTAL_MS}ms so far)"
    exit 3
    ;;
esac

# Tier C: grounding block for the full LLM path.
GR=$(mktemp -t pi-grounding.XXXXXX)
if jq -n -r --slurpfile c "$W/cands.json" --slurpfile u "$W/understanding.json" --slurpfile t "$W/target.json" \
    --slurpfile lib "$W/lib.json" --slurpfile cmp "$( [ "$COMPILED" = true ] && echo "$W/compiled.json" || echo /dev/null)" \
    -f "$HERE/ground.jq" >"$GR" 2>"$W/ground.err" && [ -s "$GR" ]; then
  printf 'FAST_TIER=%s\nFAST_GROUNDING=%s\nFAST_REASON=%s\n' "$TIER_MODEL" "$GR" "${REASON:-not served}" >"$HINTS"
else
  rm -f "$GR"
  printf 'FAST_TIER=%s\nFAST_REASON=%s\n' "$TIER_MODEL" "${REASON:-not served}" >"$HINTS"
fi
log "tier C: ${REASON:-not served}; LLM ($TIER_MODEL tier) with Jev grounding (${TOTAL_MS}ms)"
exit 3
