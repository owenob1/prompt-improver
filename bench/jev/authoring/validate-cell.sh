#!/usr/bin/env bash
# bench/jev/authoring/validate-cell.sh <cell.json>
# Structural checks for one library cell, then two dry compiles (every Jev guard
# answered 0.99, then 0.01) through the real compiler, with the fully-applicable
# variant checked by validate-prompt.sh. Exit 0 when the cell is usable.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$HERE/../../../skills/prompt-improver"
CELL="${1:?usage: validate-cell.sh <cell.json>}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

jq -e . "$CELL" >/dev/null || { echo "FAIL: not JSON"; exit 1; }
problems=$(jq -r '
  ["target_path","target_name","target_stem","target_summary","tool_path","tool_name","runner","tool_summary","syntax_check",
   "test_file","test_cmd","typecheck_cmd","lint_cmd","build_cmd","changelog","project","callers"] as $builtin
  | ["description","current","desired","approach","example","verification","companion","constraint","out_of_scope","escape","check"] as $secs
  | ["file","path","code","identifier","env","flag","quoted","version","quantity","number","url","word"] as $kinds
  | ["target","new_element","desired","symptom","constraint","metric"] as $roles
  | . as $c | ($c.slots // {} | keys) as $slots
  | (if ($c.id // "") == "" then "missing id" else empty end),
    (if ($c.match // "") == "" then "missing match" else empty end),
    (if ($c.fit // []) | length < 1 then "no fit questions" else empty end),
    (($c.slots // {}) | to_entries[] | .key as $n | .value
      | if .kind == "entity" then ((.accept // [])[] | select(. as $k | $kinds | index([$k]) | not) | "slot \($n): unknown kind \(.)"), (if (.q // "") == "" then "slot \($n): entity slot needs q" else empty end)
        elif .kind == "role" then (.role as $r | if ($roles | index([$r])) then empty else "slot \($n): unknown role \($r)" end)
        elif .kind == "word" or .kind == "span" then (if (.q // "") == "" then "slot \($n): needs q" else empty end)
        else "slot \($n): unknown kind \(.kind)" end),
    ([$c.items[] | .id] | group_by(.) | map(select(length > 1) | "duplicate item id \(.[0])") | .[]),
    ([$c.items[] | (.guards // [])[], ($c.requires // [])[], ($c.escalate // [])[]] | map(select(.q)) | group_by(.id)
      | map(select((map(.q) | unique | length) > 1) | "guard \(.[0].id) has different questions") | .[]),
    ($c.items[] | . as $it
      | (if ($it.section | startswith("requirements.")) or ($secs | index([$it.section])) then empty else "\($it.id): bad section \($it.section)" end),
        ([$it.text, $it.input, $it.output, $it.reasoning, $it.file] | map(select(. != null)) | join(" ")
          | [scan("\\{([a-z_]+)\\}") | .[0]] | .[] | select(. as $n | ($slots + $builtin) | index([$n]) | not) | "\($it.id): unknown slot {\(.)}"),
        (($it.guards // [])[] | select(.fact == null and ((.q // "") == "" or (.min == null and .max == null))) | "\($it.id): guard \(.id) needs q and min or max"),
        (($it.guards // [])[] | select(.fact != null and (.fact | IN("target_has", "target_lacks") | not)) | "\($it.id): unknown fact \(.fact)"),
        (if $it.section == "example" and ($it.input == null or $it.output == null or $it.reasoning == null) then "\($it.id): example needs input, output and reasoning" else empty end),
        (if $it.section != "example" and ($it.text // "") == "" then "\($it.id): needs text" else empty end),
        (if $it.section == "companion" and ($it.file // "") == "" then "\($it.id): companion needs file" else empty end),
        ([$it.text, $it.input, $it.output, $it.reasoning] | map(select(. != null)) | join(" ")
          | select(test("\\b(clean|robust|proper|properly|appropriate|appropriately|seamless|seamlessly|nice|efficient|efficiently)\\b"; "i"))
          | "\($it.id): vague adjective")),
    (($c.escalate // [])[] | select((.gap // "") == "") | "escalate \(.id): needs gap"),
    (($c.key_slots // [])[] | select(. as $k | $slots | index([$k]) | not) | "key_slots: \(.) is not a slot"),
    # Robustness: every required section has an unguarded item that needs only key slots.
    (($c.required // {}) | (if type == "array" then . else keys end)[] as $sec
      | ["target_path","target_name","target_stem","target_summary","project","runner","syntax_check"] as $always
      | select([$c.items[] | select(.section == $sec or (.section | startswith($sec + ".")))
                | select((.guards // []) | length == 0)
                | [(.text // ""), (.input // ""), (.output // ""), (.reasoning // "")] | join(" ") | [scan("\\{([a-z_]+)\\}") | .[0]]
                | select(all(.[]; . as $n | (($c.key_slots // []) + $always) | index([$n])))] | length == 0)
      | "required section \($sec) has no unguarded item using only key slots"),
    (($c.required // {}) | if type == "array" then .[] else keys[] end | select(. as $s | ($secs + ["requirements"]) | index([$s]) | not) | "required: unknown section \(.)")
' "$CELL")
if [ -n "$problems" ]; then
  printf 'FAIL: %s\n' "$problems"
  exit 1
fi

# Dry compile through the real compiler.
jq -n '{request: "(dry run)", entities: [], spans: [], words: [], files: [], rules: [], commands: [], tests: ["tests/test_target.sh"], changelog: "CHANGELOG.md", project: "A project."}' >"$T/c.json"
jq '[.]' "$CELL" >"$T/lib.json"
jq -n '{path: "src/target.sh", name: "target.sh", stem: "target", ext: "sh", runner: "bash", syntax_check: "bash -n src/target.sh",
        summary: "does the thing", usage: "", options: [], lines: [], refs: [], callers: ["src/caller.sh"]}' >"$T/t.json"
printf 'placeholder source mentioning nothing\n' >"$T/src.txt"
for p in 0.99 0.01; do
  jq --arg ci 0 --argjson p "$p" '{answers: ([.[0] | (.items[] | .guards[]?), (.requires // [])[], (.escalate // [])[] | select(.q) | {key: "g_0_\(.id | ascii_downcase | gsub("[^a-z0-9_]"; "_"))", value: {type: "noul", noul: $p}}] | from_entries)}' "$T/lib.json" >"$T/ab.json"
  jq --slurpfile cell "$T/lib.json" '{core: {}, cell: {index: 0, id: $cell[0][0].id, fit_ok: true, reviewed: false},
       slots: ($cell[0][0].slots // {} | with_entries(.value = {value: ("<" + .key + ">"), p: 0.9})),
       roles: {}, files: [], rules: [], commands: {test: {cmd: "make test"}}, test_file: {path: "tests/test_target.sh", p: 1}}' -n >"$T/u.json"
  if ! jq -n --slurpfile c "$T/c.json" --slurpfile lib "$T/lib.json" --slurpfile u "$T/u.json" --slurpfile ab "$T/ab.json" \
      --slurpfile t "$T/t.json" --rawfile src "$T/src.txt" --argjson ci 0 --argjson cfg '{"margin":0.05}' \
      -f "$SKILL/scripts/compile/compile.jq" >"$T/out.$p.json" 2>"$T/err"; then
    echo "FAIL: compile error with guards at $p: $(head -c 300 "$T/err")"; exit 1
  fi
done
jq -r '.xml' "$T/out.0.99.json" >"$T/spec.xml"
gaps=$(jq -r '[.gaps[] | select(.mode == "fill") | .section] | join(",")' "$T/out.0.99.json")
if ! bash "$SKILL/scripts/validate-prompt.sh" "$T/spec.xml" >"$T/v.out" 2>&1; then
  echo "FAIL: dry compile (all guards 0.99) does not validate:"; grep -E 'FAIL' "$T/v.out" | head -5; exit 1
fi
printf 'OK %s: %s items, dry compile emits %s (0.99) / %s (0.01), fill gaps at 0.99: %s, warnings: %s\n' \
  "$(jq -r .id "$CELL")" "$(jq '.items | length' "$CELL")" \
  "$(jq '.stats.emitted' "$T/out.0.99.json")" "$(jq '.stats.emitted' "$T/out.0.01.json")" "${gaps:-none}" "$(grep -c WARN "$T/v.out" || true)"
