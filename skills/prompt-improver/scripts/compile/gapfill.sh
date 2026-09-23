#!/usr/bin/env bash
# scripts/compile/gapfill.sh
# Tier B of the Jev v2 fast path: an LLM writes only the sections the compiled
# skeleton could not fill (<!-- GAP:<section> --> markers); everything else stays
# exactly as compiled.
#
# Usage:
#   bash gapfill.sh prompt <gapfill.json>                 the LLM prompt, on stdout
#   bash gapfill.sh merge  <gapfill.json> <llm-output>    the merged spec, on stdout
#
# <gapfill.json> is written by pipeline.sh: {skeleton, gaps, target, rules, request, repo}.
# merge exits 1 when a marker has no matching <gap name="…"> block in the output,
# so the caller can fall back to full generation.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUIDE="${PROMPT_IMPROVER_LIBRARY_DIR:-$HERE/../../assets/library}/_gapfill.json"

CMD="${1:-}"
GF="${2:-}"
if [ -z "$CMD" ] || [ -z "$GF" ] || [ ! -f "$GF" ]; then
  echo "Usage: $0 prompt <gapfill.json> | merge <gapfill.json> <llm-output>" >&2
  exit 1
fi

case "$CMD" in
  prompt)
    REPO=$(jq -r '.repo // ""' "$GF")
    TPATH=$(jq -r '.target.path // ""' "$GF")
    SRC=""
    if [ -n "$TPATH" ] && [ -f "$REPO/$TPATH" ]; then
      SRC=$(awk '{ printf "%5d  %s\n", NR, $0 }' "$REPO/$TPATH")
      SRC="${SRC:0:60000}"
    fi
    jq -r --arg src "$SRC" --slurpfile guide "$GUIDE" '
      "You are completing a specification that a coding agent will carry out. It was compiled from a reviewed library and already fits this request: keep every existing line exactly as it is. Write only the content for each <!-- GAP:<section> --> marker.",
      "",
      "<request>", .request, "</request>",
      "",
      (if $src != "" then "<target-file path=\"\(.target.path)\">", $src, "</target-file>", "" else empty end),
      "<specification>", .skeleton, "</specification>",
      "",
      "What each marker needs:",
      (.gaps[] | "- GAP:\(.section): " + (.prompt // $guide[0].sections[.section] // "the missing content for this section, specific to this request and this code.")),
      "",
      "Rules: be specific to this request and this code; do not repeat lines already in the specification; no vague adjectives; do not carry out the work.",
      "Reply with exactly one block per marker and nothing else:",
      (.gaps[] | "<gap name=\"\(.section)\">", "…", "</gap>")
    ' "$GF"
    ;;
  merge)
    OUT="${3:-}"
    [ -n "$OUT" ] && [ -f "$OUT" ] || { echo "Usage: $0 merge <gapfill.json> <llm-output>" >&2; exit 1; }
    jq -r '.skeleton' "$GF" >"$GF.skeleton.xml"
    # One awk pass: read the <gap> blocks from the LLM output, then replace each
    # marker line of the skeleton with its block, indented like the marker.
    awk -v out="$OUT" '
      BEGIN {
        while ((getline line < out) > 0) {
          if (match(line, /<gap name="[a-z_.]+">/)) {
            name = substr(line, RSTART + 11, RLENGTH - 13); cur = name; body[name] = ""; seen[name] = 1
            rest = substr(line, RSTART + RLENGTH)
            if (rest ~ /<\/gap>/) { sub(/<\/gap>.*/, "", rest); body[name] = rest; cur = "" }
            else if (rest ~ /[^[:space:]]/) body[name] = rest "\n"
            continue
          }
          if (cur != "" && line ~ /<\/gap>/) { t = line; sub(/<\/gap>.*/, "", t); if (t ~ /[^[:space:]]/) body[cur] = body[cur] t "\n"; cur = ""; continue }
          if (cur != "") body[cur] = body[cur] line "\n"
        }
        close(out)
      }
      function clean(s) {
        # Structural tags would break the spec: drop lines that carry them.
        return (s ~ /<\/?(task|check|execution|context|verification|approach|requirements|escape|constraints|examples|user-request|gap)([[:space:]>]|$)/) ? "" : s
      }
      {
        if (match($0, /<!-- GAP:[a-z_.]+ -->/)) {
          name = substr($0, RSTART + 9, RLENGTH - 13)
          if (!(name in seen)) { missing = missing " " name; next }
          pre = substr($0, 1, RSTART - 1)
          if (pre ~ /^[[:space:]]*$/) {
            n = split(body[name], ls, "\n"); emitted = 0
            for (i = 1; i <= n; i++) {
              t = clean(ls[i]); gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
              if (t == "") continue
              print pre t; emitted++
            }
            if (!emitted) missing = missing " " name
          } else {
            t = body[name]; gsub(/\n/, " ", t); gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
            t = clean(t)
            if (t == "") missing = missing " " name
            line = $0; sub(/ ?<!-- GAP:[a-z_.]+ -->/, (t == "" ? "" : " " t), line); print line
          }
          next
        }
        print
      }
      END { if (missing != "") { print "gapfill: no content for:" missing > "/dev/stderr"; exit 1 } }
    ' "$GF.skeleton.xml"
    ;;
  *)
    echo "Usage: $0 prompt <gapfill.json> | merge <gapfill.json> <llm-output>" >&2
    exit 1
    ;;
esac
