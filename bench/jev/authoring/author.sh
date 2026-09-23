#!/usr/bin/env bash
# bench/jev/authoring/author.sh <node-id> [model]
# The "compile-time LLM": a frontier model writes one library cell for a taxonomy
# node (nodes.json), from the schema, the calibrated example cell and the lessons
# in prompt.md. It never sees the benchmark corpus. The cell is written unreviewed
# (provenance.reviewed_by = null) and checked by validate-cell.sh.
#
#   AUTHOR_OUT=<dir>   where to write the cell (default: the skill's library)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../../../skills/prompt-improver/assets/library"
OUT_DIR="${AUTHOR_OUT:-$LIB}"
ID="${1:?usage: author.sh <node-id> [model]}"
MODEL="${2:-opus}"
node=$(jq -c --arg id "$ID" '.nodes[] | select(.id == $id)' "$HERE/nodes.json")
[ -n "$node" ] || { echo "unknown node $ID" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

jq -rn --rawfile tpl "$HERE/prompt.md" --rawfile schema "$LIB/SCHEMA.md" --rawfile example "$LIB/cli-flag.diagnostic.json" \
  --argjson node "$node" --arg date "$(date +%Y-%m-%d)" '
  $tpl | gsub("@@SCHEMA@@"; $schema) | gsub("@@EXAMPLE@@"; $example)
       | gsub("@@ID@@"; $node.id) | gsub("@@MATCH@@"; $node.match) | gsub("@@BOUNDARIES@@"; $node.boundaries)
       | gsub("@@DATE@@"; $date)' >"$T/prompt.txt"

s=$(date +%s)
claude -p --tools "" --output-format text --no-session-persistence --permission-mode dontAsk --model "$MODEL" \
  <"$T/prompt.txt" >"$T/raw.txt" 2>"$T/err.txt" || { echo "$ID: $MODEL failed: $(tail -n 2 "$T/err.txt")" >&2; exit 2; }
# Keep the outermost JSON object (tolerates stray fences or prose).
awk 'BEGIN { RS = "\001" } { a = index($0, "{"); n = split($0, _c, ""); b = 0; for (i = length($0); i > 0; i--) if (substr($0, i, 1) == "}") { b = i; break } ; if (a && b > a) print substr($0, a, b - a + 1) }' \
  "$T/raw.txt" >"$T/cell.json"
if ! jq -e . "$T/cell.json" >/dev/null 2>&1; then
  cp "$T/raw.txt" "$OUT_DIR/$ID.raw.txt"
  echo "$ID: output is not JSON (kept in $OUT_DIR/$ID.raw.txt)" >&2
  exit 3
fi
jq --arg id "$ID" '.id = $id | .provenance.reviewed_by = null' "$T/cell.json" >"$OUT_DIR/$ID.json"
echo "$ID: written in $(( $(date +%s) - s ))s" >&2
bash "$HERE/validate-cell.sh" "$OUT_DIR/$ID.json"
