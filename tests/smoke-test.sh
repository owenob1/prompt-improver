#!/usr/bin/env bash
# Repo-level smoke tests for marketplace layout + skill package integrity.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SKILL="$ROOT/skills/prompt-improver"

PASS=0
FAIL=0
ok() { echo "  OK  $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL + 1)); }

echo "== prompt-improver repo smoke =="
echo "Root: $ROOT"
echo ""

# 1. Required marketplace layout
echo "[1] marketplace layout"
for p in \
  skills/prompt-improver/SKILL.md \
  .claude-plugin/marketplace.json \
  plugins/prompt-improver/.claude-plugin/plugin.json \
  LICENSE README.md
do
  if [ -e "$p" ]; then ok "exists $p"; else bad "missing $p"; fi
done

# Symlink or nested skill for Claude plugin
if [ -e plugins/prompt-improver/skills/prompt-improver/SKILL.md ]; then
  ok "plugin skill path resolves to SKILL.md"
else
  bad "plugin skill path missing SKILL.md"
fi

# 2. Frontmatter has name + description
echo ""
echo "[2] SKILL.md frontmatter"
if head -30 "$SKILL/SKILL.md" | grep -q '^name: *prompt-improver' \
  && head -40 "$SKILL/SKILL.md" | grep -q '^description:'; then
  ok "name and description present"
else
  bad "SKILL.md missing required frontmatter"
fi

# 3. Skill-internal smoke (scripts)
echo ""
echo "[3] skill package scripts"
if [ -x "$SKILL/scripts/smoke-test.sh" ] || [ -f "$SKILL/scripts/smoke-test.sh" ]; then
  if bash "$SKILL/scripts/smoke-test.sh"; then
    ok "skill scripts/smoke-test.sh"
  else
    bad "skill scripts/smoke-test.sh failed"
  fi
else
  bad "skill scripts/smoke-test.sh missing"
fi

# 4. skills CLI discovery (if available)
echo ""
echo "[4] npx skills discovery"
if command -v npx >/dev/null 2>&1; then
  LIST_OUT=$(npx --yes skills add "$ROOT" --list 2>&1 || true)
  if echo "$LIST_OUT" | grep -qi 'prompt-improver'; then
    ok "npx skills add . --list finds prompt-improver"
  else
    # Private clone / network quirks: still record output for CI logs
    echo "$LIST_OUT" | tail -20
    bad "npx skills did not list prompt-improver"
  fi
else
  echo "  SKIP npx not available"
fi

echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
echo "All repo smoke tests passed."
exit 0
