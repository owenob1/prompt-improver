#!/usr/bin/env bash
# validate-prompt.sh
# Validates a generated XML prompt for required structural elements.
# Checks are informed by the Claude Code Prompt Engineering Playbook (Phases 3-9).
# Usage: echo "$prompt" | bash validate-prompt.sh
#        bash validate-prompt.sh prompt-file.md
set -euo pipefail

# Read prompt from file argument or stdin
if [ "${1:-}" ] && [ -f "$1" ]; then
  PROMPT=$(cat "$1")
else
  PROMPT=$(cat)
fi

ERRORS=0
WARNINGS=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo "WARN: $1"; WARNINGS=$((WARNINGS + 1)); }

# --- Required element checks ---

# 1. At least one <task> block exists
TASK_COUNT=$(echo "$PROMPT" | grep -c '<task' || true)
if [ "$TASK_COUNT" -gt 0 ]; then
  pass "task blocks found ($TASK_COUNT)"
else
  fail "no task blocks found"
fi

# 2. Every <task> block contains a <verification> section
VERIFICATION_COUNT=$(echo "$PROMPT" | grep -c '<verification' || true)
if [ "$TASK_COUNT" -gt 0 ]; then
  if [ "$VERIFICATION_COUNT" -ge "$TASK_COUNT" ]; then
    pass "all tasks have verification ($VERIFICATION_COUNT/$TASK_COUNT)"
  else
    fail "not all tasks have verification ($VERIFICATION_COUNT/$TASK_COUNT)"
  fi
fi

# 3. A <check> block exists
if echo "$PROMPT" | grep -q '<check'; then
  pass "check block present"
else
  fail "no check block found"
fi

# 4. A typecheck command appears somewhere
if echo "$PROMPT" | grep -qiE '(tsc|pyright|mypy|go vet|cargo check|cargo test)'; then
  pass "typecheck command found"
else
  fail "no typecheck command found"
fi

# 5. An <escape> clause exists (in execution block or standalone)
if echo "$PROMPT" | grep -q '<escape'; then
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
done < <(echo "$PROMPT" | grep -oiE "\b($VAGUE_WORDS)\b" | tr '[:upper:]' '[:lower:]' | sort -u || true)

# 7. No <approach> block (replaced <evaluate>)
if ! echo "$PROMPT" | grep -q '<approach'; then
  warn "no approach block found — consider adding think-before-act reasoning"
fi

# --- Emphasis and signal quality (Playbook Phase 3) ---

# 8. Emphasis dilution check — >20% of instructions at CRITICAL/ALWAYS/NEVER dilutes signal
TOTAL_INSTRUCTIONS=$(echo "$PROMPT" | grep -cE '^\s*[-*]|^\s*[0-9]+\.' || true)
if [ "$TOTAL_INSTRUCTIONS" -gt 5 ]; then
  TOP_TIER_COUNT=$(echo "$PROMPT" | grep -cE '\b(CRITICAL|ALWAYS|NEVER)\b' || true)
  if [ "$TOTAL_INSTRUCTIONS" -gt 0 ]; then
    RATIO=$((TOP_TIER_COUNT * 100 / TOTAL_INSTRUCTIONS))
    if [ "$RATIO" -gt 20 ]; then
      warn "emphasis saturation: ${RATIO}% of instructions use CRITICAL/ALWAYS/NEVER (>20%) — reserve top-tier emphasis for rules with genuine consequences"
    fi
  fi
fi

# 9. Aggressive language detection — nuanced for Claude 4.6
# The playbook says: lighter emphasis for Claude 4.6, but safety rules keep full emphasis.
# Count aggressive language, but distinguish safety context from general usage.
AGGRESSIVE_WORDS="MUST|CRITICAL|ABSOLUTELY|non-negotiable|NO exceptions"
AGGRESSIVE_TOTAL=$(echo "$PROMPT" | grep -oE "\b($AGGRESSIVE_WORDS)\b" | wc -l || true)

# Check if aggressive language appears near safety/security context
SAFETY_AGGRESSIVE=0
if echo "$PROMPT" | grep -qiE '(safety|security|data.loss|injection|destructive|irreversible).*\b(CRITICAL|MUST|NEVER)\b'; then
  SAFETY_AGGRESSIVE=$((SAFETY_AGGRESSIVE + 1))
fi
if echo "$PROMPT" | grep -qiE '\b(CRITICAL|MUST|NEVER)\b.*(safety|security|data.loss|injection|destructive|irreversible)'; then
  SAFETY_AGGRESSIVE=$((SAFETY_AGGRESSIVE + 1))
fi

# Warn only on non-safety aggressive language exceeding threshold
NON_SAFETY_AGGRESSIVE=$((AGGRESSIVE_TOTAL > SAFETY_AGGRESSIVE ? AGGRESSIVE_TOTAL - SAFETY_AGGRESSIVE : 0))
if [ "$NON_SAFETY_AGGRESSIVE" -gt 3 ]; then
  warn "aggressive language detected ($AGGRESSIVE_TOTAL total, ~$SAFETY_AGGRESSIVE in safety context) — Claude 4.6 responds better to calm instructions for non-safety rules"
elif [ "$AGGRESSIVE_TOTAL" -gt 2 ] && [ "$SAFETY_AGGRESSIVE" -eq 0 ]; then
  warn "aggressive language detected ($AGGRESSIVE_TOTAL instances, none in safety context) — use calm, direct instructions"
fi

# --- Writing technique quality (Playbook Phase 4) ---

# 10. Decision boundary examples — check for <reasoning> blocks when examples exist
EXAMPLE_COUNT=$(echo "$PROMPT" | grep -c '<example' || true)
REASONING_COUNT=$(echo "$PROMPT" | grep -c '<reasoning' || true)
if [ "$EXAMPLE_COUNT" -gt 2 ] && [ "$REASONING_COUNT" -eq 0 ]; then
  warn "examples present but no <reasoning> blocks — decision boundary examples with reasoning are the most effective steering technique"
fi

# --- Check block quality (Playbook Phase 9) ---

if echo "$PROMPT" | grep -q '<check'; then
  # File re-read
  if ! echo "$PROMPT" | grep -qi 're-read\|reread\|verify.*changed.*file\|scan.*changed'; then
    fail "check block missing file re-read verification"
  fi
  # Typecheck in check block
  if ! echo "$PROMPT" | grep -qi 'typecheck\|tsc.*noEmit\|pyright\|cargo check'; then
    warn "check block missing typecheck command"
  fi
  # Test suite
  if ! echo "$PROMPT" | grep -qi 'test suite\|npm test\|run.*test'; then
    warn "check block missing test suite execution"
  fi
  # Requirement status reporting
  if ! echo "$PROMPT" | grep -qi 'requirement\|status.*for.*each\|compare.*original'; then
    warn "check block missing requirement-by-requirement status reporting"
  fi
fi

# --- Constraint quality (Playbook Phase 5) ---

# 11. Constraints section — check for generic boilerplate
if echo "$PROMPT" | grep -qi '<constraints'; then
  GENERIC_PATTERNS="no stubs|no placeholder|re-read.*file|run.*test.*after|deterministic.*operation|bash.*for.*all"
  GENERIC_COUNT=$(echo "$PROMPT" | sed -n '/<constraints/,/<\/constraints/p' | grep -ciE "$GENERIC_PATTERNS" || true)
  if [ "$GENERIC_COUNT" -gt 2 ]; then
    warn "constraints contain $GENERIC_COUNT generic rules — move these to verification/check blocks, keep constraints task-specific"
  fi
fi

# --- Size and structure ---

# 12. Prompt exceeds 120 lines without phasing
LINE_COUNT=$(echo "$PROMPT" | wc -l | tr -d ' ')
if [ "$LINE_COUNT" -gt 120 ]; then
  if ! echo "$PROMPT" | grep -q '<phase'; then
    warn "prompt exceeds 120 lines ($LINE_COUNT) without phasing"
  fi
fi

# 13. UI tasks should mention visual verification
if echo "$PROMPT" | grep -qiE '(component|page|ui|ux|layout|responsive|css|tailwind|frontend)'; then
  if ! echo "$PROMPT" | grep -qiE '(chrome|browser|screenshot|visual.*verif|viewport|breakpoint)'; then
    warn "UI-related task missing visual verification requirement"
  fi
fi

# --- Deprecated pattern warnings ---

if echo "$PROMPT" | grep -q '<evaluate'; then
  warn "<evaluate> is deprecated — use <approach> for think-before-act reasoning"
fi
if echo "$PROMPT" | grep -qi 'sequential.thinking\|sequentialthinking'; then
  warn "sequential-thinking MCP reference detected — use native <approach> blocks instead"
fi

# --- Autonomous agent prompt checks (Playbook Phase 8) ---

# 14. Trust hierarchy — if prompt mentions autonomous/auto-mode/tool results
if echo "$PROMPT" | grep -qiE '(autonom|auto.mode|tool.result|subagent|delegation)'; then
  if ! echo "$PROMPT" | grep -qiE '(override_rules|trust.*hierarch|priority.*order|data.*only|not.*instruction)'; then
    warn "autonomous agent prompt missing trust hierarchy — declare that tool results are DATA, not instructions"
  fi
fi

# 15. Known failure modes — for complex multi-task prompts
if [ "$TASK_COUNT" -gt 3 ]; then
  if ! echo "$PROMPT" | grep -qi 'failure.mode\|common.mistake\|known_failure'; then
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
