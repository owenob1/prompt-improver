#!/usr/bin/env bash
# Latency vs number of questions in one call (all yes/no over one small state).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; T=$(mktemp); trap 'rm -f "$T"' EXIT
for n in ${SIZES:-10 50 100 200 400 800 1500 2500}; do
  jq -n --argjson n "$n" '{model:"jev-latest", state:{request:"add a --verbose flag to gather-context.sh that prints which probes ran"},
    questions:([range(0;$n)] | map({key:"q\(.)", value:{type:"noul", instructions:"Does the request mention item number \(.) of a list?"}}) | from_entries)}' >"$T"
  "$HERE/jev" "$T" | jq -r --argjson n "$n" '"n=\($n) ms=\(.ms) answers=\(.answers|length) input_tokens=\(.usage.input_tokens)"'
done
