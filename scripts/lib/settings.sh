#!/usr/bin/env bash
# scripts/lib/settings.sh
# Loads prompt-improver settings with sensible defaults and overrides.
# Priority: env vars > user settings > project settings > default

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

CONFIG_DIR="${PROMPT_IMPROVER_CONFIG_DIR:-$HOME/.config/prompt-improver}"
PROJECT_CONFIG_DIR="${PROMPT_IMPROVER_PROJECT_CONFIG_DIR:-.prompt-improver}"

DEFAULT_SETTINGS="$ROOT_DIR/config/settings.default.json"
USER_SETTINGS="$CONFIG_DIR/settings.json"
PROJECT_SETTINGS="$PROJECT_CONFIG_DIR/settings.json"

# Simple JSON getter using jq if available, else basic grep (limited)
get_setting() {
  local key="$1"
  local default="${2:-}"

  for file in "$PROJECT_SETTINGS" "$USER_SETTINGS" "$DEFAULT_SETTINGS"; do
    if [ -f "$file" ]; then
      if command -v jq >/dev/null 2>&1; then
        val=$(jq -r ".$key // empty" "$file" 2>/dev/null || true)
        if [ -n "$val" ] && [ "$val" != "null" ]; then
          echo "$val"
          return 0
        fi
      else
        # Fallback: very basic parsing
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

# Load all common settings into variables
load_settings() {
  BACKEND=$(get_setting "backend" "auto")
  MODEL=$(get_setting "model" "")
  MAX_TOKENS=$(get_setting "max_tokens" "12000")
  ENABLE_RESEARCH=$(get_setting "enable_research" "true")
  ENABLE_THINKING=$(get_setting "enable_thinking" "true")
  HEADLESS_ONLY=$(get_setting "headless_only" "true")
  FALLBACK_STRATEGY=$(get_setting "fallback_strategy" "manual")
  PREFERRED_BACKENDS=$(get_setting "preferred_backends" '["grok","claude","gemini"]')
  CUSTOM_COMMAND=$(get_setting "custom_command" "")

  # Env var overrides (highest priority)
  BACKEND="${PROMPT_IMPROVER_BACKEND:-$BACKEND}"
  MODEL="${PROMPT_IMPROVER_MODEL:-$MODEL}"
  MAX_TOKENS="${PROMPT_IMPROVER_MAX_TOKENS:-$MAX_TOKENS}"
  ENABLE_RESEARCH="${PROMPT_IMPROVER_ENABLE_RESEARCH:-$ENABLE_RESEARCH}"
  ENABLE_THINKING="${PROMPT_IMPROVER_ENABLE_THINKING:-$ENABLE_THINKING}"
}

# Detect the best backend based on available commands and environment
detect_backend() {
  local preferred=("$@")

  # Check for explicit current environment hints
  if [ -n "${CLAUDE:-}" ] || command -v claude >/dev/null 2>&1; then
    if [[ " ${preferred[*]} " == *" claude "* ]] || [ "${#preferred[@]}" -eq 0 ]; then
      echo "claude"
      return 0
    fi
  fi

  if [ -n "${GROK:-}" ] || command -v grok >/dev/null 2>&1; then
    if [[ " ${preferred[*]} " == *" grok "* ]] || [ "${#preferred[@]}" -eq 0 ]; then
      echo "grok"
      return 0
    fi
  fi

  if command -v gemini >/dev/null 2>&1; then
    if [[ " ${preferred[*]} " == *" gemini "* ]] || [ "${#preferred[@]}" -eq 0 ]; then
      echo "gemini"
      return 0
    fi
  fi

  if command -v cline >/dev/null 2>&1; then
    echo "cline"
    return 0
  fi

  # Fallback order
  for b in "${preferred[@]}"; do
    if command -v "$b" >/dev/null 2>&1; then
      echo "$b"
      return 0
    fi
  done

  echo "unknown"
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
    *)
      echo ""
      ;;
  esac
}

export -f load_settings get_setting detect_backend get_backend_command