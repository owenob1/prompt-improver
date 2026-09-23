#!/usr/bin/env bash
# scripts/compile/candidates.sh
# L0 of the Jev v2 fast path: deterministic candidates for one request.
# Shell, git and jq only. No AI, no network, no recursive find: the file list
# is `git ls-files`, and identifiers are looked up with `git grep -F`, so the
# output is reproducible for a given tree.
#
# Usage: bash candidates.sh <repo-root> <request-file>
# Stdout: one JSON object. Exit 1 on usage, 2 when jq is missing.
#
# Request-derived (never cached):
#   request   the request with credential-shaped strings masked
#   entities  [{id, kind, text, paths?, refs?}]
#             kinds: url flag env file code identifier quoted version quantity number
#             paths: tracked files a file entity resolves to
#             refs:  "path:line: text" hits for identifiers (git grep -F -w)
#   spans     contiguous word spans, in order (options for role extraction)
#   words     distinct content words (options for word slots)
# Repo-derived (cached per HEAD + working-tree diff):
#   files     [{path, card}]  card = "path — description from the file's own header"
#   rules     [{src, text}]   sentence units from agent-instruction files
#   commands  [{cmd, src}]    CI run steps, package scripts, make targets, fenced shell in docs
#   tests     [path]          tracked files that look like tests
#   changelog path or ""
#   project   one-sentence description or ""
#
# Env: PROMPT_IMPROVER_CACHE_DIR (default ${XDG_CACHE_HOME:-~/.cache}/prompt-improver)
#      PROMPT_IMPROVER_FAST_MAX_CARDS (default 250)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/jev.sh
source "$HERE/../lib/jev.sh"

ROOT="${1:-}"
REQ_FILE="${2:-}"
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ] || [ -z "$REQ_FILE" ] || [ ! -f "$REQ_FILE" ]; then
  echo "Usage: $0 <repo-root> <request-file>" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "candidates: jq is required" >&2; exit 2; }

INDEX_VERSION=9
MAX_CARDS="${PROMPT_IMPROVER_FAST_MAX_CARDS:-250}"
case "$MAX_CARDS" in ''|*[!0-9]*) MAX_CARDS=250 ;; esac

REQUEST=$(pi_jev_redact <"$REQ_FILE")
REQUEST="${REQUEST:0:24000}"

cd "$ROOT"
IS_GIT=false
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IS_GIT=true
  cd "$(git rev-parse --show-toplevel)"
fi

WORK=$(mktemp -d -t pi-cand.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# Repo index (cached)
# ---------------------------------------------------------------------------

_cache_dir() {
  local base="${PROMPT_IMPROVER_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/prompt-improver}"
  printf '%s/index' "$base"
}

_cache_key() {
  {
    printf 'v%s\n%s\n' "$INDEX_VERSION" "$PWD"
    git rev-parse HEAD 2>/dev/null || echo "no-head"
    git status --porcelain=v1 2>/dev/null || true
    git diff HEAD --no-ext-diff --no-color 2>/dev/null || true
  } | cksum | awk '{ print $1 "-" $2 }'
}

# Tracked, readable, non-binary, non-vendored files.
_tracked_files() {
  git -c core.quotepath=off ls-files 2>/dev/null \
    | awk '
        /^"/ { next }
        /(^|\/)(node_modules|vendor|dist|build|out|target|\.git|\.venv|venv|__pycache__)\// { next }
        /(^|\/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb|Cargo\.lock|go\.sum|poetry\.lock|uv\.lock|Gemfile\.lock|composer\.lock)$/ { next }
        /\.(png|jpe?g|gif|webp|ico|svg|bmp|tiff?|pdf|zip|gz|tgz|bz2|xz|7z|jar|war|class|o|a|so|dylib|dll|exe|bin|woff2?|ttf|otf|eot|mp[34]|mov|avi|wav|ogg|min\.js|map)$/ { next }
        { print }
      ' \
    | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done
}

# path<TAB>description, from each file's own header. One awk pass over all files.
_CARDS_AWK='
function flush(   d) {
  if (cur == "") return
  d = desc
  gsub(/[\t\r]/, " ", d); gsub(/[[:space:]]+/, " ", d); sub(/^ /, "", d); sub(/ $/, "", d)
  print cur "\t" substr(d, 1, 200)
  cur = ""
}
function add(t) {
  gsub(/\*\*/, "", t); gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
  if (t == "" || t ~ /^[-=*_#~.\/]+$/) return
  if (index(t, cur) == 1 || index(t, base) == 1 || (t ~ /^[^[:space:]]+[[:space:]]/ && index(substr(t, 1, index(t, " ")), base))) {
    if (match(t, / (—|–|-|→|:) /)) t = substr(t, RSTART + RLENGTH)
    else if (index(t, " ")) t = substr(t, index(t, " ") + 1)
    else return
    gsub(/^[[:space:]]+/, "", t)
    if (t == "") return
  }
  if (t ~ /shellcheck|-\*-|vim:|coding[:=]|eslint-|@license|SPDX-License|^use strict|^Copyright/) return
  desc = (desc == "" ? t : desc " " t); got++
}
FNR == 1 {
  flush(); cur = FILENAME; desc = ""; got = 0; fm = 0; fmd = 0; md_head = ""; inpy = 0
  base = cur; sub(/.*\//, "", base)
  ext = ""; if (match(base, /\.[A-Za-z0-9]+$/)) ext = tolower(substr(base, RSTART + 1))
  style = "hash"
  if (ext ~ /^(js|mjs|cjs|ts|mts|cts|tsx|jsx|go|rs|c|h|cc|cpp|hpp|java|kt|kts|swift|cs|scala|dart|php|css|scss|less|zig|proto)$/) style = "slash"
  else if (ext ~ /^(md|mdx|markdown|rst|txt|adoc)$/) style = "md"
  else if (ext == "json" || ext == "jsonc") style = "json"
  else if (ext ~ /^(html|htm|xml|vue|svelte)$/) style = "none"
  if (FNR == 1 && $0 == "---" && style == "md") { fm = 1; next }
}
FNR > 20 || got >= 2 { flush(); nextfile }
style == "none" { flush(); nextfile }
fm == 1 {
  if ($0 == "---") { fm = 2; next }
  if (fmd && $0 ~ /^[[:space:]]+[^[:space:]]/) { add($0); if (length(desc) > 160) got = 2; next }
  fmd = 0
  if ($0 ~ /^description:[[:space:]]*/) {
    t = $0; sub(/^description:[[:space:]]*/, "", t)
    if (t ~ /^[>|][-+]?[[:space:]]*$/ || t == "") { fmd = 1; next }
    gsub(/^["\047]+|["\047]+$/, "", t); add(t); got = 2
  }
  next
}
style == "hash" {
  if (FNR == 1 && $0 ~ /^#!/) next
  if (inpy) { t = $0; if (sub(/("""|\047\047\047).*$/, "", t)) inpy = 0; add(t); next }
  if ($0 ~ /^[[:space:]]*("""|\047\047\047)/) { t = $0; sub(/^[[:space:]]*("""|\047\047\047)/, "", t); if (!sub(/("""|\047\047\047).*$/, "", t)) inpy = 1; add(t); next }
  if ($0 ~ /^[[:space:]]*#/) { t = $0; sub(/^[[:space:]]*#+[[:space:]]?/, "", t); add(t); next }
  if ($0 ~ /^name:[[:space:]]/ && ext ~ /^(yml|yaml)$/) { t = $0; sub(/^name:[[:space:]]*/, "", t); gsub(/["\047]/, "", t); add(t); next }
  if ($0 ~ /[^[:space:]]/ && got > 0) { flush(); nextfile }
  next
}
style == "slash" {
  if ($0 ~ /^[[:space:]]*(\/\/+!?|\/\*+|\*+\/?)/) { t = $0; sub(/^[[:space:]]*(\/\/+!?|\/\*+|\*+)[[:space:]]?/, "", t); sub(/\*+\/[[:space:]]*$/, "", t); if (t !~ /^@/) add(t); next }
  if ($0 ~ /[^[:space:]]/ && got > 0) { flush(); nextfile }
  next
}
style == "md" {
  if ($0 ~ /^#{1,6}[[:space:]]/) { if (md_head == "") { md_head = $0; sub(/^#+[[:space:]]+/, "", md_head); add(md_head) } ; next }
  if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^(---|===|\||\[!\[|<|```|> \[!)/) next
  add(substr($0, 1, 140)); got = 2; next
}
style == "json" {
  if (match($0, /"(description|\/\/)"[[:space:]]*:[[:space:]]*"[^"]*"/)) { t = substr($0, RSTART, RLENGTH); sub(/^"[^"]*"[[:space:]]*:[[:space:]]*"/, "", t); sub(/"$/, "", t); add(substr(t, 1, 160)); got = 2 }
  next
}
END { flush() }
'

# Sentence units from agent-instruction markdown: src<TAB>sentence.
_RULES_AWK='
function unbold(s,   n, i, parts, o) {
  n = split(s, parts, "`"); o = ""
  for (i = 1; i <= n; i++) { if (i % 2 == 1) gsub(/\*\*/, "", parts[i]); o = o (i > 1 ? "`" : "") parts[i] }
  return o
}
function clean(s) { s = unbold(s); gsub(/[[:space:]]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
function emit_para(   s, rest, cut) {
  s = clean(para); para = ""; held = ""
  if (s == "") return
  if (!is_item && s ~ /:$/) { flush_lead(); lead = s; pending = s; return }
  if (is_item) pending = ""
  else flush_lead()
  if (is_item && lead != "") s = lead " " s
  # Abbreviations are not sentence ends.
  gsub(/(e\.g|i\.e|etc|vs|cf)\. /, "&\001", s); gsub(/\. \001/, ".\001", s)
  rest = s
  while (match(rest, /[.!?][)"]? +[A-Z`*("]/)) {
    cut = substr(rest, 1, RSTART + (substr(rest, RSTART + 1, 1) ~ /[)"]/ ? 1 : 0))
    out(cut); rest = substr(rest, RSTART + RLENGTH - 1)
  }
  out(rest); release()
}
# A lead-in ("… exit codes are load-bearing:") is kept as a unit of its own,
# with the rows of a table that follows it folded in; list items carry it as a prefix.
function flush_lead(   t) {
  if (pending != "") { t = pending (tbl != "" ? " " tbl : ""); held = t; release() }
  pending = ""; tbl = ""
}
# A sentence that leans on the previous one ("This keeps…", "It is…") is kept
# together with it, so no unit is a dangling fragment.
function out(t) {
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
  if (t == "") return
  if (held != "" && t ~ /^(This|That|These|Those|It|It.s|Its|They|Their|Same|Such|Both|Either|Otherwise|Also|So|Then|Here|There)[[:space:]]/) { held = held " " t; return }
  release(); held = t
}
function release(   t) {
  t = held; held = ""; gsub(/\001/, " ", t)
  if (length(t) < 30) return
  if (t ~ /^This file (provides|gives|contains)/) return
  print src "\t" head "\t" substr(t, 1, 500)
}
FNR == 1 { if (para != "") emit_para(); flush_lead(); src = FILENAME; fence = 0; para = ""; head = ""; lead = ""; is_item = 0 }
/^[[:space:]]*```/ { fence = !fence; if (para != "") emit_para(); next }
fence { next }
/^#/ { if (para != "") emit_para(); flush_lead(); head = $0; sub(/^#+[[:space:]]*/, "", head); gsub(/\*\*/, "", head); lead = ""; next }
/^[[:space:]]*\|/ {
  if (para != "") emit_para()
  if (pending != "" && $0 !~ /^[[:space:]]*\|[-:| ]+\|?[[:space:]]*$/) {
    row = $0; gsub(/^[[:space:]]*\||\|[[:space:]]*$/, "", row); gsub(/[[:space:]]*\|[[:space:]]*/, " ", row); row = clean(row)
    if (row != "") tbl = (tbl == "" ? row : tbl "; " row)
  }
  next
}
/^[[:space:]]*$/ { if (para != "") emit_para(); next }
/^[[:space:]]*<!--/ || /^---+$/ { if (para != "") emit_para(); flush_lead(); lead = ""; next }
/^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]/ { if (para != "") emit_para(); t = $0; sub(/^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]+/, "", t); para = t; is_item = 1; next }
{ if (para == "") { is_item = 0; if (tbl != "") flush_lead() } ; para = (para == "" ? $0 : para " " $0) }
END { if (para != "") emit_para(); flush_lead() }
'

# Shell commands: src<TAB>cmd from CI workflows (run: steps).
_CI_AWK='
function emit(c) {
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", c)
  if (c == "" || c ~ /^(#|echo |cd |export |set |if |fi$|then$|else$|done$|do$|for |while |\}|\{)/ || length(c) > 160) return
  if (c ~ /^(mkdir|ln|chmod|chown|rm|cp|mv|touch|cat|ls|sudo|apt(-get)?|brew|yum|dnf|apk|curl|wget|git (clone|config|fetch|checkout)|pip3? install|npm (ci|install)|pnpm install|yarn install|corepack) / || c ~ /--version/) return
  print FILENAME "\t" c
}
FNR == 1 { block = 0 }
block {
  match($0, /^[[:space:]]*/); ind = RLENGTH
  if ($0 ~ /^[[:space:]]*$/) next
  if (ind <= bind) block = 0
  else { emit($0); next }
}
/^[[:space:]]*(- )?run:[[:space:]]*[|>][-+]?[[:space:]]*$/ { block = 1; match($0, /^[[:space:]]*/); bind = RLENGTH; next }
/^[[:space:]]*(- )?run:[[:space:]]*[^|>[:space:]]/ { c = $0; sub(/^[[:space:]]*(- )?run:[[:space:]]*/, "", c); gsub(/^["\047]|["\047]$/, "", c); emit(c) }
'

# Fenced shell in docs: src<TAB>cmd.
_FENCE_AWK='
FNR == 1 { f = 0 }
/^[[:space:]]*```(bash|sh|shell|console|zsh|terminal)?[[:space:]]*$/ {
  if (f) { f = 0; next }
  lang = $0; gsub(/[[:space:]`]/, "", lang)
  if (lang ~ /^(bash|sh|shell|console|zsh|terminal)$/) f = 1
  else f = 2
  next
}
/^[[:space:]]*```/ { f = (f ? 0 : 2); next }
f == 1 {
  c = $0; sub(/^[[:space:]]*\$[[:space:]]+/, "", c); sub(/[[:space:]]+#[[:space:]].*$/, "", c)
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", c)
  if (c == "" || c ~ /^(#|cd |export |echo |\.\.\.|[A-Z_]+=|[\/~<>-])/ || c ~ /\\$/ || c ~ /<</ || c ~ /^[A-Z_]+$/ || length(c) > 160) next
  if (c ~ /^(mkdir|ln|chmod|chown|rm|cp|mv|touch|cat|ls|sudo|apt(-get)?|brew|curl|wget|git clone|npx skills|pip3? install|npm (ci|install|i) |pnpm (add|install)|yarn add)/) next
  print FILENAME "\t" c
}
'

_build_index() {
  local out="$1" files="$WORK/files.txt"
  : >"$WORK/cards.tsv"; : >"$WORK/rules.tsv"; : >"$WORK/cmds.tsv"; : >"$files"

  if [ "$IS_GIT" = true ]; then
    _tracked_files >"$files"
    if [ -s "$files" ]; then
      tr '\n' '\0' <"$files" | xargs -0 awk "$_CARDS_AWK" 2>/dev/null >"$WORK/cards.tsv" || true
    fi
  fi

  # Agent-instruction files: fixed paths, plus tracked CLAUDE.md/AGENTS.md up to depth 3.
  local rule_files="" f
  for f in CLAUDE.md AGENTS.md AGENT.md GEMINI.md CONVENTIONS.md CONTRIBUTING.md .github/CONTRIBUTING.md \
    docs/CONTRIBUTING.md .github/copilot-instructions.md .cursorrules .windsurfrules .clinerules; do
    [ -f "$f" ] && rule_files="$rule_files$f"$'\n'
  done
  if [ -s "$files" ]; then
    rule_files="$rule_files$(awk -F/ 'NF >= 2 && NF <= 4 && ($NF == "CLAUDE.md" || $NF == "AGENTS.md")' "$files")"$'\n'
    rule_files="$rule_files$(awk '/^\.cursor\/rules\/[^\/]+\.mdc?$/' "$files")"$'\n'
  fi
  rule_files=$(printf '%s' "$rule_files" | awk 'NF && !seen[$0]++' | awk 'NR <= 12')
  if [ -n "$rule_files" ]; then
    printf '%s\n' "$rule_files" | tr '\n' '\0' | xargs -0 awk "$_RULES_AWK" 2>/dev/null >"$WORK/rules.tsv" || true
  fi

  # Commands.
  local wf
  for wf in .github/workflows/*.yml .github/workflows/*.yaml .gitlab-ci.yml; do
    [ -f "$wf" ] && awk "$_CI_AWK" "$wf" >>"$WORK/cmds.tsv" 2>/dev/null || true
  done
  for f in CLAUDE.md AGENTS.md CONTRIBUTING.md .github/CONTRIBUTING.md docs/CONTRIBUTING.md README.md; do
    [ -f "$f" ] && awk "$_FENCE_AWK" "$f" >>"$WORK/cmds.tsv" 2>/dev/null || true
  done
  if [ -f package.json ]; then
    local pm=npm
    if [ -f pnpm-lock.yaml ]; then pm=pnpm; elif [ -f yarn.lock ]; then pm=yarn; elif [ -f bun.lockb ] || [ -f bun.lock ]; then pm=bun; fi
    jq -r --arg pm "$pm" '(.scripts // {}) | keys[] | if . == "test" then "\($pm) test" else "\($pm) run \(.)" end | "package.json\t" + .' \
      package.json >>"$WORK/cmds.tsv" 2>/dev/null || true
  fi
  for f in Makefile makefile GNUmakefile; do
    [ -f "$f" ] && awk -v src="$f" '/^[A-Za-z0-9][A-Za-z0-9_.\/-]*:([^=]|$)/ { t = $0; sub(/:.*/, "", t); if (t !~ /^\./ && !seen[t]++) print src "\tmake " t }' "$f" >>"$WORK/cmds.tsv" || true
  done
  for f in justfile Justfile; do
    [ -f "$f" ] && awk -v src="$f" '/^[A-Za-z0-9_-]+([[:space:]][^:=]*)?:([^=]|$)/ { t = $1; sub(/:.*/, "", t); if (!seen[t]++) print src "\tjust " t }' "$f" >>"$WORK/cmds.tsv" || true
  done
  [ -f Cargo.toml ] && printf 'Cargo.toml\t%s\n' "cargo test" "cargo build" "cargo clippy" >>"$WORK/cmds.tsv"
  [ -f go.mod ] && printf 'go.mod\t%s\n' "go test ./..." "go build ./..." "go vet ./..." >>"$WORK/cmds.tsv"
  if [ -f pyproject.toml ] || [ -f setup.cfg ] || [ -f pytest.ini ] || [ -f tox.ini ]; then
    printf 'pyproject.toml\t%s\n' "pytest" >>"$WORK/cmds.tsv"
    grep -q '^\[tool\.ruff' pyproject.toml 2>/dev/null && printf 'pyproject.toml\t%s\n' "ruff check ." >>"$WORK/cmds.tsv"
    grep -q '^\[tool\.mypy' pyproject.toml 2>/dev/null && printf 'pyproject.toml\t%s\n' "mypy ." >>"$WORK/cmds.tsv"
  fi
  if [ -f tsconfig.json ] && ! grep -q '"typecheck"' package.json 2>/dev/null; then
    printf 'tsconfig.json\t%s\n' "npx tsc --noEmit" >>"$WORK/cmds.tsv"
  fi

  # Project line: agent instructions first, then the README.
  local project=""
  for f in CLAUDE.md AGENTS.md README.md; do
    [ -f "$f" ] || continue
    project=$(awk "$_RULES_AWK" "$f" 2>/dev/null | awk -F'\t' '$3 !~ /^(This |Use |Run |See |Install|To |If |For |Note)/ { print $3; exit }' || true)
    [ -n "$project" ] && break
  done
  if [ -z "$project" ] && [ -f package.json ]; then
    project=$(jq -r '.description // empty' package.json 2>/dev/null || true)
  fi

  local tests_json='[]' changelog=""
  if [ -s "$files" ]; then
    tests_json=$(awk '
        /\.(md|txt|json|jsonl|xml|snap|csv|ya?ml)$/ { next }
        /(^|\/)(fixtures?|testdata|__snapshots__)\// { next }
        /(^|\/)(tests?|specs?|__tests__|testing)\// || /(^|\/)test_[^\/]*\.py$/ || /_test\.(go|py|rb|exs?)$/ || /[._-](test|spec)\.[A-Za-z0-9]+$/ || /smoke-test/ { print }
      ' "$files" | awk 'NR <= 100' | jq -R . | jq -sc .)
    changelog=$(awk 'tolower($0) ~ /^(changelog|changes|history|news)(\.(md|rst|txt))?$/ { print; exit }' "$files")
  fi

  pi_jev_redact <"$WORK/cards.tsv" >"$WORK/cards.red"
  pi_jev_redact <"$WORK/rules.tsv" >"$WORK/rules.red"
  pi_jev_redact <"$WORK/cmds.tsv" >"$WORK/cmds.red"

  jq -n \
    --rawfile cards "$WORK/cards.red" \
    --rawfile rules "$WORK/rules.red" \
    --rawfile cmds "$WORK/cmds.red" \
    --argjson tests "$tests_json" \
    --arg changelog "$changelog" \
    --arg project "$project" \
    --arg head "$(git rev-parse HEAD 2>/dev/null || true)" \
    '
    def rows($s): $s | split("\n") | map(select(length > 0) | split("\t"));
    {
      head: $head,
      files: (rows($cards) | map({path: .[0], card: (if (.[1] // "") == "" then .[0] else "\(.[0]) — \(.[1])" end)})),
      rules: (rows($rules) | map({src: .[0], section: (.[1] // ""), text: (.[2:] | join(" "))}) | map(select(.text != "")) | reduce .[] as $r ([]; if any(.[]; .text == $r.text) then . else . + [$r] end) | .[0:150]),
      commands: (rows($cmds) | map({src: .[0], cmd: (.[1:] | join(" "))}) | reduce .[] as $c ([]; if any(.[]; .cmd == $c.cmd) then . else . + [$c] end) | .[0:60]),
      tests: $tests,
      changelog: $changelog,
      project: $project
    }' >"$out"
}

INDEX="$WORK/index.json"
CACHED=false
if [ "$IS_GIT" = true ]; then
  CDIR=$(_cache_dir)
  KEY=$(_cache_key)
  if [ -s "$CDIR/$KEY.json" ] && jq -e '.files | type == "array"' "$CDIR/$KEY.json" >/dev/null 2>&1; then
    cp "$CDIR/$KEY.json" "$INDEX"
    CACHED=true
  else
    _build_index "$INDEX"
    if mkdir -p "$CDIR" 2>/dev/null; then
      cp "$INDEX" "$CDIR/$KEY.json.$$" 2>/dev/null && mv -f "$CDIR/$KEY.json.$$" "$CDIR/$KEY.json" 2>/dev/null || rm -f "$CDIR/$KEY.json.$$"
    fi
  fi
else
  _build_index "$INDEX"
fi

# ---------------------------------------------------------------------------
# Request-derived candidates
# ---------------------------------------------------------------------------

printf '%s' "$REQUEST" >"$WORK/request.txt"

# Entities by regex (jq/Oniguruma), then resolved against the index.
jq -n --rawfile r "$WORK/request.txt" --slurpfile idx "$INDEX" '
  def ents($kind; $re): [$r | scan($re) | if type == "array" then .[0] else . end | select(. != null)] | map({kind: $kind, text: .});
  ($idx[0].files | map(.path)) as $paths
  | ($paths | map({p: ., b: (split("/") | last)})) as $pb
  | (
      ents("url"; "https?://[^\\s)>\\]\"'"'"'`]+")
    + ents("flag"; "(?<![\\w/.$-])(--?[A-Za-z][A-Za-z0-9_-]*=[^\\s,;)`\"'"'"']+)")
    + ents("flag"; "(?<![\\w/.$-])(--?[A-Za-z][A-Za-z0-9_-]*)")
    + ents("env"; "\\b([A-Z][A-Z0-9]*_[A-Z0-9_]*[A-Z0-9])\\b")
    + ents("file"; "(?<![\\w@/.-])((?:[\\w.-]+/)*[\\w-]+\\.[A-Za-z][A-Za-z0-9]{0,6})(?![\\w/])")
    + ents("path"; "(?<![\\w@.-])((?:[\\w.-]+/)+[\\w.-]*)")
    + ents("code"; "`([^`\\n]{1,80})`")
    + ents("identifier"; "\\b(_?[a-z][a-z0-9]*(?:_[a-z0-9]+)+)\\b")
    + ents("identifier"; "\\b([a-z]+(?:[A-Z][a-z0-9]*)+)\\b")
    + ents("identifier"; "\\b((?:[A-Z][a-z0-9]+){2,})\\b")
    + ents("quoted"; "(?<![\\w])[\"'"'"']([^\"'"'"'\\n]{2,80})[\"'"'"'](?![\\w])")
    + ents("version"; "\\b(v?\\d+(?:\\.\\d+){1,3}|v\\d+)\\b")
    + ents("quantity"; "(?i)\\b(\\d+(?:\\.\\d+)?\\s?(?:ms|s|secs?|seconds?|minutes?|mins?|hours?|days?|weeks?|months?|years?|%|kb|mb|gb|x|requests?|rps|qps|px|rem|em)(?:\\s(?:per|a|an)\\s\\w+)?)\\b")
    + ents("number"; "(?<![\\w.])(\\d+)(?![\\w.])")
    )
  | map(select(.text | test("^(e\\.g|i\\.e|etc\\.?|vs\\.?)$") | not))
  # Bare names of tracked files, e.g. README, CONTRIBUTING (ALLCAPS or containing - _ .).
  | . + ([$r | scan("\\b([A-Za-z][A-Za-z0-9_.-]{3,})\\b")] | map(.[0])
        | map(select(test("^[A-Z0-9_]+$") or test("[-_.]")))
        | map(. as $w | select(any($pb[]; (.b | sub("\\.[A-Za-z0-9]+$"; "")) == $w)) | {kind: "file", text: $w}))
  | reduce .[] as $e ([]; if any(.[]; .text == $e.text) then . else . + [$e] end)
  | map(if .kind == "file" or .kind == "path" or .kind == "code" then
        . as $e | ($e.text | sub("^\\./"; "") | sub("/$"; "")) as $t
        | ($pb | map(select(.p == $t or (.p | endswith("/" + $t)) or .b == $t or (.b | sub("\\.[A-Za-z0-9]+$"; "")) == $t) | .p)) as $hits
        | ($pb | map(select(.p | startswith($t + "/")) | .p) | .[0:5]) as $dir
        | if ($hits | length) > 0 then $e + {paths: $hits[0:10]}
          elif ($dir | length) > 0 then $e + {kind: "path", paths: $dir}
          else $e end
      else . end)
  | to_entries | map(.value + {id: "e\(.key)"})
' >"$WORK/entities.json"

# git grep references for identifier-like entities (bounded).
if [ "$IS_GIT" = true ]; then
  jq -r '.[] | select(.kind == "env" or .kind == "identifier" or (.kind == "code" and (.text | test("^[A-Za-z_][A-Za-z0-9_.-]{3,}$")))) | .id + "\t" + .text' \
    "$WORK/entities.json" | awk 'NR <= 8' >"$WORK/idents.tsv" || true
  : >"$WORK/refs.tsv"
  while IFS=$'\t' read -r eid etext; do
    [ -n "$etext" ] || continue
    git grep -n -I -F -w -e "$etext" -- . 2>/dev/null \
      | awk -v id="$eid" 'NR <= 30 { line = substr($0, 1, 200); print id "\t" line }' >>"$WORK/refs.tsv" || true
  done <"$WORK/idents.tsv"
  pi_jev_redact <"$WORK/refs.tsv" >"$WORK/refs.red"
  jq --rawfile refs "$WORK/refs.red" '
    ($refs | split("\n") | map(select(length > 0) | split("\t") | {id: .[0], ref: (.[1:] | join(" "))})) as $rs
    | map(. as $e | ([$rs[] | select(.id == $e.id) | .ref]) as $mine | if ($mine | length) > 0 then $e + {refs: $mine} else $e end)
  ' "$WORK/entities.json" >"$WORK/entities2.json" && mv "$WORK/entities2.json" "$WORK/entities.json"
fi

# Spans, words and the final object. Files beyond MAX_CARDS are ranked by
# overlap with request words and entity hits, so large repos keep the likely ones.
jq -n \
  --rawfile r "$WORK/request.txt" \
  --slurpfile idx "$INDEX" \
  --slurpfile ents "$WORK/entities.json" \
  --argjson max "$MAX_CARDS" \
  --argjson cached "$CACHED" \
  '
  def words_of($s): $s | gsub("[\\s]+"; " ") | split(" ") | map(select(length > 0) | sub("^[(\\[\"'"'"']+"; "") | sub("[)\\]\"'"'"',;:.!?]+$"; "")) | map(select(length > 0));
  def stop: ["the","and","for","with","that","this","from","into","when","what","which","then","than","them","they","its","it'"'"'s","are","was","were","has","have","had","not","but","our","you","your","all","any","can","could","should","would","will","just","also","make","made","does","did","get","got","about","after","before","there","their","these","those","each","some","such","only","other","over","under","very","more","most","out","use","using","used","way","now","new","add"];
  ($ents[0]) as $E
  | words_of($r) as $w
  | ($w | length) as $n
  # Spans: every span of up to 12 words for short requests; clause-bounded for long ones.
  | (if $n <= 26 then
       [range(0; $n) as $i | range(1; 13) as $l | select($i + $l <= $n) | $w[$i:$i + $l] | join(" ")]
     else
       ($r | gsub("\\s+"; " ") | [splits("(?<=[.;:!?,])\\s+|\\s+(?=(?:and|but|so|then|which|that|while|without|unless|because|when|if|or)\\s)")]
         | map(words_of(.)) | map(select(length > 0))) as $clauses
       | ([$clauses[] | .[0:16] | join(" ")]
          + [$clauses[] as $c | ($c | length) as $cn | range(12; 1; -1) as $l | range(0; $cn) as $i | select($i + $l <= $cn and $l < $cn) | $c[$i:$i + $l] | join(" ")])
     end) as $all
  | ($all | reduce .[] as $s ([]; if index([$s]) then . else . + [$s] end) | .[0:250]) as $spans
  # Words: each token, plus its alphanumeric parts ("--format=tsv" gives "format" and "tsv").
  | ([$w[] | ascii_downcase | ., (splits("[^a-z0-9]+") | select(length > 0))]
     | map(select(length >= 3 and test("^[a-z][a-z0-9_-]*$") and (. as $x | stop | index([$x]) | not)))
     | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end) | .[0:120]) as $words
  # Card ranking (only matters above $max).
  | ([$words[] | select(length >= 4)]) as $kw
  | ([$E[] | (.paths // [])[]]) as $hit_paths
  | ([$E[] | (.refs // [])[] | split(":")[0]]) as $ref_paths
  | ($idx[0].files | length) as $nf
  | (if $nf <= $max then $idx[0].files
     else
       ($idx[0].files | map(. as $f | ($f.path | ascii_downcase) as $lp
          | {f: $f, s: ((if ($hit_paths | index([$f.path])) then 100 else 0 end)
                       + (if ($ref_paths | index([$f.path])) then 20 else 0 end)
                       + ([$kw[] | select(. as $k | $lp | contains($k))] | length) * 5
                       + (if ($f.path | test("(^|/)(README|CLAUDE|AGENTS|CONTRIBUTING)\\.md$")) then 3 else 0 end))})
        | sort_by(-.s) | .[0:$max] | sort_by(.f.path) | map(.f))
     end) as $files
  | $idx[0] + {
      request: $r,
      entities: $E,
      spans: $spans,
      words: $words,
      files: $files,
      files_total: $nf,
      meta: {cached: $cached, index_version: '"$INDEX_VERSION"'}
    }
'
