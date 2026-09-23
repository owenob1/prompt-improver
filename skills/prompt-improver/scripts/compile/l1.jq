# scripts/compile/l1.jq
# L1: the one wide Jev call. State = the request only; every candidate goes into
# its own question ("candidate in question"), because rows packed into the state
# lose accuracy with position.
#
# jq -n --slurpfile c cands.json --slurpfile lib cells.json --slurpfile q _questions.json \
#       --arg model jev-1.13.0 -f l1.jq
#
# Question keys (read back by understand.jq):
#   core keys from _questions.json · cell · fit_<ci>_<id> · slot_<ci>_<name>
#   role_<name> · file_<i> · rule_<i> · tfile_<i>
# Request-independent questions (command roles, the rule prior) live in prior.jq.

# A rule is shown with where it came from, so Jev can judge its scope.
def rule_text: .text[0:500] + " (from " + .src + (if (.section // "") != "" then ", section \"" + .section + "\"" else "" end) + ")";
def key: ascii_downcase | gsub("[^a-z0-9_]"; "_");
def options($pfx; $arr): $arr | to_entries | map({key: "\($pfx)\(.key)", value: .value}) | from_entries;

($c[0]) as $c
| ($lib[0]) as $lib
| ($q[0]) as $q
| ($c.entities // []) as $E
| ($c.words // []) as $W
| ($c.spans // []) as $S
| ($c.tests // []) as $T
# Entity ids are "e<N>"; option keys reuse them so answers map straight back.
| def entity_opts($accept):
    [$E[] | select(.kind as $k | $accept | index([$k]))] | map({key: .id, value: "\(.text) (\(.kind))"}) | from_entries;
  def word_opts: options("w"; $W);
  def span_opts: options("s"; $S);
  def slot_q($ci; $name; $s):
    (if $s.kind == "entity" then entity_opts($s.accept // []) + (if (($s.accept // []) | index(["word"])) then word_opts else {} end)
     elif $s.kind == "word" then word_opts
     elif $s.kind == "span" then span_opts
     else {} end) as $o
    | if ($o | length) == 0 then empty
      else {key: "slot_\($ci)_\($name | key)", value: {type: "choice", instructions: $s.q, criteria: ({none: $q.slot_none} + $o)}}
      end;
  # Files whose lines mention an identifier from the request say so on their card.
  ([$E[] | select(.refs) | .text as $t | .refs[] | {path: (split(":")[0]), t: $t}]
   | group_by(.path) | map({key: .[0].path, value: (map(.t) | unique)}) | from_entries) as $mentions
| {
    model: $model,
    state: {request: $c.request},
    questions: (
      $q.core
      + (if ($lib | length) > 0 then
           {cell: {type: "choice", instructions: $q.cell,
                   criteria: ({none: $q.cell_none} + ($lib | to_entries | map({key: "c\(.key)", value: .value.match}) | from_entries))}}
         else {} end)
      + ([$lib | to_entries[] | .key as $ci | (.value.fit // [])[]
          | {key: "fit_\($ci)_\(.id | key)", value: {type: "noul", instructions: .q}}] | from_entries)
      + ([$lib | to_entries[] | .key as $ci | (.value.slots // {}) | to_entries[] | slot_q($ci; .key; .value)] | from_entries)
      + (if ($S | length) > 0 then
           ($q.roles | to_entries | map({key: "role_\(.key)", value: {type: "choice", instructions: .value,
                                        criteria: ({none: $q.role_none} + span_opts)}}) | from_entries)
         else {} end)
      + ([$c.files | to_entries[]
          | ($mentions[.value.path] // []) as $m
          | {key: "file_\(.key)",
             value: {type: "noul",
                     instructions: ($q.file + .value.card
                                    + (if ($m | length) > 0 then " (mentions " + ($m | map("`\(.)`") | join(", ")) + ")" else "" end))}}]
         | from_entries)
      + ([$c.rules | to_entries[] | {key: "rule_\(.key)", value: {type: "noul", instructions: ($q.rule + (.value | rule_text))}}] | from_entries)
      + ([$T | to_entries[]
          | .value as $tp | ([$c.files[] | select(.path == $tp) | .card] | first // $tp) as $card
          | {key: "tfile_\(.key)", value: {type: "noul", instructions: ($q.test_file + $card)}}] | from_entries)
    )
  }
