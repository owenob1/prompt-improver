# scripts/compile/understand.jq
# Turns raw Jev answers into one decision sheet.
#
# jq -n --slurpfile c cands.json --slurpfile lib cells.json --slurpfile a1 l1.json \
#       --slurpfile ap prior.json --slurpfile ab l1b.json --slurpfile t target.json \
#       --argjson cfg '{…}' -f understand.jq
# (a1/ap/ab are Jev responses {answers: …}; pass {} for a call that did not run,
#  and {} for target.json when no target was resolved.)
#
# cfg: margin, cell_min, slot_min, rule_min, rule_max, command_min, test_min, allow_unreviewed

($c[0]) as $c
| ($lib[0]) as $lib
| ($a1[0].answers // {}) as $A
| ($ap[0].answers // {}) as $P
| ($ab[0].answers // {}) as $B
| ($t[0] // {}) as $T
| ($cfg.margin // 0.05) as $m
| def pmax($x): if $x == null then null else ($x.probabilities[$x.choice] // 0) end;
  def picked($x): if $x == null or $x.choice == null or $x.choice == "none" then null else $x.choice end;
  def idx($k; $pfx): ($k | ltrimstr($pfx) | tonumber? // null);
  def noul($k): ($A[$k].noul // null);
  def passes($g; $p):
    if $p == null then false
    elif $g.min != null then $p >= ($g.min + $m)
    elif $g.max != null then $p <= ($g.max - $m)
    else false end;
  def key: ascii_downcase | gsub("[^a-z0-9_]"; "_");

  # Core.
  {
    triage: {choice: ($A.triage.choice // null), p: pmax($A.triage)},
    complexity: ($A.complexity.score // null),
    risk: ($A.risk.score // null),
    clarity: ($A.clarity.score // null),
    multi_task: ([noul("multi_unrelated"), noul("multi_deliverables"), noul("multi_task")] | map(select(. != null)) | if length == 0 then null else max end),
    needs_research: noul("needs_research"),
    ui: noul("ui"),
    autonomous: noul("autonomous"),
    needs_test: noul("needs_test"),
    user_facing: noul("user_facing")
  } as $core

  # Roles: argmax span, or null for "none".
  | ([($A | to_entries[] | select(.key | startswith("role_")))
      | {key: (.key | ltrimstr("role_")),
         value: (picked(.value) as $ch | if $ch == null then null
                 else {text: $c.spans[idx($ch; "s")], p: pmax(.value)} end)}] | from_entries) as $roles

  # Files by relevance.
  | ([$c.files | to_entries[] | {path: .value.path, p: ($A["file_\(.key)"].noul // 0)}] | sort_by(-.p) | .[0:10]) as $files

  # Rules: request score + target-premised score − neutral prior, kept in document order.
  | ([$c.rules | to_entries[]
      | select(.value.text != ($c.project // ""))
      | ($A["rule_\(.key)"].noul // null) as $p
      | select($p != null)
      | ($B["trule_\(.key)"].noul // $p) as $tp
      | ($P["prior_\(.key)"].noul // 0.5) as $p0
      | {i: .key, src: .value.src, text: .value.text, p: $p, tp: $tp, p0: $p0, score: ((($p + $tp - $p0) * 100 | round) / 100)}]
     | map(select(.score >= ($cfg.rule_min // 0.75) and .p >= ($cfg.rule_floor // 0.45)))
     | sort_by(-.score) | .[0:($cfg.rule_max // 6)] | sort_by(.i)) as $rules

  # Commands from the repo prior: best candidate per role.
  | ([$c.commands | to_entries[]
      | $P["cmd_\(.key)"] as $x
      | select($x != null)
      | {i: .key, cmd: .value.cmd, src: .value.src, role: $x.choice, p: pmax($x)}]
     | map(select(.p >= ($cfg.command_min // 0.6) and .role != "other"))
     | group_by(.role) | map(sort_by(-.p, .i) | .[0]) | map({key: .role, value: {cmd, src, p}}) | from_entries) as $cmds

  # Test file: the test file that already exercises the target (most references),
  # else the highest yes/no among test-file candidates.
  | ([($T.refs // [])[] | .path as $p | select(($c.tests // []) | index([$p]))] | group_by(.path)
     | map({path: .[0].path, refs: length}) | sort_by(-.refs, .path) | .[0] // null) as $covered
  | (if $covered != null then {path: $covered.path, p: 1, source: "existing coverage (\($covered.refs) references to \($T.name))"}
     else
       ([$c.tests // [] | to_entries[] | {path: .value, p: ($A["tfile_\(.key)"].noul // 0), source: "jev"}]
        | sort_by(-.p) | .[0] // null
        | if . != null and .p >= ($cfg.test_min // 0.5) then . else null end)
     end) as $test_file

  # Cell choice and fits.
  | (if $A.cell == null then null
     else
       ($A.cell.probabilities // {} | to_entries | map(select(.key != "none")) | sort_by(-.value)
        | map({index: idx(.key; "c"), id: $lib[idx(.key; "c")].id, p: .value})) as $ranking
       | picked($A.cell) as $ch
       | if $ch == null then {index: null, id: null, p: (1 - ($A.cell.probabilities.none // 0)), ranking: $ranking, fit_ok: false}
         else
           idx($ch; "c") as $ci | $lib[$ci] as $cell
           | ([($cell.fit // [])[] | . as $f | {id: $f.id, p: ($A["fit_\($ci)_\($f.id | key)"].noul // null), ok: passes($f; ($A["fit_\($ci)_\($f.id | key)"].noul // null))}]) as $fits
           | {index: $ci, id: $cell.id, p: pmax($A.cell), ranking: $ranking,
              fits: $fits, fit_ok: (($fits | all(.ok)) and (pmax($A.cell) >= ($cfg.cell_min // 0.5))),
              reviewed: ($cell.provenance.reviewed_by != null)}
         end
     end) as $cellsel

  # Slots of the chosen cell.
  | (if $cellsel == null or $cellsel.index == null then {}
     else
       $cellsel.index as $ci
       | ($lib[$ci].slots // {}) | to_entries | map(
           .key as $name | .value as $s
           | if $s.kind == "role" then
               {key: $name, value: (if $roles[$s.role] == null then null else {value: $roles[$s.role].text, p: $roles[$s.role].p, source: "role:\($s.role)"} end)}
             else
               $A["slot_\($ci)_\($name | key)"] as $x
               | picked($x) as $ch
               | {key: $name,
                  value: (if $ch == null or pmax($x) < ($cfg.slot_min // 0.5) then null
                          elif ($ch | startswith("e")) then ([$c.entities[] | select(.id == $ch)] | first) as $e | {value: $e.text, p: pmax($x), source: $ch, paths: ($e.paths // [])}
                          elif ($ch | startswith("w")) then {value: $c.words[idx($ch; "w")], p: pmax($x), source: $ch}
                          elif ($ch | startswith("s")) then {value: $c.spans[idx($ch; "s")], p: pmax($x), source: $ch}
                          else null end)}
             end) | from_entries
     end) as $slots

  | {core: $core, cell: $cellsel, slots: $slots, roles: $roles, files: $files,
     rules: $rules, commands: $cmds, test_file: $test_file}
