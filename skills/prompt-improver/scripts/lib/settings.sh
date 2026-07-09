#!/usr/bin/env bash
# scripts/lib/settings.sh
# Loads prompt-improver settings with sensible defaults and overrides.
# Priority: env vars > project settings > user settings > default
#
# IMPORTANT: This file must not overwrite the caller's SCRIPT_DIR.
# It uses PI_* names for its own path resolution.

set -euo pipefail

_PI_SETTINGS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PI_ROOT_DIR="$(cd "$_PI_SETTINGS_DIR/../.." && pwd)"

CONFIG_DIR="${PROMPT_IMPROVER_CONFIG_DIR:-$HOME/.config/prompt-improver}"
PROJECT_CONFIG_DIR="${PROMPT_IMPROVER_PROJECT_CONFIG_DIR:-.prompt-improver}"

DEFAULT_SETTINGS="$_PI_ROOT_DIR/config/settings.default.json"
USER_SETTINGS="$CONFIG_DIR/settings.json"
PROJECT_SETTINGS="$PROJECT_CONFIG_DIR/settings.json"

# Simple JSON getter using jq if available, else basic grep (limited)
get_setting() {
  local key="$1"
  local default="${2:-}"
  local file val

  for file in "$PROJECT_SETTINGS" "$USER_SETTINGS" "$DEFAULT_SETTINGS"; do
    if [ -f "$file" ]; then
      if command -v jq >/dev/null 2>&1; then
        val=$(jq -r --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null || true)
        if [ -n "$val" ] && [ "$val" != "null" ]; then
          echo "$val"
          return 0
        fi
      else
        # Fallback: very basic parsing for string/number/bool scalars
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

# Built-in defaults if settings file has no default_models
# Strong mid-tier generators (not haiku/mini; not host frontier like fable/opus)
_PI_BUILTIN_DEFAULT_MODELS_claude="sonnet"
_PI_BUILTIN_DEFAULT_MODELS_grok="grok-composer-2.5-fast"
_PI_BUILTIN_DEFAULT_MODELS_gemini="gemini-2.5-pro"
_PI_BUILTIN_DEFAULT_MODELS_codex="gpt-5.5"

# Resolve default generator model for a backend (from settings.default_models or builtins)
get_default_model_for_backend() {
  local backend="$1"
  local val=""

  if [ "$backend" = "openai" ]; then
    backend="codex"
  fi

  if command -v jq >/dev/null 2>&1; then
    for file in "$PROJECT_SETTINGS" "$USER_SETTINGS" "$DEFAULT_SETTINGS"; do
      if [ -f "$file" ]; then
        val=$(jq -r --arg b "$backend" '.default_models[$b] // empty' "$file" 2>/dev/null || true)
        if [ -n "$val" ] && [ "$val" != "null" ]; then
          echo "$val"
          return 0
        fi
      fi
    done
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

  # Env var overrides (highest priority over settings file scalars)
  BACKEND="${PROMPT_IMPROVER_BACKEND:-$BACKEND}"
  MODEL="${PROMPT_IMPROVER_MODEL:-$MODEL}"
  MAX_TOKENS="${PROMPT_IMPROVER_MAX_TOKENS:-$MAX_TOKENS}"
  ENABLE_RESEARCH="${PROMPT_IMPROVER_ENABLE_RESEARCH:-$ENABLE_RESEARCH}"
  ENABLE_THINKING="${PROMPT_IMPROVER_ENABLE_THINKING:-$ENABLE_THINKING}"
  FALLBACK_STRATEGY="${PROMPT_IMPROVER_FALLBACK_STRATEGY:-$FALLBACK_STRATEGY}"
  CUSTOM_COMMAND="${PROMPT_IMPROVER_CUSTOM_COMMAND:-$CUSTOM_COMMAND}"

  # Null model from JSON becomes empty string (means: use per-backend default later)
  if [ "$MODEL" = "null" ]; then
    MODEL=""
  fi
  if [ "$CUSTOM_COMMAND" = "null" ]; then
    CUSTOM_COMMAND=""
  fi
}

# After backend is known, fill MODEL from default_models if still empty
resolve_generator_model() {
  local backend="$1"
  if [ -n "$MODEL" ]; then
    echo "$MODEL"
    return 0
  fi
  get_default_model_for_backend "$backend"
}

# Normalize user-facing model tokens to IDs backends commonly accept.
# Unknown future IDs (gpt-5.6-*, grok-4.6, …) pass through unchanged.
normalize_model_id() {
  local raw="${1:-}"
  local m
  m=$(echo "$raw" | tr '[:upper:]' '[:lower:]' | sed 's/^model://; s/^model=//')

  case "$m" in
    # Claude — Mythos (invite / Glasswing), Fable, Opus, Sonnet, Haiku
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

    # OpenAI / Codex — GPT-5.x and 5.6 Sol/Terra/Luna family
    gpt-5.6-sol|gpt5.6-sol|sol) echo "gpt-5.6-sol" ;;
    gpt-5.6-terra|gpt5.6-terra|terra) echo "gpt-5.6-terra" ;;
    gpt-5.6-luna|gpt5.6-luna|luna) echo "gpt-5.6-luna" ;;
    gpt-5.6|gpt5.6) echo "gpt-5.6-sol" ;;
    gpt5.5|gpt-5.5) echo "gpt-5.5" ;;
    gpt5|gpt-5) echo "gpt-5.5" ;;
    gpt-5.3-codex|gpt5.3-codex) echo "gpt-5.3-codex" ;;
    gpt-5.2-codex|gpt5.2-codex) echo "gpt-5.2-codex" ;;
    # model:codex / model:openai → default Codex-class generator model
    codex|openai) echo "gpt-5.5" ;;
    o4-mini|o4mini) echo "o4-mini" ;;

    # Grok / SpaceXAI
    grok-4.5|grok4.5) echo "grok-4.5" ;;
    grok-4.3|grok4.3) echo "grok-4.3" ;;
    composer-2.5-fast|composer2.5-fast|grok-composer-2.5-fast)
      echo "grok-composer-2.5-fast" ;;
    composer-2.5|composer2.5|grok-composer-2.5) echo "grok-composer-2.5-fast" ;;
    grok-build|grokbuild|grok-build-0.1) echo "grok-build" ;;
    grok-code-fast-1) echo "grok-code-fast-1" ;;

    # Gemini
    gemini-2.5-pro|gemini2.5-pro) echo "gemini-2.5-pro" ;;
    gemini-2.5-flash|gemini2.5-flash) echo "gemini-2.5-flash" ;;
    gemini-3.5-flash|gemini3.5-flash) echo "gemini-3.5-flash" ;;
    gemini-3.1-pro|gemini3.1-pro) echo "gemini-3.1-pro" ;;
    gemini-pro) echo "gemini-2.5-pro" ;;
    gemini-flash) echo "gemini-2.5-flash" ;;

    # Pass through: full IDs, future gpt-5.6-*, grok-4.x, claude-*, etc.
    *) echo "$raw" ;;
  esac
}

# Infer which coding CLI should run a given model id (pattern-based for future IDs).
infer_backend_for_model() {
  local m
  m=$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')

  case "$m" in
    mythos*|fable*|claude-*|sonnet*|haiku*|opus*|claude)
      echo "claude" ;;
    grok*|composer*|spacex*)
      echo "grok" ;;
    gemini*)
      echo "gemini" ;;
    gpt-*|gpt*|o1*|o3*|o4*|codex|codex*|openai|chatgpt*|sol|terra|luna)
      echo "codex" ;;
    *)
      # Future: gpt-5.6-anything, claude-anything already matched above
      echo "" ;;
  esac
}

# Ordered fallback list when primary model fails (access, rate limit, unknown model).
# mythos → fable → opus (user request); fable → opus → sonnet; etc.
get_model_fallback_chain() {
  local primary
  primary=$(normalize_model_id "${1:-}")
  local low
  low=$(echo "$primary" | tr '[:upper:]' '[:lower:]')

  case "$low" in
    # Claude frontier cascade
    *mythos*|mythos)
      echo "claude-mythos-5 claude-mythos-preview claude-fable-5 fable opus sonnet" ;;
    *fable*|fable)
      echo "claude-fable-5 fable opus sonnet" ;;
    *opus*|opus)
      echo "opus sonnet" ;;
    *sonnet*|sonnet)
      echo "$primary sonnet" ;;
    *haiku*|haiku)
      echo "$primary haiku sonnet" ;;

    # OpenAI GPT-5.6 Sol → Terra → Luna → 5.5
    *sol*|gpt-5.6)
      echo "gpt-5.6-sol gpt-5.6-terra gpt-5.6-luna gpt-5.5" ;;
    *terra*)
      echo "gpt-5.6-terra gpt-5.6-luna gpt-5.5" ;;
    *luna*)
      echo "gpt-5.6-luna gpt-5.5" ;;
    gpt-5.5|gpt-5|codex|openai)
      echo "gpt-5.5" ;;

    # Grok 4.5 → composer fast → grok-build
    grok-4.5|grok-4*)
      echo "grok-4.5 grok-composer-2.5-fast grok-build" ;;
    *composer*)
      echo "$primary grok-composer-2.5-fast" ;;

    # Gemini
    *gemini*pro*|gemini-2.5-pro)
      echo "gemini-2.5-pro gemini-2.5-flash" ;;
    *gemini*flash*|gemini-2.5-flash)
      echo "gemini-2.5-flash" ;;

    *)
      echo "$primary" ;;
  esac
}

# Account / org-wide limit (skip remaining models on same CLI; try another backend or host bounce)
is_account_limit_failure() {
  local output="$1"
  local low
  low=$(echo "$output" | tr '[:upper:]' '[:lower:]')
  echo "$low" | grep -qE \
    'weekly.?limit|monthly.?limit|hit your .*limit|you.?ve hit your|you have hit your|organization.?limit|org.?limit|account.?limit|out of (usage|credits)|usage.?limit.?reached|limit · resets|limit · reset'
}

# True if headless output/exit looks like "try another model" (limit, no access, unknown model)
is_model_retryable_failure() {
  local exit_code="$1"
  local output="$2"
  local low
  low=$(echo "$output" | tr '[:upper:]' '[:lower:]')

  if is_account_limit_failure "$output"; then
    return 0
  fi

  # Non-zero alone is not enough (auth, network) — need model-ish signals when possible
  if echo "$low" | grep -qE \
    'rate.?limit|usage.?limit|quota|out of (limit|usage|credits)|capacity|overloaded|529|429|403|401|not (available|found|supported|enabled)|unknown model|invalid model|model .* (denied|restricted|not accessible)|access denied|does not have access|invitation|glasswing|unavailable|try again later|too many requests|resource.?exhausted|throttl'
  then
    return 0
  fi

  # Some CLIs exit non-zero with sparse output for missing models
  if [ "$exit_code" -ne 0 ] && echo "$low" | grep -qE 'model'; then
    return 0
  fi

  return 1
}

# True when stdout looks like a rate/limit error rather than an improved prompt
is_rate_limit_message_only() {
  local output="$1"
  [ -z "$output" ] && return 1
  if echo "$output" | grep -qiE '<task[[:space:]>]|<prompt[[:space:]>]|<verification[[:space:]>]'; then
    return 1
  fi
  is_model_retryable_failure 1 "$output"
}

# Prefer an inferred backend when its CLI is installed.
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
  # Keep current if already valid; else try want's name anyway for clearer errors
  if [ -n "$current" ] && [ "$current" != "unknown" ] && [ "$current" != "auto" ]; then
    echo "WARNING: model wants backend '$want' but CLI not on PATH; using '$current'." >&2
    echo "$current"
    return 0
  fi
  echo "$want"
}

# Detect which host agent CLI is driving this session (not PATH auto-pick).
# Order: PROMPT_IMPROVER_HOST → known env markers → parent process tree.
# Empty string = unknown host (headless should be blocked unless model:/backend set).
detect_host_backend() {
  local explicit pid comm i

  explicit=$(echo "${PROMPT_IMPROVER_HOST:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  if [ -n "$explicit" ]; then
    [ "$explicit" = "openai" ] && explicit="codex"
    echo "$explicit"
    return 0
  fi

  # Claude Code / Anthropic
  if [ -n "${CLAUDE_CODE:-}" ] || [ -n "${CLAUDECODE:-}" ] || \
     [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ] || [ -n "${CLAUDE_AGENT:-}" ]; then
    echo "claude"
    return 0
  fi

  # Grok Build / xAI
  if [ -n "${GROK_BUILD:-}" ] || [ -n "${XAI_GROK:-}" ] || [ -n "${GROK_SESSION:-}" ]; then
    echo "grok"
    return 0
  fi

  # Gemini CLI
  if [ -n "${GEMINI_CLI:-}" ] || [ -n "${GOOGLE_GEMINI_CLI:-}" ]; then
    echo "gemini"
    return 0
  fi

  # Codex / OpenAI
  if [ -n "${CODEX_HOME:-}" ] || [ -n "${OPENAI_CODEX:-}" ]; then
    echo "codex"
    return 0
  fi

  # Walk parent processes (skills.sh hosts often leave the real CLI a few levels up)
  pid="${PPID:-}"
  i=0
  while [ "$i" -lt 8 ] && [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
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
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d '[:space:]')
    i=$((i + 1))
  done

  echo ""
}

# True if name is a generator backend we know how to invoke headlessly
is_supported_backend() {
  local b="$1"
  [ "$b" = "openai" ] && b="codex"
  case "$b" in
    claude|grok|gemini|codex|cline|opencode|kimi|kiro) return 0 ;;
    *) return 1 ;;
  esac
}

# Detect the best backend based on preferred order, then availability.
# Used only as a cascade list after the primary host/model choice fails — not for default pick.
detect_backend() {
  local preferred=("$@")
  local b

  # Respect preferred order first
  if [ "${#preferred[@]}" -gt 0 ]; then
    for b in "${preferred[@]}"; do
      # Normalize alias
      if [ "$b" = "openai" ]; then
        b="codex"
      fi
      if command -v "$b" >/dev/null 2>&1; then
        echo "$b"
        return 0
      fi
    done
  fi

  # Fallback scan of known CLIs
  for b in grok claude gemini cline opencode kimi kiro codex; do
    if command -v "$b" >/dev/null 2>&1; then
      echo "$b"
      return 0
    fi
  done

  echo "unknown"
}

# Parse preferred_backends JSON into space-separated names on stdout (portable)
# Usage: PREFS=( $(parse_preferred_backends) )
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

  # shellcheck disable=SC2086
  echo $items
}

# Get the actual command template for a backend
get_backend_command() {
  local backend="$1"
  local prompt_file="$2"   # path to file containing the full prompt

  case "$backend" in
    grok)
      echo "grok -p \"\$(cat \"$prompt_file\")\" --output-format json"
      ;;
    claude)
      echo "claude -p \"\$(cat \"$prompt_file\")\""
      ;;
    gemini)
      echo "gemini -p \"\$(cat \"$prompt_file\")\""
      ;;
    cline)
      echo "cline --prompt \"\$(cat \"$prompt_file\")\" --headless"
      ;;
    opencode)
      echo "opencode -p \"\$(cat \"$prompt_file\")\""
      ;;
    kimi)
      echo "kimi \"\$(cat \"$prompt_file\")\" --headless"
      ;;
    kiro)
      echo "kiro -p \"\$(cat \"$prompt_file\")\""
      ;;
    codex|openai)
      echo "codex exec \"\$(cat \"$prompt_file\")\""
      ;;
    *)
      echo ""
      ;;
  esac
}

export -f load_settings get_setting detect_backend detect_host_backend is_supported_backend \
  get_backend_command parse_preferred_backends \
  get_default_model_for_backend resolve_generator_model normalize_model_id infer_backend_for_model \
  prefer_backend_if_available get_model_fallback_chain is_model_retryable_failure \
  is_account_limit_failure is_rate_limit_message_only
