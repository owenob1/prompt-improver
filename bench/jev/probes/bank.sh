#!/usr/bin/env bash
# Curated-bank relevance: one yes/no per expert item (lib/bank.tsv). Print items with p >= 0.5.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; T=$(mktemp); trap 'rm -f "$T"' EXIT
jq -Rn --arg r "$1" '[inputs | split("\t") | {id:.[0], text:.[1]}] as $b | {model:"jev-latest", state:{request:$r},
  questions:($b|map({key:.id, value:{type:"noul", instructions:"Is this requirement relevant to carrying out the request well: \"\(.text)\"?"}})|from_entries)}' <"$HERE/lib/bank.tsv" >"$T"
"$HERE/jev" "$T" | jq -r '"ms=\(.ms)", ([.answers|to_entries[]|{k:.key,p:.value.noul}]|sort_by(-.p)|map(select(.p>=0.5))|.[]|"  \(.p) \(.k)")'
