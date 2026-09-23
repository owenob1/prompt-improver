#!/usr/bin/env bash
# v2slots.sh "<request>" <outdir>  — one wide Jev call → slots.tsv + rules.txt (no hand input)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; P="$HERE"
REQ="$1"; OUT="$2"; mkdir -p "$OUT"
cd "$HERE/../../.."
# --- L0 candidates (deterministic) ---
bash "$HERE/cards.sh" . > "$OUT/cards.txt"
python3 "$HERE/rule_sentences.py" CLAUDE.md > "$OUT/rules_sent.txt"
spans=$(jq -rn --arg r "$REQ" '($r|gsub("[,:;]";" ")|split(" ")|map(select(length>0))) as $w
  | [range(0;$w|length) as $i | range(1;13) as $l | select($i+$l <= ($w|length)) | $w[$i:$i+$l]|join(" ")] | unique | .[0:254] | .[]' | jq -R . | jq -s .)
words=$(tr ' ' '\n' <<<"$REQ" | tr -d ',.;:' | awk 'length>2' | sort -u | jq -R . | jq -s .)
tests=$( { git ls-files | grep -iE 'test|spec' | grep -vE '\.md$|corpus' || true; } | jq -R . | jq -s .)
cmds=$( { grep -E '^[[:space:]]+run: [a-z]' .github/workflows/ci.yml 2>/dev/null | sed 's/^ *run: //'; awk '/^```(bash|sh)/{f=1;next} /^```/{f=0} f' CLAUDE.md CONTRIBUTING.md README.md 2>/dev/null | sed 's/[[:space:]]*#.*$//' | awk 'NF && length<120'; } | grep -vE "^(\.\.\.|REQ|cd )" | sort -u | jq -R . | jq -s .)
cards=$(jq -R . < "$OUT/cards.txt" | jq -s 'map(select(length>0))')
rules=$(jq -R . < "$OUT/rules_sent.txt" | jq -s 'map(select(length>0))')
# --- L1 one wide call ---
jq -n --arg r "$REQ" --argjson sp "$spans" --argjson w "$words" --argjson t "$tests" --argjson k "$cmds" --argjson c "$cards" --argjson ru "$rules" '
 ({none:"Nothing in the request plays this role"} + ($sp|to_entries|map({key:"s\(.key)", value:.value})|from_entries)) as $crit
 | {model:"jev-latest", state:{request:$r},
   questions:({
     target:{type:"choice", instructions:"Which words name the existing file, component, command, function or system that must be changed?", criteria:$crit},
     new_element:{type:"choice", instructions:"Which words name the new thing to add (a flag, option, feature, file, endpoint or test)?", criteria:$crit},
     desired:{type:"choice", instructions:"Which words describe how things should behave once the work is done?", criteria:$crit},
     flag_kind:{type:"choice", instructions:"What kind of command-line flag does the request add?", criteria:{"diagnostic-output":"It makes the tool report extra diagnostic or progress information","behaviour-toggle":"It switches a behaviour on or off","output-format":"It changes the format of the normal output","value-option":"It takes a value that configures the tool","filter":"It narrows what the tool processes","dry-run":"It previews actions without performing them","force":"It skips confirmations or safety checks"}},
     sites:{type:"choice", instructions:"Which single word names the things the tool will report on?", criteria:($w|to_entries|map({key:"w\(.key)", value:.value})|from_entries)},
     test_file:{type:"choice", instructions:"Which file holds the automated tests that should cover this change?", criteria:($t|to_entries|map({key:"t\(.key)", value:.value})|from_entries)},
     test_cmd:{type:"choice", instructions:"Which command runs the full automated test suite?", criteria:($k|to_entries|map({key:"k\(.key)", value:.value})|from_entries)}}
     + ($c|to_entries|map({key:"f\(.key)", value:{type:"noul", instructions:("Would carrying out the request require editing this file? File: " + .value)}})|from_entries)
     + ($ru|to_entries|map({key:"u\(.key)", value:{type:"noul", instructions:("Would an engineer carrying out the request need to follow this project rule while changing the code? Rule: " + .value[0:500])}})|from_entries))}' > "$OUT/l1.json"
s=$(date +%s%N); "$HERE/jev" "$OUT/l1.json" > "$OUT/l1.out"; echo "L1 Jev call: $(( ($(date +%s%N)-s)/1000000 ))ms, $(jq '.answers|length' "$OUT/l1.out") questions" >&2
A() { jq -r "$1" "$OUT/l1.out"; }
pick() { local key="$1" arr="$2" pre="$3"; local ch; ch=$(A ".answers.$key.choice"); [ "$ch" = none ] && { echo ""; return; }; jq -r --argjson a "$arr" --arg c "${ch#$pre}" '$a[($c|tonumber)]' <<<"null"; }
target=$(pick target "$spans" s); new_el=$(pick new_element "$spans" s); desired=$(pick desired "$spans" s)
sites=$(pick sites "$words" w); test_file=$(pick test_file "$tests" t); test_cmd=$(pick test_cmd "$cmds" k)
tool_path=$(jq -r --argjson c "$cards" '[.answers|to_entries[]|select(.key|test("^f[0-9]+$"))|{i:(.key|ltrimstr("f")|tonumber),p:.value.noul}]|sort_by(-.p)|.[0].i as $i|$c[$i]|split(" — ")[0]' "$OUT/l1.out")
flag=$(grep -oE -- '--?[A-Za-z][A-Za-z0-9-]*' <<<"$new_el $REQ" | head -n 1)
tool=$(basename "$tool_path"); tool_name="${tool%.*}"
case "$tool" in *.sh) runner=bash; syntax="bash -n $tool_path";; *.py) runner=python3; syntax="python3 -m py_compile $tool_path";; *) runner=""; syntax="";; esac
summary=$(sed -n '2,12p' "$tool_path" | grep '^#' | sed 's/^# \{0,1\}//' | grep -vE "^(scripts/|$tool|$)" | head -2 | tr '\n' ' ' | sed 's/ *$//; s/\.$//' | awk '{print tolower(substr($0,1,1)) substr($0,2)}') || true
jq -r --argjson ru "$rules" '[.answers|to_entries[]|select(.key|test("^u[0-9]+$"))|{i:(.key|ltrimstr("u")|tonumber),p:.value.noul}]|sort_by(-.p)|map(select(.p>=0.53))|.[0:8][]|$ru[.i]' "$OUT/l1.out" | grep -vE '^(A pure-Bash|All are user-overridable|This keeps context|This file provides)' > "$OUT/rules.txt" || true
printf '%s\t%s\n' tool "$tool" tool_path "$tool_path" tool_name "$tool_name" runner "$runner" flag "$flag" desired "$desired" sites "$sites" \
  test_file "$test_file" test_cmd "$test_cmd" changelog "CHANGELOG.md" \
  callers "$(git grep -l -F "$tool" -- ':!*.md' ':!*.json' ':!bench/*' ':!*test*' ':!'"$tool_path" | tr '\n' ' ' | sed 's/ *$//; s/ /, /g')" \
  task_name "add-${flag#--}-flag" project "A pure-Bash Agent Skill (no build step, no package manager, no compiled code)." \
  tool_summary "${summary:-is part of this project}" syntax_check "$syntax" scope_files "$tool_path $test_file CHANGELOG.md" > "$OUT/slots.tsv"
echo "target=$target | new=$new_el | desired=$desired | flag_kind=$(A .answers.flag_kind.choice) | sites=$sites | tool_path=$tool_path | test_file=$test_file | test_cmd=$test_cmd" >&2
