#!/usr/bin/env bash
# scripts/lib/jev.sh
# Minimal client for TypeSafe's Jev decision model (POST /v1/systemone).
# Sourced, never executed. Like lib/settings.sh it must not assign SCRIPT_DIR.
#
# Jev answers typed questions (noul / choice / score) about a block of state in
# one parallel pass (~70–500 ms). It cannot generate text, so prompt-improver
# only uses it to make decisions; the XML still comes from templates or an LLM.
#
# - pi_jev_available                      curl + jq + an API key are present
# - pi_jev_redact                         stdin → stdout with credential-shaped strings masked
# - pi_jev_call <request.json> <out.json> POST the request; 0 on HTTP 200 with answers
#
# Provider (PROMPT_IMPROVER_JEV_PROVIDER = auto | typesafe | openrouter):
#   typesafe   https://api.typesafe.ai/v1/systemone      TYPESAFE_API_KEY
#   openrouter https://openrouter.ai/api/v1/systemone    OPENROUTER_API_KEY
#   auto       typesafe when TYPESAFE_API_KEY is set, else openrouter.
# PROMPT_IMPROVER_JEV_ENDPOINT overrides the URL (tests, proxies).
# Every failure returns non-zero so callers fall back to the LLM path.

_pi_jev_provider() {
  local p="${PROMPT_IMPROVER_JEV_PROVIDER:-auto}"
  case "$p" in
    typesafe|openrouter) echo "$p" ;;
    *)
      if [ -n "${TYPESAFE_API_KEY:-}" ]; then
        echo typesafe
      elif [ -n "${OPENROUTER_API_KEY:-}" ]; then
        echo openrouter
      else
        echo none
      fi
      ;;
  esac
}

_pi_jev_key() {
  case "$(_pi_jev_provider)" in
    typesafe) printf '%s' "${TYPESAFE_API_KEY:-}" ;;
    openrouter) printf '%s' "${OPENROUTER_API_KEY:-}" ;;
  esac
}

_pi_jev_endpoint() {
  if [ -n "${PROMPT_IMPROVER_JEV_ENDPOINT:-}" ]; then
    echo "$PROMPT_IMPROVER_JEV_ENDPOINT"
    return 0
  fi
  case "$(_pi_jev_provider)" in
    typesafe) echo "https://api.typesafe.ai/v1/systemone" ;;
    openrouter) echo "https://openrouter.ai/api/v1/systemone" ;;
  esac
}

# Model id: OpenRouter namespaces it (typesafe/…); TypeSafe takes it bare.
pi_jev_model() {
  local m="${PROMPT_IMPROVER_JEV_MODEL:-jev-latest}"
  if [ "$(_pi_jev_provider)" = "openrouter" ]; then
    case "$m" in
      */*|~*) ;;
      jev-latest) m="~typesafe/jev-latest" ;;
      *) m="typesafe/$m" ;;
    esac
  fi
  echo "$m"
}

pi_jev_available() {
  command -v curl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  [ -n "$(_pi_jev_key)" ]
}

# Mask credential-shaped strings before any text leaves the machine.
pi_jev_redact() {
  sed -E \
    -e 's/(sk|pk|rk)-[A-Za-z0-9_-]{16,}/[REDACTED]/g' \
    -e 's/(ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]{16,}/[REDACTED]/g' \
    -e 's/xox[abprs]-[A-Za-z0-9-]{10,}/[REDACTED]/g' \
    -e 's/AKIA[0-9A-Z]{16}/[REDACTED]/g' \
    -e 's/AIza[0-9A-Za-z_-]{30,}/[REDACTED]/g' \
    -e 's/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/[REDACTED]/g' \
    -e 's/-----BEGIN [A-Z ]*PRIVATE KEY-----/[REDACTED PRIVATE KEY]/g' \
    -e 's/(([Aa][Pp][Ii]|[Aa][Cc][Cc][Ee][Ss][Ss])?_?([Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]))([[:space:]]*[:=][[:space:]]*["'"'"']?)[^[:space:]"'"'"',;]{6,}/\1\4[REDACTED]/g'
}

# POST a request file; write the response body to <out>. Timeout in ms from
# PROMPT_IMPROVER_JEV_TIMEOUT_MS (default 2000). One retry on 429/529/5xx.
# The key goes in a mode-600 header file, never on argv (visible in `ps`).
pi_jev_call() {
  local req="$1" out="$2"
  local key url ms secs hdr code attempt
  key=$(_pi_jev_key)
  url=$(_pi_jev_endpoint)
  [ -n "$key" ] && [ -n "$url" ] || return 1
  ms="${PROMPT_IMPROVER_JEV_TIMEOUT_MS:-2000}"
  case "$ms" in ''|*[!0-9]*) ms=2000 ;; esac
  secs=$(awk -v m="$ms" 'BEGIN { printf "%.3f", m / 1000 }')

  hdr=$(mktemp -t pi-jev-hdr.XXXXXX)
  chmod 600 "$hdr"
  printf 'Authorization: Bearer %s\nContent-Type: application/json\n' "$key" >"$hdr"

  for attempt in 1 2; do
    code=$(curl -sS --max-time "$secs" -X POST -H @"$hdr" \
      --data-binary @"$req" -o "$out" -w '%{http_code}' "$url" 2>/dev/null) || code="000"
    case "$code" in
      200) break ;;
      429|529|500|502|503|504) [ "$attempt" -eq 1 ] && sleep 0.2 && continue ;;
    esac
    break
  done
  rm -f "$hdr"

  if [ "$code" != "200" ]; then
    echo "jev: HTTP $code from $url" >&2
    return 1
  fi
  jq -e '.answers | type == "object"' "$out" >/dev/null 2>&1 || {
    echo "jev: malformed response" >&2
    return 1
  }
}
