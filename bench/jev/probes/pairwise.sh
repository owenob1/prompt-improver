#!/usr/bin/env bash
# judge.sh "<request>" <specA> <specB> → WINNER line
req="$1"; a="$2"; b="$3"
{ cat <<'X'
You are judging two specifications written for a coding agent from the same user request.
Judge which one would lead a capable coding agent to a correct, verified result for THIS request.

Criteria, in order of weight:
1. Fidelity: covers what the request asks for, adds nothing unrelated, preserves its details.
2. Verification: concrete, runnable checks that would catch a wrong result.
3. Specificity: requirements and approach specific to this request rather than generic advice.
4. Safety: an escape clause, sensible constraints, a final self-check.

Length is not a virtue. If both are equally good, answer TIE.
Reply with exactly one line: WINNER: A, WINNER: B, or WINNER: TIE.
X
printf '\n<request>\n%s\n</request>\n\n<spec-A>\n' "$req"; cat "$a"; printf '</spec-A>\n\n<spec-B>\n'; cat "$b"; printf '</spec-B>\n'; } | timeout 300 claude -p --tools "" --output-format text --no-session-persistence --permission-mode dontAsk --model opus 2>/dev/null | grep -oE 'WINNER: (A|B|TIE)' | tail -1
