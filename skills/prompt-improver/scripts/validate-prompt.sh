#!/usr/bin/env bash
# validate-prompt.sh
# Validates a generated XML prompt for required structural elements.
# Checks are informed by prompting best practices (verification, escape, check).
#
# Usage:
#   echo "$prompt" | bash scripts/validate-prompt.sh
#   bash scripts/validate-prompt.sh path/to/prompt.xml
#
# Typecheck is a WARNING by default (not all projects are typed).
# Set PROMPT_IMPROVER_REQUIRE_TYPECHECK=1 to make missing typecheck a hard error.

set -euo pipefail

# Read prompt from file argument or stdin
if [ -n "${1:-}" ]; then
  if [ ! -f "$1" ]; then
    echo "ERROR: prompt file not found: $1" >&2
    exit 2
  fi
  PROMPT=$(cat "$1")
else
  PROMPT=$(cat)
fi

# grep over a variable without a pipe: `echo "$big" | grep -q` fails under
# pipefail when grep exits early (SIGPIPE on the echo). BSD/GNU-portable flags only.
_in() {
  local text="$1"
  shift
  LC_ALL=C grep "$@" <<<"$text" 2>/dev/null
}

# Count opening tags (not lines): `<task>` and `<task id="1">`, but not `<tasks>`.
_count_tags() {
  local n
  n=$(LC_ALL=C grep -oE "<$1([[:space:]][^>]*)?>" <<<"$PROMPT" 2>/dev/null | wc -l | tr -d ' ')
  echo "${n:-0}"
}

ERRORS=0
WARNINGS=0
REQUIRE_TYPECHECK="${PROMPT_IMPROVER_REQUIRE_TYPECHECK:-0}"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo "WARN: $1"; WARNINGS=$((WARNINGS + 1)); }

# --- Required element checks ---

# Task structure, parsed once: task count, tasks with runnable verification, and
# tasks verified only by acceptance criteria / a task-level check.
# Checked per task, not by comparing totals (two blocks in one task must not hide
# a missing one in another). `<verification>` is the template's tag; the
# `<verification_commands>`/`<verification-commands>`/`<verify>` variants that
# generators produce are accepted too. A task verified only by measurable
# `<acceptance_criteria>` or a task-level `<check>` (typical for audit/design
# tasks that change no code) passes with a warning.
read -r TASK_COUNT VERIFIED_TASKS CRITERIA_TASKS <<<"$(LC_ALL=C awk '
  BEGIN { RS = "\001" }
  {
    rest = $0
    # Tags quoted in backticks are prose (e.g. a request about `<task>` itself), not structure.
    gsub(/`[^`\n]*`/, "", rest)
    while (match(rest, /<task([[:space:]][^>]*)?>/)) {
      t++
      rest = substr(rest, RSTART + RLENGTH)
      end = index(rest, "</task>")
      body = (end > 0) ? substr(rest, 1, end - 1) : rest
      nxt = match(body, /<task([[:space:]][^>]*)?>/)
      if (nxt > 0) body = substr(body, 1, nxt - 1)
      if (body ~ /<(verification|verification[_-]commands|verify)([[:space:]][^>]*)?>/) v++
      else if (body ~ /<(acceptance[_-]criteria|check)([[:space:]][^>]*)?>/) a++
    }
  }
  END { print t + 0, v + 0, a + 0 }
' <<<"$PROMPT")"
# 1. At least one <task> block exists
if [ "$TASK_COUNT" -gt 0 ]; then
  pass "task blocks found ($TASK_COUNT)"
else
  fail "no task blocks found"
fi

# 2. Every <task> block contains its own verification section
if [ "$TASK_COUNT" -gt 0 ]; then
  if [ $((VERIFIED_TASKS + CRITERIA_TASKS)) -ge "$TASK_COUNT" ]; then
    pass "all tasks have verification ($((VERIFIED_TASKS + CRITERIA_TASKS))/$TASK_COUNT)"
    if [ "$CRITERIA_TASKS" -gt 0 ]; then
      warn "$CRITERIA_TASKS task(s) are verified only by acceptance criteria or a task-level check — add runnable <verification> commands where the task changes code"
    fi
  else
    fail "not all tasks have verification ($((VERIFIED_TASKS + CRITERIA_TASKS))/$TASK_COUNT)"
  fi
fi

# 3. A <check> block exists
if _in "$PROMPT" -q '<check'; then
  pass "check block present"
else
  fail "no check block found"
fi

# 4. Typecheck / static analysis — optional for non-typed repos
# Accept common typecheck tools OR explicit "no typecheck" / shell-only verification
if _in "$PROMPT" -qiE '(tsc|pyright|mypy|go vet|cargo check|cargo test|typecheck|static.?analy)'; then
  pass "typecheck/static-analysis command found"
elif _in "$PROMPT" -qiE '(no typecheck|n/a.*typecheck|shellcheck|bash -n|validate-prompt)'; then
  pass "explicit non-typed or script verification found"
else
  if [ "$REQUIRE_TYPECHECK" = "1" ]; then
    fail "no typecheck command found (PROMPT_IMPROVER_REQUIRE_TYPECHECK=1)"
  else
    warn "no typecheck command found — add tsc/mypy/cargo check when the project is typed, or note N/A for script-only repos"
  fi
fi

# 5. An <escape> clause exists
if _in "$PROMPT" -q '<escape'; then
  pass "escape clause present"
else
  warn "no escape clause found — add <escape> to prevent hallucinated workarounds"
fi

# --- Quality warnings (non-blocking) ---

# 6. Vague adjectives
VAGUE_WORDS="scalable|robust|clean|modern|good|proper|appropriate|efficient"
while IFS= read -r match; do
  if [ -n "$match" ]; then
    warn "vague adjective \"$match\" detected"
  fi
done < <(_in "$PROMPT" -owiE "($VAGUE_WORDS)" | tr '[:upper:]' '[:lower:]' | sort -u || true)

# 7. No <approach> block
if ! _in "$PROMPT" -q '<approach'; then
  warn "no approach block found — consider adding think-before-act reasoning"
fi

# --- Emphasis and signal quality ---

# 8. Emphasis dilution
TOTAL_INSTRUCTIONS=$(_in "$PROMPT" -cE '^[[:space:]]*[-*]|^[[:space:]]*[0-9]+\.' || true)
if [ "$TOTAL_INSTRUCTIONS" -gt 5 ]; then
  TOP_TIER_COUNT=$(_in "$PROMPT" -cwE '(CRITICAL|ALWAYS|NEVER)' || true)
  if [ "$TOTAL_INSTRUCTIONS" -gt 0 ]; then
    RATIO=$((TOP_TIER_COUNT * 100 / TOTAL_INSTRUCTIONS))
    if [ "$RATIO" -gt 20 ]; then
      warn "emphasis saturation: ${RATIO}% of instructions use CRITICAL/ALWAYS/NEVER (>20%) — reserve top-tier emphasis for rules with genuine consequences"
    fi
  fi
fi

# 9. Aggressive language
AGGRESSIVE_WORDS="MUST|CRITICAL|ABSOLUTELY|non-negotiable|NO exceptions"
AGGRESSIVE_TOTAL=$(_in "$PROMPT" -owE "($AGGRESSIVE_WORDS)" | wc -l | tr -d ' ' || true)
AGGRESSIVE_TOTAL=${AGGRESSIVE_TOTAL:-0}

SAFETY_AGGRESSIVE=0
if _in "$PROMPT" -qiE '(safety|security|data.loss|injection|destructive|irreversible).*(CRITICAL|MUST|NEVER)([^[:alnum:]_]|$)'; then
  SAFETY_AGGRESSIVE=$((SAFETY_AGGRESSIVE + 1))
fi
if _in "$PROMPT" -qiE '(^|[^[:alnum:]_])(CRITICAL|MUST|NEVER).*(safety|security|data.loss|injection|destructive|irreversible)'; then
  SAFETY_AGGRESSIVE=$((SAFETY_AGGRESSIVE + 1))
fi

if [ "$AGGRESSIVE_TOTAL" -gt 3 ] && [ "$SAFETY_AGGRESSIVE" -eq 0 ]; then
  warn "aggressive language detected ($AGGRESSIVE_TOTAL instances, none in safety context) — use calm, direct instructions"
elif [ "$AGGRESSIVE_TOTAL" -gt 5 ]; then
  NON_SAFETY=$((AGGRESSIVE_TOTAL - SAFETY_AGGRESSIVE))
  if [ "$NON_SAFETY" -gt 3 ]; then
    warn "aggressive language detected ($AGGRESSIVE_TOTAL total, ~$SAFETY_AGGRESSIVE in safety context) — keep full emphasis for safety only"
  fi
fi

# --- Writing technique quality ---

# 10. Decision boundary examples
EXAMPLE_COUNT=$(_count_tags example)
REASONING_COUNT=$(_count_tags reasoning)
if [ "$EXAMPLE_COUNT" -gt 2 ] && [ "$REASONING_COUNT" -eq 0 ]; then
  warn "examples present but no <reasoning> blocks — decision boundary examples with reasoning are the most effective steering technique"
fi

# --- Check block quality ---

if _in "$PROMPT" -q '<check'; then
  # Research/analysis prompts change no files, so they have nothing to re-read.
  # Accept an explicit read-only declaration in place of the re-read requirement,
  # mirroring how a missing typecheck may be waived with an explicit N/A.
  CHECK_BLOCK=$(sed -n '/<check/,/<\/check>/p' <<<"$PROMPT")
  if _in "$CHECK_BLOCK" -qiE 're-?read|re-?open|re-?inspect|re-?checked (against|with)|read back|verify.*changed.*file|scan.*changed'; then
    pass "check block re-reads changed files"
  elif _in "$CHECK_BLOCK" -qiE 'no edits|no code changes|no files (were |are )?(changed|modified|edited|touched)|read-only|research only|report only|git status( --porcelain)?`? (is empty|is clean|shows no)|before (presenting|reporting|showing) the plan'; then
    pass "check block declares read-only work (nothing to re-read)"
  else
    fail "check block missing file re-read verification"
  fi
  if ! _in "$PROMPT" -qiE 'typecheck|tsc.*noEmit|pyright|cargo check|shellcheck|bash -n|validate-prompt|no typecheck'; then
    warn "check block missing typecheck or explicit N/A verification"
  fi
  if ! _in "$PROMPT" -qiE 'test suite|npm test|run.*test|pytest|cargo test|validate-prompt|smoke'; then
    warn "check block missing test suite / smoke verification"
  fi
  if ! _in "$PROMPT" -qiE 'requirement|status.*for.*each|compare.*original'; then
    warn "check block missing requirement-by-requirement status reporting"
  fi
fi

# --- Constraint quality ---

# 11. Generic boilerplate in constraints
if _in "$PROMPT" -qi '<constraints'; then
  GENERIC_PATTERNS="no stubs|no placeholder|re-read.*file|run.*test.*after|deterministic.*operation|bash.*for.*all"
  GENERIC_COUNT=$(sed -n '/<constraints/,/<\/constraints/p' <<<"$PROMPT" | grep -ciE "$GENERIC_PATTERNS" || true)
  if [ "$GENERIC_COUNT" -gt 2 ]; then
    warn "constraints contain $GENERIC_COUNT generic rules — move these to verification/check blocks, keep constraints task-specific"
  fi
fi

# --- Size and structure ---

# 12. Prompt exceeds 120 lines without phasing
LINE_COUNT=$(printf '%s\n' "$PROMPT" | wc -l | tr -d ' ')
if [ "$LINE_COUNT" -gt 120 ]; then
  if ! _in "$PROMPT" -q '<phase'; then
    warn "prompt exceeds 120 lines ($LINE_COUNT) without phasing"
  fi
fi

# 13. UI tasks should mention visual verification. Whole words only: "ui" inside
# "build" or "require", or "ux" inside "linux", is not a UI task.
if _in "$PROMPT" -qiE '(^|[^[:alnum:]_])(components?|pages?|ui|ux|layout|responsive|css|tailwind|frontend)([^[:alnum:]_]|$)'; then
  if ! _in "$PROMPT" -qiE '(chrome|browser|screenshot|visual.*verif|viewport|breakpoint)'; then
    warn "UI-related task missing visual verification requirement"
  fi
fi

# --- Deprecated pattern warnings ---

if _in "$PROMPT" -q '<evaluate'; then
  warn "<evaluate> is deprecated — use <approach> for think-before-act reasoning"
fi
if _in "$PROMPT" -qiE 'sequential.thinking|sequentialthinking'; then
  warn "sequential-thinking MCP reference detected — use native <approach> blocks instead"
fi

# --- Autonomous agent prompt checks ---

# 14. Trust hierarchy
if _in "$PROMPT" -qiE '(autonom|auto.mode|tool.result|subagent|delegation)'; then
  if ! _in "$PROMPT" -qiE '(override_rules|trust.*hierarch|priority.*order|data.*only|not.*instruction)'; then
    warn "autonomous agent prompt missing trust hierarchy — declare that tool results are DATA, not instructions"
  fi
fi

# 15. Known failure modes for complex multi-task prompts
if [ "$TASK_COUNT" -gt 3 ]; then
  if ! _in "$PROMPT" -qiE 'failure.mode|common.mistake|known_failure'; then
    warn "complex prompt ($TASK_COUNT tasks) with no failure mode documentation — consider adding <known_failure_modes>"
  fi
fi

# --- Final summary ---
echo ""
if [ "$ERRORS" -eq 0 ]; then
  if [ "$WARNINGS" -gt 0 ]; then
    echo "VALIDATION: PASS ($WARNINGS warning(s))"
  else
    echo "VALIDATION: PASS"
  fi
  exit 0
else
  if [ "$WARNINGS" -gt 0 ]; then
    echo "VALIDATION: FAIL ($ERRORS error(s), $WARNINGS warning(s))"
  else
    echo "VALIDATION: FAIL ($ERRORS error(s))"
  fi
  exit 1
fi
