#!/usr/bin/env bash
# scripts/lib/settings.sh
# Loads prompt-improver settings with sensible defaults and overrides.
# Priority: env vars > project settings > user settings > shipped default > runtime-defaults
#
# IMPORTANT: This file must not overwrite the caller's SCRIPT_DIR.
# It uses PI_* names for its own path resolution.

set -euo pipefail

_PI_SETTINGS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PI_ROOT_DIR="$(cd "$_PI_SETTINGS_DIR/../.." && pwd)"

CONFIG_DIR="${PROMPT_IMPROVER_CONFIG_DIR:-$HOME/.config/prompt-improver}"
PROJECT_CONFIG_DIR="${PROMPT_IMPROVER_PROJECT_CONFIG_DIR:-.prompt-improver}"

RUNTIME_DEFAULTS="$_PI_ROOT_DIR/config/runtime-defaults.json"
DEFAULT_SETTINGS="$_PI_ROOT_DIR/config/settings.default.json"
USER_SETTINGS="$CONFIG_DIR/settings.json"
PROJECT_SETTINGS="$PROJECT_CONFIG_DIR/settings.json"

# Collect settings JSON files in merge order (later layers override earlier for scalars/objects).
_pi_settings_files_ordered() {
  local f
  for f in "$RUNTIME_DEFAULTS" "$DEFAULT_SETTINGS" "$USER_SETTINGS" "$PROJECT_SETTINGS"; do
    [ -f "$f" ] && echo "$f"
  done
}

# Merge a top-level object key across all settings layers (later wins on key collision).
_pi_merged_object_json() {
  local key="$1"
  if ! command -v jq >/dev/null 2>&1; then
    echo "{}"
    return 0
  fi
  local files=()
  while IFS= read -r f; do files+=("$f"); done < <(_pi_settings_files_ordered)
  if [ "${#files[@]}" -eq 0 ]; then
    echo "{}"
    return 0
  fi
  jq -s --arg k "$key" '[.[] | .[$k] // {}] | add' "${files[@]}"
}

# First defined non-empty array at project > user > default > runtime.
_pi_first_array_json() {
  local key="$1"
  local file val
  for file in "$PROJECT_SETTINGS" "$USER_SETTINGS" "$DEFAULT_SETTINGS" "$RUNTIME_DEFAULTS"; do
    [ -f "$file" ] || continue
    if command -v jq >/dev/null 2>&1; then
      val=$(jq -c --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null || true)
      if [ -n "$val" ] && [ "$val" != "null" ] && [ "$val" != "[]" ]; then
        echo "$val"
        return 0
      fi
    fi
  done
  echo "[]"
}

# Simple JSON getter using jq if available, else basic grep (limited)
get_setting() {
  local key="$1"
  local default="${2:-}"
  local file val

  for file in "$PROJECT_SETTINGS" "$USER_SETTINGS" "$DEFAULT_SETTINGS" "$RUNTIME_DEFAULTS"; do
    if [ -f "$file" ]; then
      if command -v jq >/dev/null 2>&1; then
        val=$(jq -r --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null || true)
        if [ -n "$val" ] && [ "$val" != "null" ]; then
          echo "$val"
          return 0
        fi
      else
        val=$(grep -o "\"$key\"[[:space:]]*:[[:space:]]*[^,}]*" "$file" | head -1 | sed -E 's/.*:[[:space:]]*//; s/[",]//g' || true)
        if [ -n "$val" ]; then
          echo "$val"
          return 0
        fi
      fi
    fi
  done

  echo "$default"
}

# True if value matches any bash glob pattern (lowercased).
_pi_matches_any_pattern() {
  local value="$1"
  shift
  local low pat
  low=$(echo "$value" | tr '[:upper:]' '[:lower:]')
  for pat in "$@"; do
    pat=$(echo "$pat" | tr '[:upper:]' '[:lower:]')
    case "$low" in
      $pat) return 0 ;;
    esac
  done
  return 1
}

# Built-in fallbacks when jq/settings tables unavailable
_PI_BUILTIN_DEFAULT_MODELS_claude="sonnet"
_PI_BUILTIN_DEFAULT_MODELS_grok="grok-composer-2.5-fast"
_PI_BUILTIN_DEFAULT_MODELS_gemini="gemini-2.5-pro"
_PI_BUILTIN_DEFAULT_MODELS_codex="gpt-5.5"

_builtin_normalize_model_id() {
  local raw="${1:-}"
  local m
  m=$(echo "$raw" | tr '[:upper:]' '[:lower:]' | sed 's/^model://; s/^model=//')

  case "$m" in
    mythos-5|mythos5|claude-mythos-5) echo "claude-mythos-5" ;;
    mythos-preview|claude-mythos-preview|mythos) echo "claude-mythos-preview" ;;
    fable-5|fable5|claude-fable-5) echo "claude-fable-5" ;;
    fable) echo "fable" ;;
    sonnet-5|claude-sonnet-5) echo "claude-sonnet-5" ;;
    sonnet) echo "sonnet" ;;
    haiku-4.5|haiku4.5|claude-haiku-4-5|claude-haiku-4.5) echo "haiku" ;;
    haiku) echo "haiku" ;;
    opus-4.8|claude-opus-4-8) echo "claude-opus-4-8" ;;
    opus-4.6|claude-opus-4-6) echo "claude-opus-4-6" ;;
    opus) echo "opus" ;;
    gpt-5.6-sol|gpt5.6-sol|sol) echo "gpt-5.6-sol" ;;
    gpt-5.6-terra|gpt5.6-terra|terra) echo "gpt-5.6-terra" ;;
    gpt-5.6-luna|gpt5.6-luna|luna) echo "gpt-5.6-luna" ;;
    gpt-5.6|gpt5.6) echo "gpt-5.6-sol" ;;
    gpt5.5|gpt-5.5) echo "gpt-5.5" ;;
    gpt5|gpt-5) echo "gpt-5.5" ;;
    gpt-5.3-codex|gpt5.3-codex) echo "gpt-5.3-codex" ;;
    gpt-5.2-codex|gpt5.2-codex) echo "gpt-5.2-codex" ;;
    codex|openai) echo "gpt-5.5" ;;
    o4-mini|o4mini) echo "o4-mini" ;;
    grok-4.5|grok4.5) echo "grok-4.5" ;;
    grok-4.3|grok4.3) echo "grok-4.3" ;;
    composer-2.5-fast|composer2.5-fast|grok-composer-2.5-fast) echo "grok-composer-2.5-fast" ;;
    composer-2.5|composer2.5|grok-composer-2.5) echo "grok-composer-2.5-fast" ;;
    grok-build|grokbuild|grok-build-0.1) echo "grok-build" ;;
    grok-code-fast-1) echo "grok-code-fast-1" ;;
    gemini-2.5-pro|gemini2.5-pro) echo "gemini-2.5-pro" ;;
    gemini-2.5-flash|gemini2.5-flash) echo "gemini-2.5-flash" ;;
    gemini-3.5-flash|gemini3.5-flash) echo "gemini-3.5-flash" ;;
    gemini-3.1-pro|gemini3.1-pro) echo "gemini-3.1-pro" ;;
    gemini-pro) echo "gemini-2.5-pro" ;;
    gemini-flash) echo "gemini-2.5-flash" ;;
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

  if command -v jq >/dev/null 2>&1; then
    local merged
    merged=$(_pi_merged_object_json "default_models")
    val=$(echo "$merged" | jq -r --arg b "$backend" '.[$b] // empty' 2>/dev/null || true)
    if [ -n "$val" ] && [ "$val" != "null" ]; then
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
  BACKEND=$(get_setting "backend" "auto")
  MODEL=$(get_setting "model" "")
  MAX_TOKENS=$(get_setting "max_tokens" "12000")
  ENABLE_RESEARCH=$(get_setting "enable_research" "true")
  ENABLE_THINKING=$(get_setting "enable_thinking" "true")
  HEADLESS_ONLY=$(get_setting "headless_only" "true")
  FALLBACK_STRATEGY=$(get_setting "fallback_strategy" "manual")
  PREFERRED_BACKENDS=$(get_setting "preferred_backends" '["grok","claude","gemini","cline","opencode","kimi","kiro","codex"]')
  CUSTOM_COMMAND=$(get_setting "custom_command" "")
  ALLOW_WEB_SEARCH=$(get_setting "allow_web_search" "true")
  ALLOW_CODE_EXECUTION=$(get_setting "allow_code_execution_in_generation" "false")
  SKIP_VALIDATE=$(get_setting "skip_validate" "false")
  BACKEND_INVOCATION=$(get_setting "backend_invocation" "scripts")

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

  if [ "$MODEL" = "null" ]; then MODEL=""; fi
  if [ "$CUSTOM_COMMAND" = "null" ]; then CUSTOM_COMMAND=""; fi

  export PROMPT_IMPROVER_MAX_TOKENS="$MAX_TOKENS"
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
  local raw="${1:-}"
  local m mapped

  m=$(echo "$raw" | tr '[:upper:]' '[:lower:]' | sed 's/^model://; s/^model=//')

  if command -v jq >/dev/null 2>&1; then
    local aliases
    aliases=$(_pi_merged_object_json "model_aliases")
    mapped=$(echo "$aliases" | jq -r --arg k "$m" '.[$k] // empty' 2>/dev/null || true)
    if [ -n "$mapped" ] && [ "$mapped" != "null" ]; then
      echo "$mapped"
      return 0
    fi
  fi

  _builtin_normalize_model_id "$raw"
}

infer_backend_for_model() {
  local m low
  m=$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')
  low="$m"

  if command -v jq >/dev/null 2>&1; then
    local patterns_json count i j pat backend
    patterns_json=$(_pi_first_array_json "model_backend_patterns")
    count=$(echo "$patterns_json" | jq 'length' 2>/dev/null || echo 0)
    for ((i = 0; i < count; i++)); do
      backend=$(echo "$patterns_json" | jq -r ".[$i].backend // empty")
      while IFS= read -r pat; do
        [ -z "$pat" ] && continue
        if _pi_matches_any_pattern "$low" "$pat"; then
          echo "$backend"
          return 0
        fi
      done < <(echo "$patterns_json" | jq -r ".[$i].patterns[]?")
    done
  fi

  case "$low" in
    mythos*|fable*|claude-*|sonnet*|haiku*|opus*|claude) echo "claude" ;;
    grok*|composer*|spacex*) echo "grok" ;;
    gemini*) echo "gemini" ;;
    gpt-*|gpt*|o1*|o3*|o4*|codex|codex*|openai|chatgpt*|sol|terra|luna) echo "codex" ;;
    *) echo "" ;;
  esac
}

get_model_fallback_chain() {
  local primary low item pat
  primary=$(normalize_model_id "${1:-}")
  low=$(echo "$primary" | tr '[:upper:]' '[:lower:]')

  if command -v jq >/dev/null 2>&1; then
    local chains_json count i
    chains_json=$(_pi_first_array_json "model_fallback_chains")
    count=$(echo "$chains_json" | jq 'length' 2>/dev/null || echo 0)
    for ((i = 0; i < count; i++)); do
      local matched=false
      while IFS= read -r pat; do
        [ -z "$pat" ] && continue
        if _pi_matches_any_pattern "$low" "$pat"; then
          matched=true
          break
        fi
      done < <(echo "$chains_json" | jq -r ".[$i].patterns[]?")
      if [ "$matched" = true ]; then
        while IFS= read -r item; do
          [ -z "$item" ] && continue
          if [ "$item" = '$primary' ]; then
            echo "$primary"
          else
            echo "$item"
          fi
        done < <(echo "$chains_json" | jq -r ".[$i].chain[]?")
        return 0
      fi
    done
  fi

  case "$low" in
    *mythos*|mythos) echo "claude-mythos-5 claude-mythos-preview claude-fable-5 fable opus sonnet" ;;
    *fable*|fable) echo "claude-fable-5 fable opus sonnet" ;;
    *opus*|opus) echo "opus sonnet" ;;
    *sonnet*|sonnet) echo "$primary sonnet" ;;
    *haiku*|haiku) echo "$primary haiku sonnet" ;;
    *sol*|gpt-5.6) echo "gpt-5.6-sol gpt-5.6-terra gpt-5.6-luna gpt-5.5" ;;
    *terra*) echo "gpt-5.6-terra gpt-5.6-luna gpt-5.5" ;;
    *luna*) echo "gpt-5.6-luna gpt-5.5" ;;
    gpt-5.5|gpt-5|codex|openai) echo "gpt-5.5" ;;
    grok-4.5|grok-4*) echo "grok-4.5 grok-composer-2.5-fast grok-build" ;;
    *composer*) echo "$primary grok-composer-2.5-fast" ;;
    *gemini*pro*|gemini-2.5-pro) echo "gemini-2.5-pro gemini-2.5-flash" ;;
    *gemini*flash*|gemini-2.5-flash) echo "gemini-2.5-flash" ;;
    *) echo "$primary" ;;
  esac
}

_pi_limit_pattern() {
  local field="$1"
  local default="$2"
  if command -v jq >/dev/null 2>&1; then
    local merged pat
    merged=$(_pi_merged_object_json "limit_detection")
    pat=$(echo "$merged" | jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null || true)
    if [ -n "$pat" ] && [ "$pat" != "null" ]; then
      echo "$pat"
      return 0
    fi
  fi
  echo "$default"
}

is_account_limit_failure() {
  local output="$1"
  local low pat
  low=$(echo "$output" | tr '[:upper:]' '[:lower:]')
  pat=$(_pi_limit_pattern "account_patterns" \
    'weekly.?limit|monthly.?limit|hit your .*limit|you.?ve hit your|you have hit your|organization.?limit|org.?limit|account.?limit|out of (usage|credits)|usage.?limit.?reached|limit · resets|limit · reset')
  echo "$low" | grep -qE "$pat"
}

is_model_retryable_failure() {
  local exit_code="$1"
  local output="$2"
  local low pat
  low=$(echo "$output" | tr '[:upper:]' '[:lower:]')

  if is_account_limit_failure "$output"; then
    return 0
  fi

  pat=$(_pi_limit_pattern "retry_patterns" \
    'rate.?limit|usage.?limit|quota|out of (limit|usage|credits)|capacity|overloaded|529|429|403|401|not (available|found|supported|enabled)|unknown model|invalid model|model .* (denied|restricted|not accessible)|access denied|does not have access|invitation|glasswing|unavailable|try again later|too many requests|resource.?exhausted|throttl')
  if echo "$low" | grep -qE "$pat"; then
    return 0
  fi

  if [ "$exit_code" -ne 0 ] && echo "$low" | grep -qE 'model'; then
    return 0
  fi

  return 1
}

is_rate_limit_message_only() {
  local output="$1"
  local xml_pat
  [ -z "$output" ] && return 1
  xml_pat=$(_pi_limit_pattern "xml_markers" '<task[[:space:]]>|<prompt[[:space:]]>|<verification[[:space:]]>')
  if echo "$output" | grep -qiE "$xml_pat"; then
    return 1
  fi
  is_model_retryable_failure 1 "$output"
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
  if command -v "$want" >/dev/null 2>&1; then
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

detect_host_backend() {
  local explicit pid comm i backend var

  explicit=$(echo "${PROMPT_IMPROVER_HOST:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  if [ -n "$explicit" ]; then
    [ "$explicit" = "openai" ] && explicit="codex"
    echo "$explicit"
    return 0
  fi

  if command -v jq >/dev/null 2>&1; then
    local markers
    markers=$(_pi_merged_object_json "host_env_markers")
    while IFS= read -r backend; do
      [ -z "$backend" ] && continue
      while IFS= read -r var; do
        [ -z "$var" ] && continue
        if [ -n "${!var:-}" ]; then
          echo "$backend"
          return 0
        fi
      done < <(echo "$markers" | jq -r --arg b "$backend" '.[$b][]?')
    done < <(echo "$markers" | jq -r 'keys[]?')
  else
    if [ -n "${CLAUDE_CODE:-}" ] || [ -n "${CLAUDECODE:-}" ] || \
       [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ] || [ -n "${CLAUDE_AGENT:-}" ]; then
      echo "claude"; return 0
    fi
    if [ -n "${GROK_BUILD:-}" ] || [ -n "${XAI_GROK:-}" ] || [ -n "${GROK_SESSION:-}" ]; then
      echo "grok"; return 0
    fi
    if [ -n "${GEMINI_CLI:-}" ] || [ -n "${GOOGLE_GEMINI_CLI:-}" ]; then
      echo "gemini"; return 0
    fi
    if [ -n "${CODEX_HOME:-}" ] || [ -n "${OPENAI_CODEX:-}" ]; then
      echo "codex"; return 0
    fi
  fi

  pid="${PPID:-}"
  i=0
  while [ "$i" -lt 8 ] && [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if command -v jq >/dev/null 2>&1; then
      local proc_patterns backend_found=""
      proc_patterns=$(_pi_merged_object_json "parent_process_patterns")
      while IFS= read -r backend; do
        [ -z "$backend" ] && continue
        while IFS= read -r pat; do
          [ -z "$pat" ] && continue
          if _pi_matches_any_pattern "$comm" "$pat"; then
            backend_found="$backend"
            break
          fi
        done < <(echo "$proc_patterns" | jq -r --arg b "$backend" '.[$b][]?')
        [ -n "$backend_found" ] && break
      done < <(echo "$proc_patterns" | jq -r 'keys[]?')
      if [ -n "$backend_found" ]; then
        echo "$backend_found"
        return 0
      fi
    else
      case "$comm" in
        claude|claude-*|*claude*) echo "claude"; return 0 ;;
        grok|grok-*|*grok*)       echo "grok"; return 0 ;;
        gemini|gemini-*|*gemini*) echo "gemini"; return 0 ;;
        codex|codex-*|*codex*)    echo "codex"; return 0 ;;
        opencode|opencode-*)      echo "opencode"; return 0 ;;
        cline|cline-*)            echo "cline"; return 0 ;;
        kimi|kimi-*)              echo "kimi"; return 0 ;;
        kiro|kiro-*)              echo "kiro"; return 0 ;;
      esac
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d '[:space:]')
    i=$((i + 1))
  done

  echo ""
}

is_supported_backend() {
  local b="$1"
  [ "$b" = "openai" ] && b="codex"

  if command -v jq >/dev/null 2>&1; then
    local list
    list=$(_pi_first_array_json "supported_backends")
    if echo "$list" | jq -e --arg b "$b" 'index($b) != null' >/dev/null 2>&1; then
      return 0
    fi
    if [ "$(echo "$list" | jq 'length')" -gt 0 ]; then
      return 1
    fi
  fi

  case "$b" in
    claude|grok|gemini|codex|cline|opencode|kimi|kiro) return 0 ;;
    *) return 1 ;;
  esac
}

detect_backend() {
  local preferred=("$@")
  local b scan

  if [ "${#preferred[@]}" -gt 0 ]; then
    for b in "${preferred[@]}"; do
      [ "$b" = "openai" ] && b="codex"
      if command -v "$b" >/dev/null 2>&1; then
        echo "$b"
        return 0
      fi
    done
  fi

  if command -v jq >/dev/null 2>&1; then
    local order
    order=$(_pi_first_array_json "cascade_scan_order")
    while IFS= read -r scan; do
      [ -z "$scan" ] && continue
      [ "$scan" = "openai" ] && scan="codex"
      if command -v "$scan" >/dev/null 2>&1; then
        echo "$scan"
        return 0
      fi
    done < <(echo "$order" | jq -r '.[]?')
  fi

  for b in grok claude gemini cline opencode kimi kiro codex; do
    if command -v "$b" >/dev/null 2>&1; then
      echo "$b"
      return 0
    fi
  done

  echo "unknown"
}

parse_preferred_backends() {
  local items="" line cleaned

  if command -v jq >/dev/null 2>&1 && echo "$PREFERRED_BACKENDS" | jq -e 'type == "array"' >/dev/null 2>&1; then
    while IFS= read -r line; do
      [ -n "$line" ] && items="$items $line"
    done < <(jq -r '.[]' <<<"$PREFERRED_BACKENDS" 2>/dev/null)
  fi

  if [ -z "${items// /}" ]; then
    cleaned=$(echo "$PREFERRED_BACKENDS" | tr -d '[]"' | tr ',' ' ')
    items="$cleaned"
  fi

  if [ -z "${items// /}" ]; then
    items="grok claude gemini cline opencode kimi kiro codex"
  fi

  echo $items
}

# Build model args token for backend command templates.
_pi_model_args_for_backend() {
  local backend="$1"
  local model="$2"
  local flag_tpl="" result=""

  [ "$backend" = "openai" ] && backend="codex"
  [ -z "$model" ] && { echo ""; return 0; }

  if command -v jq >/dev/null 2>&1; then
    local flags
    flags=$(_pi_merged_object_json "backend_model_flags")
    flag_tpl=$(echo "$flags" | jq -r --arg b "$backend" '.[$b] // empty' 2>/dev/null || true)
    if [ -n "$flag_tpl" ] && [ "$flag_tpl" != "null" ]; then
      result="${flag_tpl//\{model\}/$model}"
      echo "$result"
      return 0
    fi
  fi

  case "$backend" in
    grok) echo "-m $model" ;;
    claude) echo "--model $model" ;;
    gemini|codex|openai) echo "-m $model" ;;
    *) echo "" ;;
  esac
}

get_backend_command() {
  local backend="$1"
  local prompt_file="$2"
  local model="${3:-${PROMPT_IMPROVER_MODEL:-}}"
  local tpl model_args rendered

  [ "$backend" = "openai" ] && backend="codex"
  model_args=$(_pi_model_args_for_backend "$backend" "$model")

  if command -v jq >/dev/null 2>&1; then
    local cmds
    cmds=$(_pi_merged_object_json "backend_commands")
    tpl=$(echo "$cmds" | jq -r --arg b "$backend" '.[$b] // empty' 2>/dev/null || true)
    if [ -n "$tpl" ] && [ "$tpl" != "null" ]; then
      rendered="${tpl//\{prompt_file\}/$prompt_file}"
      rendered="${rendered//\{model_args\}/$model_args}"
      rendered="${rendered//\{model\}/$model}"
      rendered="${rendered//\{max_tokens\}/$MAX_TOKENS}"
      echo "$rendered"
      return 0
    fi
  fi

  case "$backend" in
    grok)   echo "grok -p \"\$(cat \"$prompt_file\")\" $model_args --output-format plain --yolo" ;;
    claude) echo "claude -p \"\$(cat \"$prompt_file\")\" --print $model_args" ;;
    gemini) echo "gemini -p \"\$(cat \"$prompt_file\")\" $model_args" ;;
    cline)  echo "cline --prompt \"\$(cat \"$prompt_file\")\" --headless $model_args" ;;
    opencode) echo "opencode -p \"\$(cat \"$prompt_file\")\" $model_args" ;;
    kimi)   echo "kimi \"\$(cat \"$prompt_file\")\" --headless $model_args" ;;
    kiro)   echo "kiro -p \"\$(cat \"$prompt_file\")\" $model_args" ;;
    codex|openai) echo "codex exec \"\$(cat \"$prompt_file\")\" $model_args" ;;
    *) echo "" ;;
  esac
}

# Settings-driven overlay appended to the assembled generator prompt.
# True when user/project settings define a backend_commands entry for this backend.
_pi_has_backend_command_override() {
  local backend="$1"
  local file
  [ "$backend" = "openai" ] && backend="codex"
  for file in "$PROJECT_SETTINGS" "$USER_SETTINGS"; do
    [ -f "$file" ] || continue
    if command -v jq >/dev/null 2>&1; then
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

get_generation_settings_overlay() {
  cat <<EOF
=== RUNTIME SETTINGS (from prompt-improver config) ===
enable_research: $ENABLE_RESEARCH
enable_thinking: $ENABLE_THINKING
allow_web_search: $ALLOW_WEB_SEARCH
allow_code_execution_in_generation: $ALLOW_CODE_EXECUTION
max_tokens: $MAX_TOKENS
headless_only: $HEADLESS_ONLY

Apply these settings when building the improved prompt:
- When enable_research is false, omit or minimize <research> blocks unless the raw request explicitly requires external lookup.
- When enable_thinking is false, omit <approach> think-then-act blocks unless strictly necessary for safety.
- When allow_web_search is false, do not instruct the executor to search the web; rely on codebase exploration only.
- When allow_code_execution_in_generation is false, do not run gather-context.sh or shell during generation; use provided context only.
- Respect max_tokens as a soft cap on output length when the backend supports it.
EOF
}

export -f load_settings get_setting detect_backend detect_host_backend is_supported_backend \
  get_backend_command parse_preferred_backends get_generation_settings_overlay should_use_backend_script \
  get_default_model_for_backend resolve_generator_model normalize_model_id infer_backend_for_model \
  prefer_backend_if_available get_model_fallback_chain is_model_retryable_failure \
  is_account_limit_failure is_rate_limit_message_only