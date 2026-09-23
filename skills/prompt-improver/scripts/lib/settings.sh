#!/usr/bin/env bash
# scripts/lib/settings.sh
# Loads prompt-improver settings with sensible defaults and overrides.
# Priority: env vars > project settings > user settings > shipped default > runtime-defaults
#
# IMPORTANT: This file must not overwrite the caller's SCRIPT_DIR.
# It uses PI_* names for its own path resolution.
#
# Every table lookup has a hardcoded Bash fallback for when jq is absent. When
# changing a table in config/runtime-defaults.json, change its fallback here too.

set -euo pipefail

_PI_SETTINGS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PI_ROOT_DIR="$(cd "$_PI_SETTINGS_DIR/../.." && pwd)"

CONFIG_DIR="${PROMPT_IMPROVER_CONFIG_DIR:-$HOME/.config/prompt-improver}"
PROJECT_CONFIG_DIR="${PROMPT_IMPROVER_PROJECT_CONFIG_DIR:-.prompt-improver}"

RUNTIME_DEFAULTS="$_PI_ROOT_DIR/config/runtime-defaults.json"
DEFAULT_SETTINGS="$_PI_ROOT_DIR/config/settings.default.json"
USER_SETTINGS="$CONFIG_DIR/settings.json"
PROJECT_SETTINGS="$PROJECT_CONFIG_DIR/settings.json"

# Point project settings at <dir>/.prompt-improver unless explicitly configured.
# Call before load_settings so --cwd, not the caller's pwd, decides the project.
pi_set_project_dir() {
  local dir="$1"
  if [ -z "${PROMPT_IMPROVER_PROJECT_CONFIG_DIR:-}" ] && [ -n "$dir" ]; then
    PROJECT_CONFIG_DIR="$dir/.prompt-improver"
    PROJECT_SETTINGS="$PROJECT_CONFIG_DIR/settings.json"
  fi
}

_pi_have_jq() {
  command -v jq >/dev/null 2>&1
}

# True when the file is valid JSON (always true without jq — nothing to check with).
_pi_json_ok() {
  _pi_have_jq || return 0
  jq empty "$1" >/dev/null 2>&1
}

# Collect settings JSON files in merge order (later layers override earlier for scalars/objects).
# Malformed files are skipped (load_settings warns about them once).
_pi_settings_files_ordered() {
  local f
  for f in "$RUNTIME_DEFAULTS" "$DEFAULT_SETTINGS" "$USER_SETTINGS" "$PROJECT_SETTINGS"; do
    [ -f "$f" ] && _pi_json_ok "$f" && echo "$f"
  done
  return 0
}

# Same files, highest priority first.
_pi_settings_files_priority() {
  local f
  for f in "$PROJECT_SETTINGS" "$USER_SETTINGS" "$DEFAULT_SETTINGS" "$RUNTIME_DEFAULTS"; do
    [ -f "$f" ] && _pi_json_ok "$f" && echo "$f"
  done
  return 0
}

# Merge a top-level object key across all settings layers (later wins on key collision).
_pi_merged_object_json() {
  local key="$1"
  if ! _pi_have_jq; then
    echo "{}"
    return 0
  fi
  local files=() f
  while IFS= read -r f; do files+=("$f"); done < <(_pi_settings_files_ordered)
  if [ "${#files[@]}" -eq 0 ]; then
    echo "{}"
    return 0
  fi
  jq -s --arg k "$key" '[.[] | .[$k] // {} | if type == "object" then . else {} end] | add' "${files[@]}" 2>/dev/null || echo "{}"
}

# First defined non-empty array at project > user > default > runtime.
_pi_first_array_json() {
  local key="$1"
  local file val
  if _pi_have_jq; then
    while IFS= read -r file; do
      val=$(jq -c --arg k "$key" '.[$k] // empty | select(type == "array")' "$file" 2>/dev/null || true)
      if [ -n "$val" ] && [ "$val" != "[]" ]; then
        echo "$val"
        return 0
      fi
    done < <(_pi_settings_files_priority)
  fi
  echo "[]"
}

# Top-level scalar setting. With jq, `false` is a real value (jq's `//` would
# treat it as missing and fall through to a lower layer). Without jq, a
# line-based fallback reads simple `"key": value` pairs; arrays and objects
# are not supported there and resolve to the default.
get_setting() {
  local key="$1"
  local default="${2:-}"
  local file val

  if _pi_have_jq; then
    while IFS= read -r file; do
      val=$(jq -r --arg k "$key" 'if has($k) and .[$k] != null then (.[$k] | if type == "string" then . else tojson end) else empty end' "$file" 2>/dev/null || true)
      if [ -n "$val" ]; then
        echo "$val"
        return 0
      fi
    done < <(_pi_settings_files_priority)
  else
    for file in "$PROJECT_SETTINGS" "$USER_SETTINGS" "$DEFAULT_SETTINGS" "$RUNTIME_DEFAULTS"; do
      [ -f "$file" ] || continue
      val=$(sed -n -E \
        -e "s/^[[:space:]]*\"$key\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\"[[:space:]]*,?[[:space:]]*$/\\1/p" \
        -e "s/^[[:space:]]*\"$key\"[[:space:]]*:[[:space:]]*([^\"[{[:space:],][^,}[:space:]]*)[[:space:]]*,?[[:space:]]*$/\\1/p" \
        "$file" 2>/dev/null | head -n 1 || true)
      if [ -n "$val" ] && [ "$val" != "null" ]; then
        echo "$val"
        return 0
      fi
    done
  fi

  echo "$default"
}

# True if value matches any bash glob pattern (case-insensitive).
_pi_matches_any_pattern() {
  local value="$1"
  shift
  local low pat
  low=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  for pat in "$@"; do
    pat=$(printf '%s' "$pat" | tr '[:upper:]' '[:lower:]')
    # shellcheck disable=SC2254
    case "$low" in
      $pat) return 0 ;;
    esac
  done
  return 1
}

# SIGPIPE-safe, locale-safe case-insensitive ERE match against arbitrary text.
# Never `echo "$big" | grep -q`: under pipefail an early-exiting grep fails the pipe.
_pi_text_matches() {
  local text="$1" pat="$2"
  LC_ALL=C grep -qiE -- "$pat" <<<"$text" 2>/dev/null
}

# Model ids are interpolated into CLI invocations; accept only plain id characters.
pi_is_safe_model_id() {
  local m="${1:-}"
  [ -n "$m" ] || return 1
  case "$m" in
    *[!A-Za-z0-9._:/@+\[\]-]*) return 1 ;;
  esac
  return 0
}

# Built-in fallbacks when jq/settings tables unavailable
_PI_BUILTIN_DEFAULT_MODELS_claude="opus"
_PI_BUILTIN_DEFAULT_MODELS_grok="grok-4.7"
_PI_BUILTIN_DEFAULT_MODELS_gemini="gemini-3.8-flash"
_PI_BUILTIN_DEFAULT_MODELS_codex="gpt-6-sol"
_PI_BUILTIN_SUPPORTED_BACKENDS="claude grok gemini codex agy copilot cursor opencode cline qwen droid amp kimi kiro"
_PI_BUILTIN_PREFERRED_BACKENDS="claude codex grok gemini agy copilot cursor opencode cline qwen droid amp kiro"
_PI_BUILTIN_OUTPUT_INSTRUCTIONS="Output ONLY the final improved XML prompt. No explanation, no code fences, no commentary, no execution of the request."

# Strip a leading model:/model= token (any case).
_pi_strip_model_prefix() {
  local raw="$1"
  case "$raw" in
    [Mm][Oo][Dd][Ee][Ll]:*|[Mm][Oo][Dd][Ee][Ll]=*) raw="${raw:6}" ;;
  esac
  printf '%s' "$raw"
}

_builtin_normalize_model_id() {
  local raw m
  raw=$(_pi_strip_model_prefix "${1:-}")
  m=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')

  case "$m" in
    mythos-5.1|mythos5.1|claude-mythos-5-1|mythos) echo "claude-mythos-5-1" ;;
    mythos-5|mythos5|claude-mythos-5) echo "claude-mythos-5" ;;
    mythos-preview|claude-mythos-preview) echo "claude-mythos-preview" ;;
    fable-5.1|fable5.1|claude-fable-5-1) echo "claude-fable-5-1" ;;
    fable-5|fable5|claude-fable-5) echo "claude-fable-5" ;;
    fable) echo "fable" ;;
    opus-5.5|opus5.5|claude-opus-5-5|claude-opus-5.5) echo "claude-opus-5-5" ;;
    opus-5|opus5|claude-opus-5) echo "claude-opus-5" ;;
    opus-4.8|opus4.8|claude-opus-4-8) echo "claude-opus-4-8" ;;
    opus-4.7|opus4.7|claude-opus-4-7) echo "claude-opus-4-7" ;;
    opus-4.6|opus4.6|claude-opus-4-6) echo "claude-opus-4-6" ;;
    opus) echo "opus" ;;
    sonnet-5|sonnet5|claude-sonnet-5) echo "claude-sonnet-5" ;;
    sonnet-4.6|sonnet4.6|claude-sonnet-4-6) echo "claude-sonnet-4-6" ;;
    sonnet) echo "sonnet" ;;
    haiku-4.5|haiku4.5|claude-haiku-4-5|claude-haiku-4.5) echo "claude-haiku-4-5" ;;
    claude-haiku-4-5-20251001) echo "claude-haiku-4-5-20251001" ;;
    haiku) echo "haiku" ;;
    gpt-6-sol|gpt6-sol|sol|gpt-6|gpt6|codex|openai) echo "gpt-6-sol" ;;
    gpt-6-astra|gpt6-astra|astra) echo "gpt-6-astra" ;;
    gpt-6-luna|gpt6-luna|luna) echo "gpt-6-luna" ;;
    gpt-5.6-sol|gpt5.6-sol|gpt-5.6|gpt5.6) echo "gpt-5.6-sol" ;;
    gpt-5.6-terra|gpt5.6-terra|terra) echo "gpt-5.6-terra" ;;
    gpt-5.6-luna|gpt5.6-luna) echo "gpt-5.6-luna" ;;
    gpt-5.5|gpt5.5|gpt-5|gpt5) echo "gpt-5.5" ;;
    gpt-5.3-codex|gpt5.3-codex) echo "gpt-5.3-codex" ;;
    gpt-5.2-codex|gpt5.2-codex) echo "gpt-5.2-codex" ;;
    o4-mini|o4mini) echo "o4-mini" ;;
    grok-4.7|grok4.7|grok) echo "grok-4.7" ;;
    grok-4.6|grok4.6) echo "grok-4.6" ;;
    grok-4.5|grok4.5) echo "grok-4.5" ;;
    grok-4.3|grok4.3) echo "grok-4.3" ;;
    grok-build-0.1|grok-build|grokbuild|grok-code-fast-1|grok-code-fast|composer-2.5-fast|composer2.5-fast|grok-composer-2.5-fast|composer-2.5|composer2.5|grok-composer-2.5) echo "grok-build-0.1" ;;
    gemini-3.8-flash|gemini3.8-flash|gemini-flash|gemini) echo "gemini-3.8-flash" ;;
    gemini-3.7-flash|gemini3.7-flash) echo "gemini-3.7-flash" ;;
    gemini-3.6-flash|gemini3.6-flash) echo "gemini-3.6-flash" ;;
    gemini-3.5-flash|gemini3.5-flash) echo "gemini-3.5-flash" ;;
    gemini-3.5-flash-lite|gemini3.5-flash-lite) echo "gemini-3.5-flash-lite" ;;
    gemini-3.1-flash-lite|gemini3.1-flash-lite) echo "gemini-3.1-flash-lite" ;;
    gemini-3.1-pro-preview|gemini-3.1-pro|gemini3.1-pro|gemini-pro) echo "gemini-3.1-pro-preview" ;;
    gemini-2.5-pro|gemini2.5-pro) echo "gemini-2.5-pro" ;;
    gemini-2.5-flash|gemini2.5-flash) echo "gemini-2.5-flash" ;;
    *) echo "$raw" ;;
  esac
}

# Resolve default generator model for a backend (from settings.default_models or builtins)
get_default_model_for_backend() {
  local backend="$1"
  local val=""

  if [ "$backend" = "openai" ]; then
    backend="codex"
  fi

  if _pi_have_jq; then
    local merged
    merged=$(_pi_merged_object_json "default_models")
    if jq -e --arg b "$backend" 'has($b)' >/dev/null 2>&1 <<<"$merged"; then
      # Explicit entry wins, including null (= leave the CLI's own default).
      val=$(jq -r --arg b "$backend" '.[$b] // empty' <<<"$merged" 2>/dev/null || true)
      echo "$val"
      return 0
    fi
  fi

  case "$backend" in
    claude) echo "$_PI_BUILTIN_DEFAULT_MODELS_claude" ;;
    grok)   echo "$_PI_BUILTIN_DEFAULT_MODELS_grok" ;;
    gemini) echo "$_PI_BUILTIN_DEFAULT_MODELS_gemini" ;;
    codex)  echo "$_PI_BUILTIN_DEFAULT_MODELS_codex" ;;
    *)      echo "" ;;
  esac
}

# Load all common settings into variables
load_settings() {
  local f
  if _pi_have_jq; then
    for f in "$RUNTIME_DEFAULTS" "$DEFAULT_SETTINGS" "$USER_SETTINGS" "$PROJECT_SETTINGS"; do
      if [ -f "$f" ] && ! _pi_json_ok "$f"; then
        echo "WARNING: ignoring malformed settings file: $f" >&2
      fi
    done
  fi

  BACKEND=$(get_setting "backend" "auto")
  MODEL=$(get_setting "model" "")
  MAX_TOKENS=$(get_setting "max_tokens" "12000")
  ENABLE_RESEARCH=$(get_setting "enable_research" "true")
  ENABLE_THINKING=$(get_setting "enable_thinking" "true")
  HEADLESS_ONLY=$(get_setting "headless_only" "true")
  FALLBACK_STRATEGY=$(get_setting "fallback_strategy" "manual")
  PREFERRED_BACKENDS=$(get_setting "preferred_backends" "")
  CUSTOM_COMMAND=$(get_setting "custom_command" "")
  ALLOW_WEB_SEARCH=$(get_setting "allow_web_search" "true")
  ALLOW_CODE_EXECUTION=$(get_setting "allow_code_execution_in_generation" "false")
  SKIP_VALIDATE=$(get_setting "skip_validate" "false")
  BACKEND_INVOCATION=$(get_setting "backend_invocation" "scripts")

  local _backend_timeout="" _grok_timeout="" _grok_turns=""

  # Generation materials / output (nested generation object, with flat env overrides)
  if _pi_have_jq; then
    local _gen
    _gen=$(_pi_merged_object_json "generation")
    # Note: jq `//` treats false as missing — use explicit null checks for booleans
    CONTEXT_MODE=$(jq -r 'if .context_mode == null then "deterministic" else .context_mode end' <<<"$_gen")
    GEN_INCLUDE_XML=$(jq -r 'if .include_xml_template == null then true else .include_xml_template end' <<<"$_gen")
    GEN_INCLUDE_PRINCIPLES=$(jq -r 'if .include_principles == null then true else .include_principles end' <<<"$_gen")
    GEN_INCLUDE_CHAINING=$(jq -r 'if .include_chaining == null then true else .include_chaining end' <<<"$_gen")
    GEN_INCLUDE_EXAMPLES=$(jq -r 'if .include_examples == null then true else .include_examples end' <<<"$_gen")
    GEN_INCLUDE_SYSTEM=$(jq -r 'if .include_system_prompt == null then true else .include_system_prompt end' <<<"$_gen")
    GEN_SYSTEM_PATH=$(jq -r 'if .system_prompt_path == null then "assets/generation-agent-prompt.md" else .system_prompt_path end' <<<"$_gen")
    GEN_XML_PATH=$(jq -r 'if .xml_template_path == null then "references/xml-template.md" else .xml_template_path end' <<<"$_gen")
    GEN_PRINCIPLES_PATH=$(jq -r 'if .principles_path == null then "references/prompting-principles.md" else .principles_path end' <<<"$_gen")
    GEN_CHAINING_PATH=$(jq -r 'if .chaining_path == null then "references/prompt-chaining.md" else .chaining_path end' <<<"$_gen")
    GEN_EXAMPLES_PATH=$(jq -r 'if .examples_path == null then "examples/before-after.md" else .examples_path end' <<<"$_gen")
    GEN_OUTPUT_INSTRUCTIONS=$(jq -r --arg d "$_PI_BUILTIN_OUTPUT_INSTRUCTIONS" 'if .output_instructions == null then $d else .output_instructions end' <<<"$_gen")
    GEN_REQUIRE_XML=$(jq -r 'if .require_xml_output == null then true else .require_xml_output end' <<<"$_gen")
    GEN_FORBID_AGENT_SEARCH=$(jq -r 'if .forbid_agent_codebase_search == null then true else .forbid_agent_codebase_search end' <<<"$_gen")
    GEN_EXTRA_REFS=$(jq -c 'if .extra_reference_paths == null then [] else .extra_reference_paths end' <<<"$_gen")
    _backend_timeout=$(jq -r 'if .backend_timeout_secs == null then empty else .backend_timeout_secs end' <<<"$_gen")
    _grok_timeout=$(jq -r 'if .grok_timeout_secs == null then empty else .grok_timeout_secs end' <<<"$_gen")
    _grok_turns=$(jq -r 'if .grok_max_turns == null then empty else .grok_max_turns end' <<<"$_gen")
  else
    CONTEXT_MODE="deterministic"
    GEN_INCLUDE_XML="true"
    GEN_INCLUDE_PRINCIPLES="true"
    GEN_INCLUDE_CHAINING="true"
    GEN_INCLUDE_EXAMPLES="true"
    GEN_INCLUDE_SYSTEM="true"
    GEN_SYSTEM_PATH="assets/generation-agent-prompt.md"
    GEN_XML_PATH="references/xml-template.md"
    GEN_PRINCIPLES_PATH="references/prompting-principles.md"
    GEN_CHAINING_PATH="references/prompt-chaining.md"
    GEN_EXAMPLES_PATH="examples/before-after.md"
    GEN_OUTPUT_INSTRUCTIONS="$_PI_BUILTIN_OUTPUT_INSTRUCTIONS"
    GEN_REQUIRE_XML="true"
    GEN_FORBID_AGENT_SEARCH="true"
    GEN_EXTRA_REFS="[]"
    _backend_timeout=300
    _grok_timeout=180
    _grok_turns=3
  fi

  BACKEND="${PROMPT_IMPROVER_BACKEND:-$BACKEND}"
  MODEL="${PROMPT_IMPROVER_MODEL:-$MODEL}"
  MAX_TOKENS="${PROMPT_IMPROVER_MAX_TOKENS:-$MAX_TOKENS}"
  ENABLE_RESEARCH="${PROMPT_IMPROVER_ENABLE_RESEARCH:-$ENABLE_RESEARCH}"
  ENABLE_THINKING="${PROMPT_IMPROVER_ENABLE_THINKING:-$ENABLE_THINKING}"
  HEADLESS_ONLY="${PROMPT_IMPROVER_HEADLESS_ONLY:-$HEADLESS_ONLY}"
  FALLBACK_STRATEGY="${PROMPT_IMPROVER_FALLBACK_STRATEGY:-$FALLBACK_STRATEGY}"
  CUSTOM_COMMAND="${PROMPT_IMPROVER_CUSTOM_COMMAND:-$CUSTOM_COMMAND}"
  ALLOW_WEB_SEARCH="${PROMPT_IMPROVER_ALLOW_WEB_SEARCH:-$ALLOW_WEB_SEARCH}"
  ALLOW_CODE_EXECUTION="${PROMPT_IMPROVER_ALLOW_CODE_EXECUTION:-$ALLOW_CODE_EXECUTION}"
  SKIP_VALIDATE="${PROMPT_IMPROVER_SKIP_VALIDATE:-$SKIP_VALIDATE}"
  BACKEND_INVOCATION="${PROMPT_IMPROVER_BACKEND_INVOCATION:-$BACKEND_INVOCATION}"
  CONTEXT_MODE="${PROMPT_IMPROVER_CONTEXT_MODE:-$CONTEXT_MODE}"

  if [ "$MODEL" = "null" ]; then MODEL=""; fi
  if [ "$CUSTOM_COMMAND" = "null" ]; then CUSTOM_COMMAND=""; fi
  BACKEND=$(printf '%s' "$BACKEND" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  [ -z "$BACKEND" ] && BACKEND="auto"

  export PROMPT_IMPROVER_MAX_TOKENS="$MAX_TOKENS"
  export CONTEXT_MODE GEN_INCLUDE_XML GEN_INCLUDE_PRINCIPLES GEN_INCLUDE_CHAINING \
    GEN_INCLUDE_EXAMPLES GEN_INCLUDE_SYSTEM GEN_SYSTEM_PATH GEN_XML_PATH \
    GEN_PRINCIPLES_PATH GEN_CHAINING_PATH GEN_EXAMPLES_PATH GEN_OUTPUT_INSTRUCTIONS \
    GEN_REQUIRE_XML GEN_FORBID_AGENT_SEARCH GEN_EXTRA_REFS

  # Timeouts read by scripts/lib/backend-common.sh (env always wins).
  if [ -n "$_backend_timeout" ]; then
    export PROMPT_IMPROVER_BACKEND_TIMEOUT="${PROMPT_IMPROVER_BACKEND_TIMEOUT:-$_backend_timeout}"
  fi
  if [ -n "$_grok_timeout" ]; then
    export PROMPT_IMPROVER_GROK_TIMEOUT="${PROMPT_IMPROVER_GROK_TIMEOUT:-$_grok_timeout}"
  fi
  if [ -n "$_grok_turns" ]; then
    export PROMPT_IMPROVER_GROK_MAX_TURNS="${PROMPT_IMPROVER_GROK_MAX_TURNS:-$_grok_turns}"
  fi
  return 0
}

# Resolve a path relative to skill root unless absolute.
_pi_resolve_skill_path() {
  local p="$1"
  local root="${2:-$_PI_ROOT_DIR}"
  if [ -z "$p" ] || [ "$p" = "null" ]; then
    echo ""
    return 0
  fi
  case "$p" in
    /*) echo "$p" ;;
    *) echo "$root/$p" ;;
  esac
}

resolve_generator_model() {
  local backend="$1"
  if [ -n "$MODEL" ]; then
    echo "$MODEL"
    return 0
  fi
  get_default_model_for_backend "$backend"
}

normalize_model_id() {
  local raw m mapped
  raw=$(_pi_strip_model_prefix "${1:-}")
  m=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')

  if _pi_have_jq; then
    local aliases
    aliases=$(_pi_merged_object_json "model_aliases")
    mapped=$(jq -r --arg k "$m" '.[$k] // empty' <<<"$aliases" 2>/dev/null || true)
    if [ -n "$mapped" ] && [ "$mapped" != "null" ]; then
      echo "$mapped"
      return 0
    fi
  fi

  _builtin_normalize_model_id "$raw"
}

infer_backend_for_model() {
  local low
  low=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')
  [ -z "$low" ] && { echo ""; return 0; }

  if _pi_have_jq; then
    local patterns_json count i pat backend
    patterns_json=$(_pi_first_array_json "model_backend_patterns")
    count=$(jq 'length' <<<"$patterns_json" 2>/dev/null || echo 0)
    for ((i = 0; i < count; i++)); do
      backend=$(jq -r ".[$i].backend // empty" <<<"$patterns_json")
      while IFS= read -r pat; do
        [ -z "$pat" ] && continue
        if _pi_matches_any_pattern "$low" "$pat"; then
          echo "$backend"
          return 0
        fi
      done < <(jq -r ".[$i].patterns[]?" <<<"$patterns_json")
    done
    if [ "$count" -gt 0 ]; then
      echo ""
      return 0
    fi
  fi

  case "$low" in
    mythos*|fable*|claude-*|sonnet*|haiku*|opus*|claude) echo "claude" ;;
    grok*|composer*) echo "grok" ;;
    gemini*) echo "gemini" ;;
    gpt*|o1*|o3*|o4*|codex*|openai|chatgpt*|sol|terra|luna|astra) echo "codex" ;;
    *) echo "" ;;
  esac
}

# Ordered model ids to try on the model's own CLI. Every shipped chain starts
# with the requested id ($primary), so a pinned version is always tried first.
get_model_fallback_chain() {
  local primary low item pat
  primary=$(normalize_model_id "${1:-}")
  low=$(printf '%s' "$primary" | tr '[:upper:]' '[:lower:]')
  [ -z "$primary" ] && return 0

  if _pi_have_jq; then
    local chains_json count i
    chains_json=$(_pi_first_array_json "model_fallback_chains")
    count=$(jq 'length' <<<"$chains_json" 2>/dev/null || echo 0)
    for ((i = 0; i < count; i++)); do
      local matched=false
      while IFS= read -r pat; do
        [ -z "$pat" ] && continue
        if _pi_matches_any_pattern "$low" "$pat"; then
          matched=true
          break
        fi
      done < <(jq -r ".[$i].patterns[]?" <<<"$chains_json")
      if [ "$matched" = true ]; then
        while IFS= read -r item; do
          [ -z "$item" ] && continue
          if [ "$item" = '$primary' ]; then
            echo "$primary"
          else
            echo "$item"
          fi
        done < <(jq -r ".[$i].chain[]?" <<<"$chains_json")
        return 0
      fi
    done
    if [ "$count" -gt 0 ]; then
      echo "$primary"
      return 0
    fi
  fi

  case "$low" in
    *mythos*) echo "$primary claude-mythos-5-1 claude-mythos-5 fable opus sonnet" ;;
    *fable*) echo "$primary fable opus sonnet" ;;
    *opus*) echo "$primary opus sonnet" ;;
    *sonnet*) echo "$primary sonnet" ;;
    *haiku*) echo "$primary haiku sonnet" ;;
    gpt-6*) echo "$primary gpt-6-sol gpt-6-luna gpt-5.6-terra gpt-5.5" ;;
    gpt-5.6*) echo "$primary gpt-6-sol gpt-5.6-terra gpt-5.6-luna gpt-5.5" ;;
    *codex*|gpt-5*|o[0-9]*) echo "$primary gpt-6-sol gpt-6-luna" ;;
    grok-4*) echo "$primary grok-4.7 grok-4.6 grok-4.5" ;;
    grok*) echo "$primary grok-4.7" ;;
    *gemini*pro*) echo "$primary gemini-3.1-pro-preview gemini-3.8-flash gemini-2.5-pro" ;;
    *gemini*flash*) echo "$primary gemini-3.8-flash gemini-3.7-flash gemini-2.5-flash" ;;
    gemini*) echo "$primary gemini-3.8-flash" ;;
    *) echo "$primary" ;;
  esac
}

_pi_limit_pattern() {
  local field="$1"
  local default="$2"
  if _pi_have_jq; then
    local merged pat
    merged=$(_pi_merged_object_json "limit_detection")
    pat=$(jq -r --arg f "$field" '.[$f] // empty' <<<"$merged" 2>/dev/null || true)
    if [ -n "$pat" ] && [ "$pat" != "null" ]; then
      echo "$pat"
      return 0
    fi
  fi
  echo "$default"
}

is_account_limit_failure() {
  local output="$1"
  local pat
  [ -z "$output" ] && return 1
  pat=$(_pi_limit_pattern "account_patterns" \
    'weekly.?limit|monthly.?limit|session limit|spend limit|hit your .*limit|you.?ve hit your|you have hit your|you.?ve reached your|organization.?limit|org.?limit|account.?limit|individual usage limit|out of (usage|credits)|usage.?limit.?reached|credit balance is too low|exhausted your daily quota|grok build usage limit|upgrade to (plus|pro|supergrok)|limit · resets|limit · reset')
  _pi_text_matches "$output" "$pat"
}

is_model_retryable_failure() {
  local exit_code="$1"
  local output="$2"
  local pat

  if is_account_limit_failure "$output"; then
    return 0
  fi

  pat=$(_pi_limit_pattern "retry_patterns" \
    'rate.?limit|usage.?limit|quota|out of (limit|usage|credits)|capacity|overloaded|(^|[^0-9])(401|403|429|503|529)([^0-9]|$)|not (available|supported|enabled) (for|on|with|in)|model .*not found|unknown model|invalid model|not a (recognized|valid) model|model .* (denied|restricted|not accessible)|restricted by your organization|access denied|does not have access|not available with the|invitation|glasswing|temporarily (unavailable|limiting)|service unavailable|try again (later|at)|too many requests|resource.?exhausted|throttl|not supported when using codex')
  if _pi_text_matches "$output" "$pat"; then
    return 0
  fi

  # A non-zero exit whose output merely contains the word "model" is not evidence of
  # a limit — "model" appears in ordinary prose and in generated prompts. Require an
  # explicit bad-model signal, or genuine backend errors get retried as limit failures.
  if [ "$exit_code" -ne 0 ] && _pi_text_matches "$output" '(unknown|invalid|unsupported|unrecognized|no such|nonexistent) model|model [^[:space:]]* ?(not found|does not exist|not exist|unsupported|unavailable|denied|restricted)'; then
    return 0
  fi

  return 1
}

# True when the output is a limit/access message rather than a generated prompt.
# Any line that opens with an XML element marks real generator output.
is_rate_limit_message_only() {
  local output="$1"
  local xml_pat
  [ -z "$output" ] && return 1
  xml_pat=$(_pi_limit_pattern "xml_markers" '^[[:space:]]*<[A-Za-z][A-Za-z0-9_-]*[[:space:]>/]')
  if _pi_text_matches "$output" "$xml_pat"; then
    return 1
  fi
  is_model_retryable_failure 1 "$output"
}

# Executable(s) for a backend, in preference order (default: the backend name).
_pi_backend_binaries() {
  local backend="$1"
  [ "$backend" = "openai" ] && backend="codex"
  if _pi_have_jq; then
    local bins
    bins=$(_pi_merged_object_json "backend_binaries" | jq -r --arg b "$backend" '.[$b] // empty | if type == "array" then .[] else . end' 2>/dev/null || true)
    if [ -n "$bins" ]; then
      echo "$bins"
      return 0
    fi
  fi
  case "$backend" in
    cursor) printf '%s\n' cursor-agent agent ;;
    kiro)   printf '%s\n' kiro-cli kiro ;;
    *)      echo "$backend" ;;
  esac
}

# First installed executable for a backend; non-zero when none is on PATH.
pi_backend_binary() {
  local bin
  while IFS= read -r bin; do
    [ -z "$bin" ] && continue
    if command -v "$bin" >/dev/null 2>&1; then
      echo "$bin"
      return 0
    fi
  done < <(_pi_backend_binaries "$1")
  return 1
}

pi_backend_available() {
  pi_backend_binary "$1" >/dev/null
}

prefer_backend_if_available() {
  local want="$1"
  local current="$2"

  if [ -z "$want" ]; then
    echo "$current"
    return 0
  fi
  if [ "$want" = "openai" ]; then
    want="codex"
  fi
  if pi_backend_available "$want"; then
    echo "$want"
    return 0
  fi
  if [ -n "$current" ] && [ "$current" != "unknown" ] && [ "$current" != "auto" ]; then
    echo "WARNING: model wants backend '$want' but CLI not on PATH; using '$current'." >&2
    echo "$current"
    return 0
  fi
  echo "$want"
}

# Supported backends, one per line, in table order.
_pi_supported_backends_list() {
  local list=""
  if _pi_have_jq; then
    list=$(_pi_first_array_json "supported_backends" | jq -r '.[]?' 2>/dev/null || true)
  fi
  if [ -z "$list" ]; then
    list=$(printf '%s\n' $_PI_BUILTIN_SUPPORTED_BACKENDS)
  fi
  echo "$list"
}

_pi_host_from_env() {
  local backend var
  if _pi_have_jq; then
    local markers
    markers=$(_pi_merged_object_json "host_env_markers")
    # Iterate in supported_backends order — jq `keys` would sort alphabetically.
    while IFS= read -r backend; do
      [ -z "$backend" ] && continue
      while IFS= read -r var; do
        case "$var" in
          ''|[0-9]*|*[!A-Za-z0-9_]*) continue ;;
        esac
        if [ -n "${!var:-}" ]; then
          echo "$backend"
          return 0
        fi
      done < <(jq -r --arg b "$backend" '.[$b] // empty | .[]?' <<<"$markers" 2>/dev/null)
    done < <(_pi_supported_backends_list)
    return 1
  fi
  if [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ] || \
     [ -n "${CLAUDE_CODE:-}" ] || [ -n "${CLAUDE_AGENT:-}" ]; then
    echo "claude"; return 0
  fi
  if [ -n "${GROK_BUILD:-}" ] || [ -n "${XAI_GROK:-}" ] || [ -n "${GROK_SESSION:-}" ]; then
    echo "grok"; return 0
  fi
  if [ -n "${GEMINI_CLI:-}" ] || [ -n "${GOOGLE_GEMINI_CLI:-}" ]; then
    echo "gemini"; return 0
  fi
  if [ -n "${CODEX_SANDBOX:-}" ] || [ -n "${CODEX_MANAGED_BY_NPM:-}" ] || [ -n "${OPENAI_CODEX:-}" ]; then
    echo "codex"; return 0
  fi
  if [ -n "${QWEN_CODE:-}" ]; then
    echo "qwen"; return 0
  fi
  return 1
}

# Backend whose process-name patterns match any of the given names.
_pi_backend_for_process_names() {
  local backend pat name
  if _pi_have_jq; then
    local proc_patterns
    proc_patterns=$(_pi_merged_object_json "parent_process_patterns")
    while IFS= read -r backend; do
      [ -z "$backend" ] && continue
      while IFS= read -r pat; do
        [ -z "$pat" ] && continue
        for name in "$@"; do
          [ -z "$name" ] && continue
          if _pi_matches_any_pattern "$name" "$pat"; then
            echo "$backend"
            return 0
          fi
        done
      done < <(jq -r --arg b "$backend" '.[$b] // empty | .[]?' <<<"$proc_patterns" 2>/dev/null)
    done < <(_pi_supported_backends_list)
    return 1
  fi
  for name in "$@"; do
    case "$name" in
      claude|claude-*|*claude*) echo "claude"; return 0 ;;
      grok|grok-*|*grok*)       echo "grok"; return 0 ;;
      gemini|gemini-*|*gemini*) echo "gemini"; return 0 ;;
      codex|codex-*|*codex*)    echo "codex"; return 0 ;;
      agy|antigravity*)         echo "agy"; return 0 ;;
      copilot|copilot-*)        echo "copilot"; return 0 ;;
      cursor-agent*)            echo "cursor"; return 0 ;;
      opencode|opencode-*)      echo "opencode"; return 0 ;;
      cline|cline-*)            echo "cline"; return 0 ;;
      qwen|qwen-*)              echo "qwen"; return 0 ;;
      droid|droid-*)            echo "droid"; return 0 ;;
      amp)                      echo "amp"; return 0 ;;
      kimi|kimi-*)              echo "kimi"; return 0 ;;
      kiro|kiro-*|kiro-cli*)    echo "kiro"; return 0 ;;
    esac
  done
  return 1
}

detect_host_backend() {
  local explicit pid comm args a1 a2 i found

  explicit=$(printf '%s' "${PROMPT_IMPROVER_HOST:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  if [ -n "$explicit" ]; then
    [ "$explicit" = "openai" ] && explicit="codex"
    echo "$explicit"
    return 0
  fi

  if found=$(_pi_host_from_env) && [ -n "$found" ]; then
    echo "$found"
    return 0
  fi

  # Walk up the process tree. `comm` is truncated (15 chars on Linux) and is just
  # `node` for npm-installed CLIs, so also check the basenames of the first two
  # argv words (`node /usr/lib/node_modules/.bin/claude`).
  pid="${PPID:-}"
  i=0
  while [ "$i" -lt 8 ] && [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d '[:space:]' || true)
    args=$(ps -o args= -p "$pid" 2>/dev/null || true)
    a1=""; a2=""
    local w1="" w2=""
    read -r w1 w2 _ <<<"$args" || true
    [ -n "$w1" ] && a1=$(basename -- "$w1" 2>/dev/null || true)
    case "$w2" in
      ''|-*) ;;
      *) a2=$(basename -- "$w2" 2>/dev/null || true) ;;
    esac
    comm=$(basename -- "${comm:-x}" 2>/dev/null || true)
    if found=$(_pi_backend_for_process_names "$comm" "$a1" "$a2") && [ -n "$found" ]; then
      echo "$found"
      return 0
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d '[:space:]' || true)
    i=$((i + 1))
  done

  echo ""
}

is_supported_backend() {
  local b="$1"
  [ "$b" = "openai" ] && b="codex"
  [ -z "$b" ] && return 1
  local list
  list=$(_pi_supported_backends_list)
  grep -qxF -- "$b" <<<"$list" 2>/dev/null
}

detect_backend() {
  local b scan
  for b in "$@"; do
    [ "$b" = "openai" ] && b="codex"
    if pi_backend_available "$b"; then
      echo "$b"
      return 0
    fi
  done

  if _pi_have_jq; then
    while IFS= read -r scan; do
      [ -z "$scan" ] && continue
      [ "$scan" = "openai" ] && scan="codex"
      if pi_backend_available "$scan"; then
        echo "$scan"
        return 0
      fi
    done < <(_pi_first_array_json "cascade_scan_order" | jq -r '.[]?')
  fi

  for b in $_PI_BUILTIN_SUPPORTED_BACKENDS; do
    if pi_backend_available "$b"; then
      echo "$b"
      return 0
    fi
  done

  echo "unknown"
}

# preferred_backends as whitespace-separated names (only [A-Za-z0-9_-] kept).
parse_preferred_backends() {
  local items="" line

  if _pi_have_jq && jq -e 'type == "array"' >/dev/null 2>&1 <<<"$PREFERRED_BACKENDS"; then
    while IFS= read -r line; do
      [ -n "$line" ] && items="$items $line"
    done < <(jq -r '.[] | strings' <<<"$PREFERRED_BACKENDS" 2>/dev/null)
  fi

  if [ -z "${items// /}" ]; then
    items=$(printf '%s' "$PREFERRED_BACKENDS" | tr -d '[]"' | tr ',' ' ')
  fi

  if [ -z "${items// /}" ]; then
    items="$_PI_BUILTIN_PREFERRED_BACKENDS"
  fi

  printf '%s' "$items" | tr -c 'A-Za-z0-9_\n -' ' ' | tr -s ' \n' ' ' | sed 's/^ //; s/ $//'
  echo
}

# Build model args token for backend command templates. The model is
# shell-quoted: templates are eval'd.
_pi_model_args_for_backend() {
  local backend="$1"
  local model="$2"
  local flag_tpl="" quoted

  [ "$backend" = "openai" ] && backend="codex"
  [ -z "$model" ] && { echo ""; return 0; }
  quoted=$(printf '%q' "$model")

  if _pi_have_jq; then
    local flags
    flags=$(_pi_merged_object_json "backend_model_flags")
    if jq -e --arg b "$backend" 'has($b)' >/dev/null 2>&1 <<<"$flags"; then
      flag_tpl=$(jq -r --arg b "$backend" '.[$b] // empty' <<<"$flags" 2>/dev/null || true)
      echo "${flag_tpl//\{model\}/$quoted}"
      return 0
    fi
  fi

  case "$backend" in
    claude|agy|copilot|cursor|kiro) echo "--model $quoted" ;;
    grok|gemini|codex|opencode|cline|qwen|droid|kimi) echo "-m $quoted" ;;
    *) echo "" ;;
  esac
}

get_backend_command() {
  local backend="$1"
  local prompt_file="$2"
  local model="${3:-${PROMPT_IMPROVER_MODEL:-}}"
  local tpl model_args rendered quoted=""

  [ "$backend" = "openai" ] && backend="codex"
  model_args=$(_pi_model_args_for_backend "$backend" "$model")
  [ -n "$model" ] && quoted=$(printf '%q' "$model")

  if _pi_have_jq; then
    local cmds
    cmds=$(_pi_merged_object_json "backend_commands")
    tpl=$(jq -r --arg b "$backend" '.[$b] // empty' <<<"$cmds" 2>/dev/null || true)
  fi

  if [ -z "${tpl:-}" ] || [ "$tpl" = "null" ]; then
    case "$backend" in
      claude)   tpl='claude -p "$(cat "{prompt_file}")" --tools "" --output-format text --no-session-persistence --permission-mode dontAsk {model_args} </dev/null' ;;
      grok)     tpl='grok -p "$(cat "{prompt_file}")" --output-format plain --always-approve --no-subagents --no-plan --disable-web-search --max-turns 3 {model_args} </dev/null' ;;
      gemini)   tpl='gemini -p "$(cat "{prompt_file}")" --output-format text --approval-mode default {model_args} </dev/null' ;;
      codex)    tpl='codex exec --sandbox read-only --skip-git-repo-check --ephemeral --color never {model_args} - <"{prompt_file}"' ;;
      agy)      tpl='agy -p "$(cat "{prompt_file}")" --output-format text {model_args} </dev/null' ;;
      copilot)  tpl='copilot -p "$(cat "{prompt_file}")" -s --no-ask-user --deny-tool shell --deny-tool write {model_args} </dev/null' ;;
      cursor)   tpl='cursor-agent -p "$(cat "{prompt_file}")" --mode ask --output-format text {model_args} </dev/null' ;;
      opencode) tpl='opencode run {model_args} "$(cat "{prompt_file}")" </dev/null' ;;
      cline)    tpl='cline --plan -y {model_args} "$(cat "{prompt_file}")" </dev/null' ;;
      qwen)     tpl='qwen -p "$(cat "{prompt_file}")" --output-format text --approval-mode default {model_args} </dev/null' ;;
      droid)    tpl='droid exec -f "{prompt_file}" {model_args} </dev/null' ;;
      amp)      tpl='amp -x <"{prompt_file}"' ;;
      kimi)     tpl='kimi -p "$(cat "{prompt_file}")" --output-format text {model_args} </dev/null' ;;
      kiro)     tpl='kiro-cli chat --no-interactive {model_args} "$(cat "{prompt_file}")" </dev/null' ;;
      *)        echo ""; return 0 ;;
    esac
  fi

  rendered="${tpl//\{prompt_file\}/$prompt_file}"
  rendered="${rendered//\{model_args\}/$model_args}"
  rendered="${rendered//\{model\}/$quoted}"
  rendered="${rendered//\{max_tokens\}/${MAX_TOKENS:-12000}}"
  echo "$rendered"
}

# True when user/project settings define a backend_commands entry for this backend.
_pi_has_backend_command_override() {
  local backend="$1"
  local file
  [ "$backend" = "openai" ] && backend="codex"
  for file in "$PROJECT_SETTINGS" "$USER_SETTINGS"; do
    [ -f "$file" ] || continue
    if _pi_have_jq; then
      if jq -e --arg b "$backend" '.backend_commands[$b] // empty | type == "string" and length > 0' "$file" >/dev/null 2>&1; then
        return 0
      fi
    fi
  done
  return 1
}

# Whether to invoke backend via scripts/*.sh or settings backend_commands template.
should_use_backend_script() {
  local backend="$1"
  case "${BACKEND_INVOCATION:-scripts}" in
    commands) return 1 ;;
    scripts) return 0 ;;
    auto|*)
      if _pi_has_backend_command_override "$backend"; then
        return 1
      fi
      return 0
      ;;
  esac
}

# Settings-driven overlay appended to the assembled generator prompt.
get_generation_settings_overlay() {
  cat <<EOF
=== RUNTIME SETTINGS (from prompt-improver config) ===
enable_research: $ENABLE_RESEARCH
enable_thinking: $ENABLE_THINKING
allow_web_search: $ALLOW_WEB_SEARCH
allow_code_execution_in_generation: $ALLOW_CODE_EXECUTION
max_tokens: $MAX_TOKENS
headless_only: $HEADLESS_ONLY
context_mode: ${CONTEXT_MODE:-deterministic}
forbid_agent_codebase_search: ${GEN_FORBID_AGENT_SEARCH:-true}
require_xml_output: ${GEN_REQUIRE_XML:-true}

Apply these settings when building the improved prompt:
- When enable_research is false, omit or minimize <research> blocks unless the raw request explicitly requires external lookup.
- When enable_thinking is false, omit <approach> think-then-act blocks unless strictly necessary for safety.
- When allow_web_search is false, do not instruct the executor to search the web.
- Context is pre-gathered by the shell (deterministic). When forbid_agent_codebase_search is true (default), you MUST NOT grep, glob, find, list, or search the repo — use ONLY the DETERMINISTIC PROJECT CONTEXT block.
- When allow_code_execution_in_generation is false, do not run shell tools during generation.
- When require_xml_output is true, return only the improved XML prompt body.
- Respect max_tokens as a soft cap on output length when the backend supports it.
EOF
}

export -f load_settings get_setting detect_backend detect_host_backend is_supported_backend \
  get_backend_command parse_preferred_backends get_generation_settings_overlay should_use_backend_script \
  get_default_model_for_backend resolve_generator_model normalize_model_id infer_backend_for_model \
  prefer_backend_if_available get_model_fallback_chain is_model_retryable_failure \
  is_account_limit_failure is_rate_limit_message_only _pi_resolve_skill_path \
  pi_set_project_dir pi_is_safe_model_id pi_backend_binary pi_backend_available
