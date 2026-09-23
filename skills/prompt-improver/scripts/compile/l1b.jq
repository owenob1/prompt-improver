# scripts/compile/l1b.jq
# L1b: questions that need the target file in the state. Runs in parallel with L1
# when L0 already resolved the target, otherwise right after it.
#
# jq -n --slurpfile c cands.json --slurpfile lib cells.json --slurpfile q _questions.json \
#       --slurpfile t target.json --argjson cells '[0,2]' --arg model jev-1.13.0 -f l1b.jq
#
# State: {request, target: {path, summary, usage}}.
# Question keys: g_<ci>_<guard id> (item, requires and escalate guards of the listed cells),
#                trule_<i> (rule relevance premised on the target).

# A rule is shown with where it came from, so Jev can judge its scope.
def rule_text: .text[0:500] + " (from " + .src + (if (.section // "") != "" then ", section \"" + .section + "\"" else "" end) + ")";
def key: ascii_downcase | gsub("[^a-z0-9_]"; "_");

($c[0]) as $c
| ($lib[0]) as $lib
| ($q[0]) as $q
| ($t[0]) as $t
| {
    model: $model,
    state: {request: $c.request, target: {path: $t.path, summary: $t.summary, usage: $t.usage}},
    questions: (
      ([$cells[] as $ci | $lib[$ci] as $cell
        | (([$cell.items[]? | .guards[]?] + ($cell.requires // []) + ($cell.escalate // [])) | map(select(.q)) | unique_by(.id))[]
        | {key: "g_\($ci)_\(.id | key)", value: {type: "noul", instructions: .q}}] | from_entries)
      + ([$c.rules | to_entries[]
          | {key: "trule_\(.key)", value: {type: "noul", instructions: ($q.target_rule + (.value | rule_text))}}] | from_entries)
    )
  }
