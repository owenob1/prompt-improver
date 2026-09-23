#!/usr/bin/env bash
# scripts/compile/target.sh
# Deterministic facts about the request's target file, used by guards, slots
# and code anchors. The file is read, never executed.
#
# Usage: bash target.sh <repo-root> <repo-relative-path>
# Stdout: JSON
#   path name stem ext runner syntax_check
#   summary   first sentence of the file's own header, lower-cased initial
#   usage     header comment + usage/help text + options handled (≤ 2500 chars)
#   options   option tokens the file parses (case patterns, argparse, commander…)
#   lines     [{n, fn, text}] statement lines (anchor candidates, ≤ 600)
#   refs      [{path, n, text, kind}] other files naming this one; kind = calls | doc | mentions
#   callers   paths whose refs invoke this file
# Exit 1 on usage or when the file is not readable.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/jev.sh
source "$HERE/../lib/jev.sh"

ROOT="${1:-}"
REL="${2:-}"
if [ -z "$ROOT" ] || [ -z "$REL" ] || [ ! -f "$ROOT/$REL" ] || [ ! -r "$ROOT/$REL" ]; then
  echo "Usage: $0 <repo-root> <repo-relative-path>" >&2
  exit 1
fi
cd "$ROOT"
command -v jq >/dev/null 2>&1 || { echo "target: jq is required" >&2; exit 1; }

WORK=$(mktemp -d -t pi-target.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

NAME="${REL##*/}"
STEM="${NAME%.*}"
EXT=""
case "$NAME" in *.*) EXT="${NAME##*.}" ;; esac
SHEBANG=$(awk 'NR == 1 && /^#!/ { print; exit }' "$REL")

RUNNER=""
SYNTAX=""
_lang="$EXT"
if [ -z "$_lang" ]; then
  case "$SHEBANG" in
    *bash*|*/sh|*" sh"*) _lang=sh ;;
    *python*) _lang=py ;;
    *node*) _lang=js ;;
    *ruby*) _lang=rb ;;
    *perl*) _lang=pl ;;
    *zsh*) _lang=zsh ;;
  esac
fi
case "$_lang" in
  sh|bash) RUNNER=bash; SYNTAX="bash -n $REL" ;;
  zsh) RUNNER=zsh; SYNTAX="zsh -n $REL" ;;
  py) RUNNER=python3; SYNTAX="python3 -m py_compile $REL" ;;
  js|mjs|cjs) RUNNER=node; SYNTAX="node --check $REL" ;;
  rb) RUNNER=ruby; SYNTAX="ruby -c $REL" ;;
  pl) RUNNER=perl; SYNTAX="perl -c $REL" ;;
  php) RUNNER=php; SYNTAX="php -l $REL" ;;
esac

# Header comment block (after the shebang), comment markers stripped.
awk '
  NR == 1 && /^#!/ { next }
  /^[[:space:]]*(#|\/\/|\*|\/\*)/ || (NR <= 3 && /^[[:space:]]*("""|\047\047\047)/) {
    t = $0; sub(/^[[:space:]]*(#+|\/\/+|\/\*+|\*+)[[:space:]]?/, "", t); sub(/\*+\/[[:space:]]*$/, "", t)
    print t; n++; if (n >= 40) exit; next
  }
  /^[[:space:]]*$/ { if (n > 0) print ""; next }
  { exit }
' "$REL" >"$WORK/header.txt"

# Usage/help text: heredocs or echo/printf lines that mention "usage", plus
# argparse/commander/click declarations.
awk '
  function flushdoc() { if (doc != "" && tolower(doc) ~ /usage|options|--/) printf "%s", doc; doc = "" }
  inhere {
    if ($0 ~ "^[[:space:]]*" term "[[:space:]]*$") { inhere = 0; flushdoc(); next }
    if (nd < 40) { doc = doc $0 "\n" }
    if (++nd > 200) { inhere = 0; doc = "" }
    next
  }
  /^[[:space:]]*#/ { next }
  /<<-?[[:space:]]*["\047]?[A-Za-z_]+["\047]?/ {
    t = $0; sub(/.*<<-?[[:space:]]*["\047]?/, "", t); sub(/["\047].*$/, "", t); sub(/[^A-Za-z_].*$/, "", t)
    if (t != "") { term = t; inhere = 1; doc = ""; nd = 0 }
    next
  }
  tolower($0) ~ /(echo|printf|print|console\.(log|error))[^a-z].*usage:/ { t = $0; gsub(/^[[:space:]]+/, "", t); print t; next }
  /add_argument\(|ArgumentParser\(|@click\.(option|argument|command)|\.option\(|\.command\(|\.argument\(|\.requiredOption\(/ { t = $0; gsub(/^[[:space:]]+/, "", t); print substr(t, 1, 200) }
' "$REL" >"$WORK/usage.txt"

# Option tokens from case patterns and declarations.
awk '
  /^[[:space:]]*["\047]?-{1,2}[A-Za-z0-9][A-Za-z0-9_-]*["\047]?([[:space:]]*\|[[:space:]]*["\047]?-{1,2}[A-Za-z0-9][A-Za-z0-9_-]*["\047]?)*\)/ {
    t = $0; sub(/\).*/, "", t); gsub(/["\047[:space:]]/, "", t)
    n = split(t, a, "|"); for (i = 1; i <= n; i++) if (a[i] ~ /^-/) print a[i]
  }
  /add_argument\(|\.option\(|\.requiredOption\(|@click\.option\(/ {
    t = $0
    while (match(t, /["\047]-{1,2}[A-Za-z0-9][A-Za-z0-9_-]*["\047]/)) { print substr(t, RSTART + 1, RLENGTH - 2); t = substr(t, RSTART + RLENGTH) }
  }
' "$REL" | awk '!seen[$0]++' | awk 'NR <= 60' >"$WORK/options.txt"

# Statement lines with the enclosing function (anchor candidates).
awk '
  {
    line = $0
    if (line ~ /^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_:.-]*[[:space:]]*\(\)[[:space:]]*\{?[[:space:]]*$/) {
      fn = line; sub(/^[[:space:]]*(function[[:space:]]+)?/, "", fn); sub(/[[:space:]]*\(.*/, "", fn)
    } else if (line ~ /^[[:space:]]*(def|func|fn|function|async function)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/) {
      fn = line; sub(/^[[:space:]]*(def|func|fn|function|async function)[[:space:]]+/, "", fn); sub(/[^A-Za-z0-9_].*/, "", fn)
    } else if (line ~ /^[^[:space:]]/ && line !~ /^[}#]/) {
      fn = ""
    }
    t = line; gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
    if (t == "" || t ~ /^(#|\/\/|\*|\/\*)/) next
    if (t ~ /^(\}|\{|fi|done|esac|;;|else|then|do|\)|\]|end|\};?|\);?|elif .*; then)$/) next
    if (length(t) < 4) next
    if (NR == 1 && t ~ /^#!/) next
    printf "%d\t%s\t%s\n", NR, fn, substr(t, 1, 160)
  }
' "$REL" | awk 'NR <= 600' >"$WORK/lines.tsv"

# References from other tracked files (git grep -F on the file name).
: >"$WORK/refs.tsv"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git grep -n -I -F -e "$NAME" -- . ":(exclude)$REL" 2>/dev/null \
    | awk 'NR <= 80' \
    | awk -v name="$NAME" '
        {
          p = $0; sub(/:.*/, "", p); rest = substr($0, length(p) + 2)
          n = rest; sub(/:.*/, "", n); text = substr(rest, length(n) + 2)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", text)
          kind = "mentions"
          if (p ~ /\.(md|mdx|rst|txt|adoc)$/ || p ~ /(^|\/)(CHANGELOG|README|LICENSE)/) kind = "doc"
          else if (p ~ /\.(json|jsonl|xml|csv|tsv|lock|snap)$/ || p ~ /(^|\/)(fixtures?|testdata)\//) kind = "mentions"
          else if (text ~ /^[[:space:]]*#/) kind = "mentions"
          else {
            q = name; gsub(/\./, "\\.", q)
            if (text ~ ("(bash|sh|zsh|source|exec|python3?|node|ruby|perl)[[:space:]][^|;&]*" q) || text ~ ("^\\.[[:space:]][^|;&]*" q) || text ~ ("[\"$/]" q "\"?[[:space:]]") || text ~ ("(require|import)[^;]*" q)) kind = "calls"
          }
          printf "%s\t%s\t%s\t%s\n", p, n, kind, substr(text, 1, 200)
        }' >"$WORK/refs.tsv" || true
fi

SUMMARY=$(awk 'NF { print; exit }' "$WORK/header.txt" 2>/dev/null || true)
# Skip a first line that only repeats the path or the name.
if [ -n "$SUMMARY" ] && { [ "$SUMMARY" = "$REL" ] || [ "$SUMMARY" = "$NAME" ] || [[ "$SUMMARY" == *"$NAME" ]]; }; then
  SUMMARY=$(awk 'NF' "$WORK/header.txt" | awk 'NR == 2 { print; exit }' || true)
fi
SUMMARY="${SUMMARY%.}"
if [[ "$SUMMARY" == *". "* ]]; then SUMMARY="${SUMMARY%%. *}"; fi

for f in header.txt usage.txt lines.tsv refs.tsv; do
  pi_jev_redact <"$WORK/$f" >"$WORK/$f.red"
done

jq -n \
  --arg path "$REL" --arg name "$NAME" --arg stem "$STEM" --arg ext "$EXT" \
  --arg runner "$RUNNER" --arg syntax "$SYNTAX" --arg summary "$SUMMARY" \
  --rawfile header "$WORK/header.txt.red" --rawfile usage "$WORK/usage.txt.red" \
  --rawfile options "$WORK/options.txt" --rawfile lines "$WORK/lines.tsv.red" \
  --rawfile refs "$WORK/refs.tsv.red" '
  def rows($s): $s | split("\n") | map(select(length > 0) | split("\t"));
  ($options | split("\n") | map(select(length > 0))) as $opts
  | (rows($refs) | map({path: .[0], n: (.[1] | tonumber? // 0), kind: .[2], text: (.[3:] | join(" "))})) as $refs
  | {
      path: $path, name: $name, stem: $stem, ext: $ext, runner: $runner, syntax_check: $syntax,
      summary: (if $summary == "" then "" else ($summary[0:1] | ascii_downcase) + $summary[1:] end),
      usage: (($header | sub("\\s+$"; ""))[0:1400]
              + (if ($usage | length) > 0 then "\n\n" + ($usage | sub("\\s+$"; ""))[0:1000] else "" end)
              + (if ($opts | length) > 0 then "\n\nOptions the file parses: " + ($opts | join(" ")) else "\n\nOptions the file parses: (none found)" end)),
      options: $opts,
      lines: (rows($lines) | map({n: (.[0] | tonumber), fn: .[1], text: (.[2:] | join(" "))})),
      refs: $refs,
      callers: ([$refs[] | select(.kind == "calls") | .path] | unique)
    }'
