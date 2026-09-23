# scripts/compile/prior.jq
# Request-independent questions about the repository, cached with every other
# Jev answer (the request JSON is the cache key, so this call is made once per
# repository state):
#   prior_<i>  rule relevance for a neutral request; subtracted from the per-request
#              scores so that rules which score high for every request ("attractors")
#              do not crowd out the relevant ones
#   cmd_<i>    what each candidate command does (test, lint, typecheck, build, …)
#
# jq -n --slurpfile c cands.json --slurpfile q _questions.json --arg model jev-1.13.0 -f prior.jq

# A rule is shown with where it came from, so Jev can judge its scope.
def rule_text: .text[0:500] + " (from " + .src + (if (.section // "") != "" then ", section \"" + .section + "\"" else "" end) + ")";
($c[0]) as $c
| ($q[0]) as $q
| {
    model: $model,
    state: {request: $q.prior_request},
    questions: (
      ([$c.rules | to_entries[] | {key: "prior_\(.key)", value: {type: "noul", instructions: ($q.rule + (.value | rule_text))}}] | from_entries)
      + ([$c.commands | to_entries[]
          | {key: "cmd_\(.key)", value: {type: "choice", instructions: ($q.command_role.instructions + .value.cmd), criteria: $q.command_role.criteria}}]
         | from_entries)
    )
  }
