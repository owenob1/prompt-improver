#!/usr/bin/env bash
# Deterministic file cards: "path — description from the file's own header", one per tracked file.
set -euo pipefail
cd "$(git -C "${1:-.}" rev-parse --show-toplevel)"
git ls-files | while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in
    *.sh)   d=$(sed -n '2,8p' "$f" | grep '^#' | sed 's/^# \{0,1\}//' | grep -vF -e "$(basename "$f")" -e "scripts/" -e "$f" | head -2 | tr '\n' ' ') || true ;;
    *.md)   d=$( { grep -m1 '^#' "$f" | sed 's/^#* //'; sed -n '2,12p' "$f" | grep -vE '^(#|$|---|[|])' | head -1 | cut -c1-140; } | tr '\n' ' ') || true ;;
    *.json) d=$(jq -r '(.description // .["//"] // .name // empty)' "$f" 2>/dev/null | head -1 | cut -c1-140) || true ;;
    *.yml|*.yaml) d=$(grep -m1 '^name:' "$f" || true) || true ;;
    *)      d="" ;;
  esac
  printf '%s — %s\n' "$f" "$(printf '%s' "$d" | cut -c1-200)"
done
