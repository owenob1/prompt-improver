#!/usr/bin/env bash
# Extraction by choice: every contiguous word span (≤12 words, ≤254) is an option; Jev picks one per role.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; T=$(mktemp); O=$(mktemp); trap 'rm -f "$T" "$O"' EXIT
spans=$(jq -rn --arg r "$1" '($r|gsub("[,:;]";" ")|split(" ")|map(select(length>0))) as $w
  | [range(0;$w|length) as $i | range(1;13) as $l | select($i+$l <= ($w|length)) | $w[$i:$i+$l]|join(" ")] | unique | .[0:254]')
jq -n --arg r "$1" --argjson sp "$spans" '({none:"Nothing in the request plays this role"} + ($sp|to_entries|map({key:"s\(.key)", value:.value})|from_entries)) as $c
 | {model:"jev-latest", state:{request:$r}, questions:{
   target:{type:"choice", instructions:"Which words name the existing file, component, command, function or system that must be changed?", criteria:$c},
   new_element:{type:"choice", instructions:"Which words name the new thing to add (a flag, option, feature, file, endpoint or test)?", criteria:$c},
   desired:{type:"choice", instructions:"Which words describe how things should behave once the work is done?", criteria:$c},
   symptom:{type:"choice", instructions:"Which words describe the current wrong behaviour or error?", criteria:$c},
   constraint:{type:"choice", instructions:"Which words state a limit or rule the change must respect?", criteria:$c},
   metric:{type:"choice", instructions:"Which words give a measured number, amount or duration?", criteria:$c}}}' >"$T"
"$HERE/jev" "$T" >"$O"
jq -r --argjson sp "$spans" '"ms=\(.ms)", (.answers|to_entries[]|"  \(.key): \(if .value.choice=="none" then "(none)" else $sp[(.value.choice|ltrimstr("s")|tonumber)] end) (p_max \(.value.probabilities|to_entries|map(.value)|max))")' "$O"
