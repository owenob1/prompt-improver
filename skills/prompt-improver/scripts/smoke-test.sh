#!/usr/bin/env bash
# scripts/smoke-test.sh
# Offline checks that do not require API keys or coding CLIs.
# Exit 0 only if all checks pass.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

PASS=0
FAIL=0

ok() { echo "  OK  $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL + 1)); }

echo "== prompt-improver smoke tests =="
echo "Root: $ROOT_DIR"
echo ""

# 1. Syntax of all shell scripts
echo "[1/8] bash -n on scripts"
while IFS= read -r -d '' f; do
  if bash -n "$f" 2>/dev/null; then
    ok "syntax $f"
  else
    bad "syntax $f"
  fi
done < <(find scripts -name '*.sh' -print0)

# 2. settings does not clobber SCRIPT_DIR
echo ""
echo "[2/8] settings.sh does not overwrite caller SCRIPT_DIR"
# shellcheck disable=SC1091
OUT=$(bash -c '
  SCRIPT_DIR="'"$SCRIPT_DIR"'"
  source "'"$SCRIPT_DIR"'/lib/settings.sh"
  load_settings
  echo "SCRIPT_DIR=$SCRIPT_DIR"
  echo "BACKEND=$BACKEND"
  BACKEND_SCRIPT="$SCRIPT_DIR/backends/grok.sh"
  if [ -x "$BACKEND_SCRIPT" ]; then echo "BACKEND_OK=1"; else echo "BACKEND_OK=0"; fi
')
if echo "$OUT" | grep -q "SCRIPT_DIR=$SCRIPT_DIR" && echo "$OUT" | grep -q "BACKEND_OK=1"; then
  ok "SCRIPT_DIR preserved; backends resolvable"
else
  bad "SCRIPT_DIR leak or missing backends: $OUT"
fi

# 3. assemble-generation-prompt produces materials + raw wrapper
# Note: avoid `echo "$huge" | grep -q` under `set -o pipefail` — early grep exit
# causes SIGPIPE/broken pipe on large assembler output (fails on Ubuntu CI).
echo ""
echo "[3/8] assemble-generation-prompt.sh"
ASM=$(bash scripts/assemble-generation-prompt.sh "smoke test request" 2>&1) || true
if [[ "$ASM" == *"REFERENCE MATERIALS"* ]] \
  && [[ "$ASM" == *"<raw-request-to-improve>"* ]] \
  && [[ "$ASM" == *"smoke test request"* ]] \
  && { [[ "$ASM" == *"IMPROVEMENT-ONLY"* ]] || [[ "$ASM" == *"DO NOT PERFORM"* ]] || [[ "$ASM" == *"DATA ONLY"* ]]; }; then
  ok "assembler embeds refs + improvement guard"
else
  bad "assembler output missing expected sections (len=${#ASM})"
fi

# 4. validate valid fixture
echo ""
echo "[4/8] validate-prompt.sh (valid fixture)"
if bash scripts/validate-prompt.sh examples/fixtures/valid-prompt.xml >/tmp/pi-valid.out 2>&1; then
  ok "valid fixture PASSes"
else
  bad "valid fixture should PASS: $(cat /tmp/pi-valid.out)"
fi

# 5. validate invalid fixture
echo ""
echo "[5/8] validate-prompt.sh (invalid fixture)"
if bash scripts/validate-prompt.sh examples/fixtures/invalid-prompt.xml >/tmp/pi-invalid.out 2>&1; then
  bad "invalid fixture should FAIL"
else
  ok "invalid fixture FAILs as expected"
fi

# 6. typecheck optional by default
echo ""
echo "[6/8] typecheck is optional (warning, not error)"
NO_TC=$(mktemp)
cat > "$NO_TC" <<'EOF'
<task name="docs"><verification>bash scripts/smoke-test.sh</verification></task>
<check>
  Re-read changed files.
  Run smoke tests.
  Report status for each requirement.
</check>
EOF
if bash scripts/validate-prompt.sh "$NO_TC" >/tmp/pi-notc.out 2>&1; then
  if grep -q "WARN: no typecheck" /tmp/pi-notc.out; then
    ok "missing typecheck is WARN and still PASS"
  else
    ok "missing typecheck still PASS"
  fi
else
  bad "missing typecheck should not hard-fail by default: $(cat /tmp/pi-notc.out)"
fi
rm -f "$NO_TC"

# 7. standalone usage guard (no args)
echo ""
echo "[7/8] standalone-improve.sh usage error"
if bash scripts/standalone-improve.sh >/tmp/pi-standalone.out 2>&1; then
  bad "standalone with no args should exit non-zero"
else
  ok "standalone rejects empty input"
fi

# 8. generate-prompt help + required arg
echo ""
echo "[8/8] generate-prompt.sh CLI"
if bash scripts/generate-prompt.sh --help >/tmp/pi-help.out 2>&1; then
  ok "generate-prompt --help works"
else
  bad "generate-prompt --help failed"
fi
if bash scripts/generate-prompt.sh >/tmp/pi-nogen.out 2>&1; then
  bad "generate-prompt without --raw-input should fail"
else
  ok "generate-prompt requires --raw-input"
fi

# 9. default model resolution per backend
echo ""
echo "[9] default generator models"
# shellcheck disable=SC1091
source scripts/lib/settings.sh
load_settings
for pair in "claude:sonnet" "grok:grok-composer-2.5-fast" "gemini:gemini-2.5-pro" "codex:gpt-5.5"; do
  b="${pair%%:*}"
  expect="${pair#*:}"
  got=$(get_default_model_for_backend "$b")
  if [ "$got" = "$expect" ]; then
    ok "default_models $b → $got"
  else
    bad "default_models $b expected $expect got $got"
  fi
done

# Optional: gather-context should not crash
echo ""
echo "[extra] gather-context.sh"
if bash scripts/gather-context.sh . >/tmp/pi-ctx.out 2>&1; then
  ok "gather-context runs"
else
  bad "gather-context failed"
fi

echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
echo "All smoke tests passed."
exit 0
