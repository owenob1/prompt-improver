#!/usr/bin/env bash
# bench/jev/judge.sh — blind pairwise quality judgement: baseline (mode off) vs each
# candidate mode, per corpus id. Order is randomised; the judge never sees mode names.
#
#   BENCH_JUDGE_MODEL=opus        claude model used as judge
#   BENCH_MODES="route compose auto"
#   BENCH_OUT=<dir>               results directory from run.sh
#   BENCH_IDS="r01 r05"           judge a subset
#
# Writes $BENCH_OUT/judgements.jsonl: {id, mode, result: win|tie|loss} from the
# candidate's point of view. Identical outputs are recorded as ties without a call.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${BENCH_OUT:-$HERE/results}"
MODES="${BENCH_MODES:-route compose auto}"
JUDGE_MODEL="${BENCH_JUDGE_MODEL:-opus}"
touch "$OUT/judgements.jsonl"

while IFS= read -r line; do
  id=$(jq -r .id <<<"$line")
  if [ -n "${BENCH_IDS:-}" ]; then
    case " $BENCH_IDS " in *" $id "*) ;; *) continue ;; esac
  fi
  request=$(jq -r .request <<<"$line")
  base="$OUT/off/$id.xml"
  [ -s "$base" ] || continue
  for mode in $MODES; do
    cand="$OUT/$mode/$id.xml"
    [ -s "$cand" ] || continue
    if jq -e --arg id "$id" --arg m "$mode" 'select(.id == $id and .mode == $m)' "$OUT/judgements.jsonl" >/dev/null 2>&1 \
      && [ -n "$(jq -c --arg id "$id" --arg m "$mode" 'select(.id == $id and .mode == $m)' "$OUT/judgements.jsonl")" ]; then
      continue
    fi
    if cmp -s "$base" "$cand"; then
      jq -cn --arg id "$id" --arg m "$mode" '{id:$id, mode:$m, result:"tie", note:"identical"}' >>"$OUT/judgements.jsonl"
      continue
    fi
    if [ $((RANDOM % 2)) -eq 0 ]; then a="$base"; b="$cand"; cand_is=B; else a="$cand"; b="$base"; cand_is=A; fi
    prompt=$(mktemp)
    {
      cat <<'P'
You are judging two specifications written for a coding agent from the same user request.
Judge which one would lead a capable coding agent to a correct, verified result for THIS request.

Criteria, in order of weight:
1. Fidelity: covers what the request asks for, adds nothing unrelated, preserves its details.
2. Verification: concrete, runnable checks that would catch a wrong result.
3. Specificity: requirements and approach specific to this request rather than generic advice.
4. Safety: an escape clause, sensible constraints, a final self-check.

Length is not a virtue. If both are equally good, answer TIE.
Reply with exactly one line: WINNER: A, WINNER: B, or WINNER: TIE.
P
      printf '\n<request>\n%s\n</request>\n\n<spec-A>\n' "$request"
      cat "$a"
      printf '</spec-A>\n\n<spec-B>\n'
      cat "$b"
      printf '</spec-B>\n'
    } >"$prompt"
    verdict=$(claude -p --tools "" --output-format text --no-session-persistence --permission-mode dontAsk \
      --model "$JUDGE_MODEL" <"$prompt" 2>/dev/null | grep -oE 'WINNER: (A|B|TIE)' | tail -n 1 || true)
    rm -f "$prompt"
    case "$verdict" in
      "WINNER: TIE") result=tie ;;
      "WINNER: $cand_is") result=win ;;
      "WINNER: A"|"WINNER: B") result=loss ;;
      *) result=error ;;
    esac
    jq -cn --arg id "$id" --arg m "$mode" --arg r "$result" '{id:$id, mode:$m, result:$r}' >>"$OUT/judgements.jsonl"
    echo "$id $mode $result" >&2
  done
done <"$HERE/corpus.jsonl"
