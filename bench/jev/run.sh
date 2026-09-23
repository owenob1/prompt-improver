#!/usr/bin/env bash
# bench/jev/run.sh — run the corpus through generate-prompt.sh in each fast-path mode.
#
#   BENCH_MODES="off auto"                 modes to run (off = the 1.1.0 LLM baseline; auto | ground = v2)
#   BENCH_CWD=<repo>                       project the requests are about (default: this repo)
#   BENCH_IDS="r01 r05"                    run a subset
#   BENCH_OUT=<dir>                        results directory (default: bench/jev/results)
#   BENCH_FORCE=1                          re-run cases that already have a result
#
# Needs jq, a generator CLI for the LLM path, and TYPESAFE_API_KEY or
# OPENROUTER_API_KEY for the Jev modes. Output: $BENCH_OUT/<mode>/<id>.xml|.err
# plus one JSON line per case in $BENCH_OUT/runs.jsonl.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
GEN="$REPO/skills/prompt-improver/scripts/generate-prompt.sh"
VALIDATE="$REPO/skills/prompt-improver/scripts/validate-prompt.sh"
MODES="${BENCH_MODES:-off auto}"
CWD="${BENCH_CWD:-$REPO}"
OUT="${BENCH_OUT:-$HERE/results}"
mkdir -p "$OUT"

_now_ms() {
  local t
  t=$(date +%s%N 2>/dev/null || true)
  case "$t" in *N|'') echo $(( $(date +%s) * 1000 )) ;; *) echo $(( t / 1000000 )) ;; esac
}

while IFS= read -r line; do
  id=$(jq -r .id <<<"$line")
  kind=$(jq -r .kind <<<"$line")
  if [ -n "${BENCH_IDS:-}" ]; then
    case " $BENCH_IDS " in *" $id "*) ;; *) continue ;; esac
  fi
  req=$(mktemp)
  jq -r .request <<<"$line" >"$req"
  for mode in $MODES; do
    mkdir -p "$OUT/$mode"
    xml="$OUT/$mode/$id.xml"
    err="$OUT/$mode/$id.err"
    if [ -s "$xml" ] && [ -z "${BENCH_FORCE:-}" ]; then
      continue
    fi
    t0=$(_now_ms)
    rc=0
    PROMPT_IMPROVER_FAST_PATH="$mode" bash "$GEN" --mode plan --cwd "$CWD" --raw-input-file "$req" \
      >"$xml" 2>"$err" </dev/null || rc=$?
    ms=$(( $(_now_ms) - t0 ))

    # v2 tiers: A compiled (no LLM) · B compiled + LLM gap-fill · C grounded LLM.
    path="llm"
    grep -q '^fast-path: tier A' "$err" && path="A"
    grep -q '^fast-path: tier B merged' "$err" && path="B"
    grep -q '^fast-path: tier B output was incomplete' "$err" && path="B-fallback"
    grep -q '^fast-path: tier C' "$err" && path="C"
    grep -q '^fast-path: passthrough' "$err" && path="passthrough"
    [ "$rc" -eq 3 ] && path="bounce"
    tier=$(sed -n 's/^Using backend: .*(model: \(.*\))$/\1/p' "$err" | tail -n 1)
    jev_ms=$(sed -n 's/^fast-path: tier [ABC].*(\([0-9]*\)ms.*/\1/p; s/^fast-path: tier A: .* in \([0-9]*\)ms.*/\1/p' "$err" | tail -n 1)
    model=$(sed -n 's/^Trying backend: [a-z]* (model: \(.*\))$/\1/p' "$err" | tail -n 1)
    valid=false
    warnings=0
    if [ "$rc" -eq 0 ]; then
      vout=$(bash "$VALIDATE" "$xml" 2>&1 || true)
      [[ "$vout" == *"VALIDATION: PASS"* ]] && valid=true
      warnings=$(grep -c '^WARN' <<<"$vout" || true)
    fi
    jq -cn --arg id "$id" --arg kind "$kind" --arg mode "$mode" --argjson rc "$rc" --argjson ms "$ms" \
      --arg path "$path" --arg tier "$tier" --arg fast_ms "$jev_ms" --arg model "$model" \
      --argjson valid "$valid" --argjson warnings "${warnings:-0}" \
      '{id:$id, kind:$kind, mode:$mode, rc:$rc, ms:$ms, path:$path, tier:$tier,
        fast_ms:($fast_ms|tonumber? // null), model:$model, valid:$valid, warnings:$warnings}' \
      >>"$OUT/runs.jsonl"
    echo "$id $mode rc=$rc ${ms}ms path=$path${tier:+ tier=$tier}${model:+ model=$model}" >&2
  done
  rm -f "$req"
done <"$HERE/corpus.jsonl"
