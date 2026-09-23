#!/usr/bin/env bash
# bench/jev/report.sh — markdown summary of runs.jsonl + judgements.jsonl.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${BENCH_OUT:-$HERE/results}"
RUNS="$OUT/runs.jsonl"
JUD="$OUT/judgements.jsonl"
[ -s "$RUNS" ] || { echo "no runs in $RUNS — run bench/jev/run.sh first" >&2; exit 1; }
[ -f "$JUD" ] || : >"$JUD"

jq -rs --slurpfile j "$JUD" '
  def pct(p): (sort | .[((length - 1) * p | floor)]);
  def fmt: if . == null then "–" elif . >= 1000 then "\((. / 100 | round) / 10)s" else "\(.)ms" end;
  (group_by(.mode) | map({
    mode: .[0].mode,
    n: length,
    p50: (map(.ms) | pct(0.5)),
    p95: (map(.ms) | pct(0.95)),
    fast: (map(select(.path == "compose" or .path == "passthrough")) | length),
    fast_p50: (map(select(.path == "compose" or .path == "passthrough") | .ms) | if length > 0 then pct(0.5) else null end),
    valid: (map(select(.valid)) | length),
    jev_p50: (map(.jev_ms | select(. != null)) | if length > 0 then pct(0.5) else null end),
    ids_fast: (map(select(.path == "compose" or .path == "passthrough") | .id))
  })) as $modes
  | ($j | map(select(.result != "error"))) as $judg
  | "| mode | n | p50 | p95 | served fast | fast p50 | Jev p50 | valid | win/tie/loss (all) | win/tie/loss (fast-served) |",
    "|---|---|---|---|---|---|---|---|---|---|",
    ($modes[] | . as $m
      | ($judg | map(select(.mode == $m.mode))) as $mj
      | ($mj | map(select(.id as $i | $m.ids_fast | index($i)))) as $fj
      | "| \($m.mode) | \($m.n) | \($m.p50 | fmt) | \($m.p95 | fmt) | \($m.fast) (\(($m.fast * 100 / $m.n) | floor)%) | \($m.fast_p50 | fmt) | \($m.jev_p50 | fmt) | \($m.valid)/\($m.n) | "
        + "\($mj | map(select(.result == "win")) | length)/\($mj | map(select(.result == "tie")) | length)/\($mj | map(select(.result == "loss")) | length) | "
        + "\($fj | map(select(.result == "win")) | length)/\($fj | map(select(.result == "tie")) | length)/\($fj | map(select(.result == "loss")) | length) |")
' "$RUNS"
echo
echo "Per-kind path choice (auto):"
jq -rs 'map(select(.mode == "auto")) | group_by(.kind) | map("- \(.[0].kind): " + (map(.path + (if .tier != "" then "/" + .tier else "" end)) | join(", "))) | .[]' "$RUNS"
