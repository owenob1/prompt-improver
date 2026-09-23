# scripts/compile/ground.jq
# Tier C: the repo facts Jev selected, as a block for the full LLM generation
# prompt. The generator runs with no tools, so without this block it never sees
# the target's usage text, its callers, the right test command or the rules
# that apply. Every line here is a verbatim candidate or a Jev choice among them.
#
# jq -n -r --slurpfile c cands.json --slurpfile u understanding.json --slurpfile t target.json \
#          --slurpfile lib cells.json --slurpfile cmp compiled.json -f ground.jq

($c[0]) as $c
| ($u[0]) as $u
| ($t[0] // {}) as $t
| ($cmp[0] // null) as $cmp
| def yn($p): if $p == null then "unknown" elif $p >= 0.5 then "yes" else "no" end;
  def num($x): if $x == null then "?" else (($x * 10 | round) / 10 | tostring) end;
[
  "=== JEV GROUNDING (repository facts selected for this request by a fast classifier; verify before relying on them) ===",
  "",
  "Request analysis: complexity \(num($u.core.complexity))/3, risk \(num($u.core.risk))/2, clarity \(num($u.core.clarity))/2, multi-part: \(yn($u.core.multi_task)), needs external research: \(yn($u.core.needs_research)), UI change: \(yn($u.core.ui)).",
  (if ($u.roles | to_entries | map(select(.value != null)) | length) > 0 then
     "Parts of the request: " + ($u.roles | to_entries | map(select(.value != null) | "\(.key | gsub("_"; " ")): \"\(.value.text)\"") | join("; ")) + "."
   else empty end),
  (if $t.path then
     "",
     "Most likely file to change: `\($t.path)`" + (if ($t.summary // "") != "" then " (\($t.summary))" else "" end) + ".",
     (if ($t.usage // "") != "" then "Its own header and usage text:", "```", $t.usage, "```" else empty end),
     (if ($t.callers // []) | length > 0 then "Files that invoke it: " + ($t.callers | map("`\(.)`") | join(", ")) + "." else empty end)
   else empty end),
  ([$u.files[] | select(.p >= 0.5 and .path != $t.path)] | if length > 0 then
     "", "Other files the request may touch: " + (map("`\(.path)`") | join(", ")) + "."
   else empty end),
  (if ($u.rules | length) > 0 then
     "", "Project rules that apply to this change:", ($u.rules[] | "- " + .text)
   else empty end),
  (if ($u.commands | length) > 0 then
     "", "Project commands: " + ($u.commands | to_entries | map("\(.key): `\(.value.cmd)`") | join("; ")) + "."
   else empty end),
  (if $u.test_file != null then "Automated tests for this change most likely belong in `\($u.test_file.path)`." else empty end),
  (if ($c.changelog // "") != "" then "The project keeps a changelog in `\($c.changelog)`." else empty end),
  (if $cmp != null and ($cmp.emitted // [] | length) > 0 then
     "",
     "Library practice for this kind of change (cell `\($u.cell.id)`; each item passed its applicability checks for this request; adapt, do not copy blindly):",
     ($cmp.emitted[] | select(.text != null and (.id | startswith("cover-") | not)) | "- [\(.section)] " + .text)
   else empty end),
  "",
  "=== END JEV GROUNDING ==="
] | join("\n")
