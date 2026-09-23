#!/usr/bin/env bash
# bench/jev/report.sh — markdown summary of runs.jsonl + judgements.jsonl.
# Paths: llm (mode off), A (compiled, no LLM), B (compiled + LLM gap-fill),
# B-fallback, C (grounded full generation), passthrough, bounce.
# Judgements are counted per order: each pair is judged candidate-first and
# baseline-first, so a request contributes two verdicts.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${BENCH_OUT:-$HERE/results}"
RUNS="$OUT/runs.jsonl"
JUD="$OUT/judgements.jsonl"
[ -s "$RUNS" ] || { echo "no runs in $RUNS — run bench/jev/run.sh first" >&2; exit 1; }
[ -f "$JUD" ] || : >"$JUD"

jq -rs --slurpfile j "$JUD" '
  def pct(p): if length == 0 then null else (sort | .[((length - 1) * p | floor)]) end;
  def fmt: if . == null then "-" elif . >= 1000 then "\((. / 100 | round) / 10)s" else "\(.)ms" end;
  def wtl($js): "\($js | map(select(.result == "win")) | length)/\($js | map(select(.result == "tie")) | length)/\($js | map(select(.result == "loss")) | length)";
  ($j | map(select(.result != "error"))) as $judg
  | "| mode | path | n | p50 | p95 | valid | win/tie/loss vs off (both orders) |",
    "|---|---|---|---|---|---|---|",
    (group_by(.mode)[] | . as $rows | .[0].mode as $mode
      | (["all"] + ($rows | map(.path) | unique))[] as $path
      | ($rows | map(select($path == "all" or .path == $path))) as $r
      | ($r | map(.id)) as $ids
      | ($judg | map(select(.mode == $mode and (.id as $i | $ids | index($i))))) as $jj
      | "| \($mode) | \($path) | \($r | length) | \($r | map(.ms) | pct(0.5) | fmt) | \($r | map(.ms) | pct(0.95) | fmt) | \($r | map(select(.valid)) | length)/\($r | length) | \(if $mode == "off" then "-" else wtl($jj) end) |")
' "$RUNS"
echo
echo "Path per request (auto):"
jq -rs 'map(select(.mode == "auto")) | sort_by(.id) | map("\(.id)=\(.path)") | join(" ")' "$RUNS"
