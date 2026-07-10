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

# 10. model aliases + cross-CLI inference
echo ""
echo "[10] model normalize + backend inference"
for pair in \
  "fable-5:claude-fable-5:claude" \
  "mythos:claude-mythos-preview:claude" \
  "mythos-5:claude-mythos-5:claude" \
  "sonnet:sonnet:claude" \
  "gpt-5.5:gpt-5.5:codex" \
  "codex:gpt-5.5:codex" \
  "openai:gpt-5.5:codex" \
  "gpt-5.6-sol:gpt-5.6-sol:codex" \
  "sol:gpt-5.6-sol:codex" \
  "terra:gpt-5.6-terra:codex" \
  "luna:gpt-5.6-luna:codex" \
  "grok-4.5:grok-4.5:grok" \
  "gemini-2.5-pro:gemini-2.5-pro:gemini" \
  "grok-composer-2.5-fast:grok-composer-2.5-fast:grok"
do
  raw="${pair%%:*}"
  rest="${pair#*:}"
  expect_model="${rest%%:*}"
  expect_be="${rest#*:}"
  got_m=$(normalize_model_id "$raw")
  got_b=$(infer_backend_for_model "$got_m")
  if [ "$got_m" = "$expect_model" ] && [ "$got_b" = "$expect_be" ]; then
    ok "model $raw → $got_m ($got_b)"
  else
    bad "model $raw expected $expect_model/$expect_be got $got_m/$got_b"
  fi
done

# 11. fallback chains
echo ""
echo "[11] model fallback chains"
chain_mythos=$(get_model_fallback_chain "mythos")
chain_sol=$(get_model_fallback_chain "gpt-5.6-sol")
chain_g45=$(get_model_fallback_chain "grok-4.5")
if echo "$chain_mythos" | grep -q 'fable' && echo "$chain_mythos" | grep -q 'opus'; then
  ok "mythos cascade includes fable→opus"
else
  bad "mythos cascade: $chain_mythos"
fi
if echo "$chain_sol" | grep -q 'terra' && echo "$chain_sol" | grep -q 'luna'; then
  ok "sol cascade includes terra→luna"
else
  bad "sol cascade: $chain_sol"
fi
if echo "$chain_g45" | grep -q 'composer'; then
  ok "grok-4.5 cascade includes composer"
else
  bad "grok-4.5 cascade: $chain_g45"
fi
if is_model_retryable_failure 1 "Error: rate limit exceeded for model"; then
  ok "retryable rate-limit detection"
else
  bad "retryable rate-limit detection failed"
fi

if is_model_retryable_failure 1 "You've hit your weekly limit · resets Jul 11"; then
  ok "retryable weekly-limit detection"
else
  bad "retryable weekly-limit detection failed"
fi

if is_account_limit_failure "You've hit your weekly limit · resets Jul 11"; then
  ok "account-limit detection"
else
  bad "account-limit detection failed"
fi

if is_rate_limit_message_only "You've hit your weekly limit · resets Jul 11"; then
  ok "rate-limit-message-only detection"
else
  bad "rate-limit-message-only detection failed"
fi

if is_rate_limit_message_only "<task id=\"1\"><verification>x</verification></task>"; then
  bad "false positive rate-limit on real task XML"
else
  ok "task XML not treated as rate-limit-only"
fi

# The XML guard must win even when the prompt's own text contains retry_patterns
# words. Regression: xml_markers was `<task[[:space:]]>` (matches only `<task >`),
# so real prompts about 429s/quotas were discarded as rate-limit messages.
while IFS='|' read -r label body; do
  [ -z "$label" ] && continue
  if is_rate_limit_message_only "$body"; then
    bad "XML guard: $label misread as a rate-limit message"
  else
    ok "XML guard: $label"
  fi
done <<'EOF'
prompt about rate limiting|<task id="1"><description>Add rate limiting, return 429 with retry-after</description><verification>curl</verification></task>
prompt mentioning not found|<task id="1"><description>Handle when the file is not found</description></task>
prompt mentioning capacity|<task id="1"><description>Increase queue capacity</description></task>
prompt mentioning 401/403|<task id="1"><description>Log 401 and 403 responses</description></task>
bare task tag, no attributes|<task><verification>quota unavailable throttle</verification></task>
EOF

# 12. host detection + no PATH auto-pick for default
echo ""
echo "[12] host-matched backend selection helpers"
export PROMPT_IMPROVER_HOST=claude
host_got=$(detect_host_backend)
if [ "$host_got" = "claude" ]; then
  ok "PROMPT_IMPROVER_HOST=claude"
else
  bad "PROMPT_IMPROVER_HOST expected claude got $host_got"
fi
unset PROMPT_IMPROVER_HOST
if is_supported_backend claude && is_supported_backend grok && ! is_supported_backend cursor; then
  ok "is_supported_backend allowlist"
else
  bad "is_supported_backend allowlist failed"
fi
# NO_HEADLESS bounce when host unknown and no model
_tmpdir=$(mktemp -d)
export PROMPT_IMPROVER_PROJECT_CONFIG_DIR="$_tmpdir"
export PROMPT_IMPROVER_CONFIG_DIR="$_tmpdir"
export PROMPT_IMPROVER_HOST=""
# Force empty host by unsetting and using a clean env for host detect is hard;
# simulate via PROMPT_IMPROVER_HOST=none which is unsupported
export PROMPT_IMPROVER_HOST=none
unset PROMPT_IMPROVER_BACKEND PROMPT_IMPROVER_MODEL PROMPT_IMPROVER_CUSTOM_COMMAND 2>/dev/null || true
set +e
bash scripts/generate-prompt.sh --mode plan --raw-input "x" >/tmp/pi-nohost.out 2>/tmp/pi-nohost.err
_nh=$?
set -e
if [ "$_nh" -eq 3 ] && grep -q 'HOST_BOUNCE:NO_HEADLESS' /tmp/pi-nohost.out; then
  ok "unknown host → HOST_BOUNCE:NO_HEADLESS exit 3"
else
  bad "expected NO_HEADLESS exit 3, got $_nh: $(head -5 /tmp/pi-nohost.err)"
fi
# Host claude with no model → sonnet (only check selection line if claude on PATH)
if command -v claude >/dev/null 2>&1; then
  export PROMPT_IMPROVER_HOST=claude
  set +e
  bash scripts/generate-prompt.sh --mode plan --raw-input "x" --skip-validate >/tmp/pi-host.out 2>/tmp/pi-host.err
  _hc=$?
  set -e
  if grep -q 'host CLI (claude)' /tmp/pi-host.err && grep -q 'model: sonnet' /tmp/pi-host.err; then
    ok "claude host → sonnet default selection"
  else
    # may fail generation (rate limit) but selection reason should appear
    if grep -qE 'host CLI \(claude\).*sonnet|model: sonnet' /tmp/pi-host.err; then
      ok "claude host → sonnet default selection"
    else
      bad "claude host selection: $(head -8 /tmp/pi-host.err)"
    fi
  fi
else
  ok "claude host selection skipped (claude not on PATH)"
fi
unset PROMPT_IMPROVER_HOST PROMPT_IMPROVER_PROJECT_CONFIG_DIR PROMPT_IMPROVER_CONFIG_DIR
rm -rf "$_tmpdir"

# 13. settings overlay + custom alias override
echo ""
echo "[13] settings-driven runtime tables"
ASM_SETTINGS=$(bash scripts/assemble-generation-prompt.sh "settings smoke" 2>&1) || true
if [[ "$ASM_SETTINGS" == *"RUNTIME SETTINGS"* ]] && [[ "$ASM_SETTINGS" == *"enable_research:"* ]]; then
  ok "assembler injects settings overlay"
else
  bad "assembler missing settings overlay"
fi

_tmp_settings=$(mktemp -d)
export PROMPT_IMPROVER_PROJECT_CONFIG_DIR="$_tmp_settings"
cat > "$_tmp_settings/settings.json" <<'EOF'
{
  "model_aliases": {
    "smoke-alias": "sonnet"
  }
}
EOF
# shellcheck disable=SC1091
source scripts/lib/settings.sh
got_alias=$(normalize_model_id "smoke-alias")
if [ "$got_alias" = "sonnet" ]; then
  ok "project model_aliases override"
else
  bad "model_aliases override expected sonnet got $got_alias"
fi
unset PROMPT_IMPROVER_PROJECT_CONFIG_DIR
rm -rf "$_tmp_settings"

# 14. generation customisation + deterministic context (no agent explore)
echo ""
echo "[14] generation materials + deterministic context"
_ctx14=$(bash scripts/gather-context.sh . 2>/dev/null || true)
if echo "$_ctx14" | grep -q 'deterministic'; then
  ok "gather-context labels deterministic"
else
  bad "gather-context missing deterministic label"
fi
if echo "$_ctx14" | grep -qE 'Most-Referenced|Project Structure \(from index\)|pilot_map|find \.'; then
  bad "gather-context still uses find/index exploration"
else
  ok "gather-context has no recursive find/index explorers"
fi
unset _ctx14
_g14=$(mktemp -d)
export PROMPT_IMPROVER_PROJECT_CONFIG_DIR="$_g14"
export PROMPT_IMPROVER_CONFIG_DIR="$_g14/u"
mkdir -p "$_g14" "$_g14/u"
printf '%s\n' '{"generation":{"include_examples":false,"output_instructions":"ONLY_LINE_G14"}}' > "$_g14/settings.json"
_asm=$(bash scripts/assemble-generation-prompt.sh "smoke-raw" 2>/dev/null || true)
if echo "$_asm" | grep -q 'ONLY_LINE_G14'; then
  ok "custom generation.output_instructions applied"
else
  bad "output_instructions not applied"
fi
if echo "$_asm" | grep -q 'BEFORE / AFTER EXAMPLES'; then
  bad "include_examples=false still included examples"
else
  ok "include_examples=false omits examples"
fi
unset PROMPT_IMPROVER_PROJECT_CONFIG_DIR PROMPT_IMPROVER_CONFIG_DIR
rm -rf "$_g14"

# 15. a failing backend must fall through to host bounce, not kill the script
# Regression: run_headless_once used `set +e; cmd; code=$?; set -e`, and because
# errexit is a global option that clobbered the caller's `set +e`, a non-zero
# `return` exited the script at the call site — no diagnostics, no fallback,
# exit 1 instead of exit 3.
echo ""
echo "[15] backend failure falls through to HOST_BOUNCE (errexit leak)"
_e15=$(mktemp -d)
mkdir -p "$_e15/u"
cat > "$_e15/settings.json" <<'EOF'
{
  "backend": "claude",
  "backend_invocation": "commands",
  "preferred_backends": ["claude"],
  "backend_commands": { "claude": "sh -c 'exit 9'" }
}
EOF
export PROMPT_IMPROVER_PROJECT_CONFIG_DIR="$_e15"
export PROMPT_IMPROVER_CONFIG_DIR="$_e15/u"
export PROMPT_IMPROVER_HOST=claude
unset PROMPT_IMPROVER_BACKEND PROMPT_IMPROVER_MODEL PROMPT_IMPROVER_CUSTOM_COMMAND 2>/dev/null || true
set +e
bash scripts/generate-prompt.sh --mode plan --raw-input "x" >/tmp/pi-e15.out 2>/tmp/pi-e15.err
_e15_rc=$?
set -e
if [ "$_e15_rc" -eq 3 ]; then
  ok "failing backend → exit 3 (not the backend's own exit code)"
else
  bad "expected exit 3 from failing backend, got $_e15_rc"
fi
if grep -q 'HOST_BOUNCE' /tmp/pi-e15.out; then
  ok "failing backend emits HOST_BOUNCE marker"
else
  bad "no HOST_BOUNCE marker on stdout"
fi
if grep -q 'failed (exit 9)' /tmp/pi-e15.err; then
  ok "backend exit code surfaced in diagnostics"
else
  bad "backend failure diagnostics swallowed: $(head -3 /tmp/pi-e15.err)"
fi
unset PROMPT_IMPROVER_PROJECT_CONFIG_DIR PROMPT_IMPROVER_CONFIG_DIR PROMPT_IMPROVER_HOST
rm -rf "$_e15"

# 16. research prompts may waive the re-read requirement
echo ""
echo "[16] validate-prompt.sh read-only check blocks"
_ro=$(mktemp)
cat > "$_ro" <<'EOF'
<task name="research"><verification>bash -n scripts/foo.sh</verification></task>
<check>
  - Report the comparison summary for each candidate
  - Confirm no edits were made to any file in the working directory
  - List each original request against actual output
</check>
EOF
if bash scripts/validate-prompt.sh "$_ro" >/tmp/pi-ro.out 2>&1; then
  ok "read-only check block PASSes without a re-read line"
else
  bad "read-only check block should PASS: $(grep '^FAIL' /tmp/pi-ro.out)"
fi
rm -f "$_ro"

# A code-changing prompt with no re-read line must still hard-fail.
_rw=$(mktemp)
cat > "$_rw" <<'EOF'
<task name="impl"><verification>npx tsc --noEmit</verification></task>
<check>
  - Run the test suite
  - Report status for each requirement
</check>
EOF
if bash scripts/validate-prompt.sh "$_rw" >/tmp/pi-rw.out 2>&1; then
  bad "code-changing check block without re-read should FAIL"
else
  ok "code-changing check block without re-read still FAILs"
fi
rm -f "$_rw"

# 17. 'model' in prose must not be read as a retryable limit failure
echo ""
echo "[17] bad-model heuristic is not triggered by prose"
if is_model_retryable_failure 1 "Traceback: could not open the model file at src/model.py"; then
  bad "prose containing 'model' misread as a retryable limit failure"
else
  ok "prose containing 'model' is not a limit failure"
fi
if is_model_retryable_failure 1 "Error: unknown model 'sonnet-9'"; then
  ok "unknown model still detected as retryable"
else
  bad "unknown model should be retryable"
fi

# 18. claude backend switches to stdin above ARG_MAX/2
echo ""
echo "[18] claude.sh ARG_MAX guard"
if grep -q 'ARG_MAX' scripts/backends/claude.sh && grep -q 'claude --print .* <"\$PROMPT_FILE"' scripts/backends/claude.sh; then
  ok "claude.sh has an ARG_MAX guard with a stdin fallback"
else
  bad "claude.sh missing ARG_MAX guard / stdin fallback"
fi

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
