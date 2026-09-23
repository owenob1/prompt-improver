#!/usr/bin/env bash
# Item guards: narrow preconditions, premised on the request (+ the target's usage text).
# Usage: guards.sh "<request>" <file-with-tool-usage-text>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; T=$(mktemp); trap 'rm -f "$T"' EXIT
jq -n --arg r "$1" --rawfile u "$2" '{model:"jev-latest", state:{request:$r, tool_usage:$u}, questions:{
  g_lookup:{type:"noul", instructions:"Is each thing the new flag reports on a lookup or check that either finds something or comes up empty?"},
  g_sites:{type:"noul", instructions:"Does the new flag report on fixed checks or steps written in the code, each of which runs or is skipped?"},
  g_attempts:{type:"noul", instructions:"Does the new flag report on a sequence of attempts, where each attempt can succeed or fail?"},
  g_positional:{type:"noul", instructions:"Does the tool described in `tool_usage` take positional (non-flag) arguments?"},
  g_bare_run:{type:"noul", instructions:"Can the tool described in `tool_usage` produce its normal output when run with no arguments at all?"}}}' >"$T"
"$HERE/jev" "$T" | jq -r '"ms=\(.ms) " + ([.answers|to_entries[]|"\(.key)=\(.value.noul)"]|join(" "))'
