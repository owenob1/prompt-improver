#!/usr/bin/env bash
# bench/jev/authoring/calibrate.sh [library-dir]
# Runs every request in calibration.jsonl through the v2 pipeline (live Jev) and
# prints, per request: the node it should (or should not) match, the cell Jev
# chose, fit, tier, the items the guards dropped and the gaps. This is the
# reviewer's evidence that a cell's fit questions and guards discriminate.
#
#   CAL_IDS="c01 c02"   run a subset
#   CAL_OUT=<dir>       keep per-request traces (default: a temp dir)
# Needs TYPESAFE_API_KEY or OPENROUTER_API_KEY.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
LIB="${1:-$REPO/skills/prompt-improver/assets/library}"
OUT="${CAL_OUT:-$(mktemp -d)}"
mkdir -p "$OUT"
printf '%-4s %-24s %-5s %-24s %-5s %-5s %-5s %s\n' id expected fit? chosen p fit tier "dropped (guard) · gaps"
while IFS= read -r line; do
  id=$(jq -r .id <<<"$line")
  if [ -n "${CAL_IDS:-}" ]; then case " $CAL_IDS " in *" $id "*) ;; *) continue ;; esac; fi
  jq -r .request <<<"$line" >"$OUT/$id.req"
  rm -rf "$OUT/$id"
  rc=0
  PROMPT_IMPROVER_LIBRARY_DIR="$LIB" PROMPT_IMPROVER_FAST_TRACE_DIR="$OUT/$id" \
    FAST_PATH_JSON='{"allow_unreviewed":true}' \
    bash "$REPO/skills/prompt-improver/scripts/compile/pipeline.sh" "$REPO" "$OUT/$id.req" "$OUT/$id.hints" \
    >"$OUT/$id.xml" 2>"$OUT/$id.log" || rc=$?
  tier=$(sed -n 's/^fast-path: tier \([ABC]\).*/\1/p' "$OUT/$id.log" | tail -n 1)
  [ -n "$tier" ] || tier=$( [ "$rc" -eq 0 ] && echo pass || echo "rc$rc")
  u="$OUT/$id/understanding.json"
  chosen=$(jq -r '.cell.id // "none"' "$u" 2>/dev/null || echo "?")
  p=$(jq -r '.cell.p // 0 | . * 100 | round / 100' "$u" 2>/dev/null || echo "?")
  fit=$(jq -r 'if .cell.fit_ok then "yes" else "no" end' "$u" 2>/dev/null || echo "?")
  dropped=""
  if [ -f "$OUT/$id/compiled.json" ]; then
    dropped=$(jq -r '([.trace[] | select(.status == "dropped") | .reasons[] | select(startswith("guard:")) | ltrimstr("guard:")] | group_by(.) | map("\(.[0])×\(length)") | join(" "))
      + (if (.gaps | length) > 0 then " · gaps: " + ([.gaps[] | "\(.section)(\(.mode))"] | join(",")) else "" end)
      + (if .ok then "" else " · " + .reason end)' "$OUT/$id/compiled.json")
  fi
  printf '%-4s %-24s %-5s %-24s %-5s %-5s %-5s %s\n' "$id" "$(jq -r .node <<<"$line")" "$(jq -r .expect <<<"$line")" "$chosen" "$p" "$fit" "$tier" "$dropped"
done <"$HERE/calibration.jsonl"
echo "traces: $OUT" >&2
