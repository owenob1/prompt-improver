#!/usr/bin/env bash
# Card-in-question retrieval: state = request only; one yes/no per file with its card in the question.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; T=$(mktemp); C=$(mktemp); trap 'rm -f "$T" "$C"' EXIT
bash "$HERE/cards.sh" "$HERE" >"$C"
jq -Rn --arg r "$1" '[inputs|select(length>0)] as $cards | {model:"jev-latest", state:{request:$r},
  questions:($cards|to_entries|map({key:"f\(.key)", value:{type:"noul", instructions:("Would carrying out the request require editing this file? File: " + .value)}})|from_entries)}' <"$C" >"$T"
"$HERE/jev" "$T" | jq -r --rawfile c "$C" '($c|split("\n")|map(select(length>0))) as $cs | "ms=\(.ms)",
  ([.answers|to_entries[]|{f:($cs[(.key|ltrimstr("f")|tonumber)]|split(" — ")[0]), p:.value.noul}]|sort_by(-.p)|.[0:5][]|"  \(.p)  \(.f)")'
