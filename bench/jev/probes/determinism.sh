#!/usr/bin/env bash
# Repeat one identical decision request; print discrete choices and scores per run.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$HERE/../../.."; T=$(mktemp); trap 'rm -f "$T"' EXIT
jq -n --arg r "${1:-add a --verbose flag to gather-context.sh that prints which probes ran}" \
  --slurpfile q "$ROOT/skills/prompt-improver/assets/fast-templates/questions.json" \
  '{model:"jev-latest", state:{request:$r}, questions:$q[0].decide}' >"$T"
for i in $(seq 1 "${RUNS:-6}"); do
  "$HERE/jev" "$T" | jq -c '.answers | {triage:.triage.choice, archetype:.archetype.choice, complexity:.complexity.score, risk:.risk.score, multi:.multi_task.noul, clarity:.clarity.score}'
done
