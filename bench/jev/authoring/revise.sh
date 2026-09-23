#!/usr/bin/env bash
# bench/jev/authoring/revise.sh <cell.json> <calibration-trace-dir> [model]
# One revision round of the offline authoring loop: the model sees the cell, what
# validate-cell.sh says about it, and how its slots, guards and gaps behaved on
# the calibration requests it matched (calibrate.sh traces). It returns the whole
# revised cell. The evidence is about robustness, not content for those requests.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../../../skills/prompt-improver/assets/library"
CELL="${1:?usage: revise.sh <cell.json> <trace-dir> [model]}"
TRACES="${2:?usage: revise.sh <cell.json> <trace-dir> [model]}"
MODEL="${3:-opus}"
ID=$(jq -r .id "$CELL")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

bash "$HERE/validate-cell.sh" "$CELL" >"$T/validator.txt" 2>&1 || true

# Evidence: every calibration request this cell was chosen for.
: >"$T/evidence.txt"
for u in "$TRACES"/*/understanding.json; do
  d=$(dirname "$u")
  [ "$(jq -r '.cell.id // ""' "$u")" = "$ID" ] || continue
  {
    printf -- '- request: %s\n' "$(cat "$d/request.txt")"
    jq -r '"  fit: \(if .cell.fit_ok then "yes" else "no" end); slots: " + ((.slots // {}) | to_entries | map("\(.key)=\(if .value == null then "UNRESOLVED" else (.value.value | tostring) end)") | join(", "))' "$u"
    if [ -f "$d/compiled.json" ]; then
      jq -r '"  items emitted \(.stats.emitted)/\(.stats.items); dropped for unresolved slots: " + ([.trace[] | select(.status == "dropped") | .reasons[] | select(startswith("slot:")) | ltrimstr("slot:")] | group_by(.) | map("\(.[0])×\(length)") | join(", "))
        + "\n  gaps: " + ([.gaps[] | "\(.section) (\(.mode), \(.have)/\(.need))"] | join(", "))
        + "\n  uncertain guards (answer between the thresholds): " + ([.trace[] | .guards[]? | select(.p != null and .pass == false and .p > 0.35 and .p < 0.65) | "\(.id)=\(.p)"] | unique | join(", "))' "$d/compiled.json"
    fi
  } >>"$T/evidence.txt"
done

jq -rn --rawfile schema "$LIB/SCHEMA.md" --rawfile cell "$CELL" --rawfile val "$T/validator.txt" --rawfile ev "$T/evidence.txt" '
"You are revising one cell of a prompt-compilation library (schema below). The cell was written without seeing real requests; it has now been run on calibration requests about one repository. Revise it so it compiles a complete, correct specification for every request of its kind.",
"",
"<schema>", $schema, "</schema>",
"",
"<cell>", $cell, "</cell>",
"",
"<validator>", $val, "</validator>",
"",
"<calibration-evidence>", (if ($ev | length) > 0 then $ev else "(the cell was not chosen for any calibration request)\n" end), "</calibration-evidence>",
"",
"Revise the cell:",
"1. Add \"key_slots\": the few cell slots the cell cannot do without. If one of them does not resolve, the cell is not used for that request, so choose the minimum.",
"2. Role slots ({desired}, {symptom}, {constraint}, {metric}, {target}, {new_element}) often do not resolve; they must never be key slots. Every other slot is optional too.",
"3. Every required section needs at least one unguarded item that uses only key slots, {target_path}, {target_name}, {target_stem}, {target_summary}, {project}, {runner} and {syntax_check}. Keep the richer items that use optional slots as well; they are emitted when their slots resolve.",
"4. Where the evidence shows a slot that never resolves, rewrite its slot question so a request that states the value lets the value be chosen. If the value is rarely stated, stop depending on it.",
"5. Where a guard answered between its thresholds, sharpen its question so that it is a narrower fact.",
"6. Fix everything the validator reports.",
"7. The evidence describes how slots and guards behave; do not add content aimed at those particular requests. Keep the cell generic across projects and languages.",
"8. Keep the id, schema, provenance (reviewed_by stays null), match and the lessons the cell already follows: guards on judgement-dependent items, runnable verification with expected results, examples with reasoning, specific escapes, and a check that re-reads changed files.",
"",
"Reply with the complete revised cell as JSON only: no commentary and no code fences."
' >"$T/prompt.txt"

s=$(date +%s)
claude -p --tools "" --output-format text --no-session-persistence --permission-mode dontAsk --model "$MODEL" \
  <"$T/prompt.txt" >"$T/raw.txt" 2>"$T/err.txt" || { echo "$ID: $MODEL failed: $(tail -n 2 "$T/err.txt")" >&2; exit 2; }
awk 'BEGIN { RS = "\001" } { a = index($0, "{"); b = 0; for (i = length($0); i > 0; i--) if (substr($0, i, 1) == "}") { b = i; break }; if (a && b > a) print substr($0, a, b - a + 1) }' \
  "$T/raw.txt" >"$T/cell.json"
jq -e . "$T/cell.json" >/dev/null 2>&1 || { cp "$T/raw.txt" "$CELL.revise-raw.txt"; echo "$ID: revision is not JSON" >&2; exit 3; }
jq --arg id "$ID" '.id = $id | .provenance.reviewed_by = null' "$T/cell.json" >"$CELL"
echo "$ID: revised in $(( $(date +%s) - s ))s" >&2
bash "$HERE/validate-cell.sh" "$CELL"
