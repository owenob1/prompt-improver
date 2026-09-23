# scripts/compile/compile.jq
# L2 + L3: compile one library cell into an XML spec. Nothing here is generated:
# every line is a library item, filled from verbatim candidates, emitted only if
# all of its guards pass. Each item's fate is recorded in the trace.
#
# jq -n --slurpfile c cands.json --slurpfile lib cells.json --slurpfile u understanding.json \
#       --slurpfile ab l1b.json --slurpfile t target.json --rawfile src target-source.txt \
#       --argjson ci 0 --argjson cfg '{"margin":0.05}' -f compile.jq
#
# Output: {ok, reason?, xml, trace, gaps, slots, stats}
#   gaps: [{section, mode: fill|augment, need, have, reason}]  (Tier B writes these)

def key: ascii_downcase | gsub("[^a-z0-9_]"; "_");
def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
def kebab: ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-+|-+$"; "");
def ind($n): ([range(0; $n)] | map(" ") | join(""));

($c[0]) as $c
| ($lib[0]) as $lib
| ($u[0]) as $u
| ($ab[0].answers // {}) as $B
| ($t[0] // {}) as $t
| ($cfg.margin // 0.05) as $m
| $lib[$ci] as $cell

# ---- slot values -----------------------------------------------------------
| ($c.tests // []) as $tests
| ($u.test_file.path // null) as $test_file
| {
    tool_path: ($t.path // null),
    tool_name: ($t.stem // null),
    runner: ($t.runner // null),
    tool_summary: ($t.summary // null),
    syntax_check: ($t.syntax_check // null),
    test_file: $test_file,
    test_cmd: ($u.commands.test.cmd // null),
    typecheck_cmd: ($u.commands.typecheck.cmd // null),
    lint_cmd: ($u.commands.lint.cmd // null),
    build_cmd: ($u.commands.build.cmd // null),
    changelog: ($c.changelog // null),
    project: ($c.project // null),
    callers: (($t.callers // []) | map(select(. as $p | ($tests | index([$p]) | not) and $p != $test_file))
              | if length == 0 then null else map("`\(.)`") | join(", ") end)
  } as $builtin
| ($cell.slots // {} | keys) as $cell_slot_names
| ($builtin + ([$cell_slot_names[] | {key: ., value: ($u.slots[.].value // null | if . == null then null else esc end)}] | from_entries)) as $vals
| ($vals | with_entries(select(.value == "" )) | keys) as $empty
| ($vals | with_entries(if .value == "" then .value = null else . end)) as $vals
| ($cell_slot_names + ($builtin | keys)) as $known

| def fill($s): reduce ($known[]) as $k ($s; if $vals[$k] == null then . else gsub("\\{" + $k + "\\}"; $vals[$k]) end);
  def missing($s): [$s | scan("\\{([a-z_]+)\\}") | .[0] | select(. as $k | $known | index([$k])) | select($vals[.] == null)] | unique;
  def gp($g): $B["g_\($ci)_\($g.id | key)"].noul // null;
  def eval_guard($g):
    if $g.fact != null then
      (fill($g.text // "")) as $needle
      | (if ($src | length) == 0 or ($needle | test("\\{[a-z_]+\\}")) then null
         elif $g.fact == "target_lacks" then ($src | contains($needle) | not)
         elif $g.fact == "target_has" then ($src | contains($needle))
         else null end) as $r
      | {id: $g.id, fact: $g.fact, text: $needle, pass: ($r == true)}
    else
      gp($g) as $p
      | {id: $g.id, p: $p,
         need: (if $g.min != null then ">= \($g.min + $m)" else "<= \($g.max - $m)" end),
         pass: (if $p == null then false elif $g.min != null then $p >= ($g.min + $m) else $p <= ($g.max - $m) end)}
    end;

# ---- cell-level requirements ----------------------------------------------
  ([($cell.requires // [])[] | eval_guard(.)]) as $requires
| ([($cell.escalate // [])[] | . as $e | eval_guard($e) + {gap: $e.gap}]) as $escalate

# ---- items -------------------------------------------------------------------
| ([$cell.items[] | . as $it
    | ([$it.text, $it.input, $it.output, $it.reasoning, $it.file] | map(select(. != null)) | map(missing(.)) | add | unique) as $miss
    | ([($it.guards // [])[] | eval_guard(.)]) as $gs
    | {id: $it.id, section: $it.section,
       status: (if ($miss | length) > 0 then "dropped" elif ($gs | all(.pass)) then "emitted" else "dropped" end),
       reasons: ((if ($miss | length) > 0 then [$miss[] | "slot:" + .] else [] end) + [$gs[] | select(.pass | not) | "guard:" + .id]),
       guards: $gs,
       text: (if $it.text then fill($it.text) else null end),
       input: (if $it.input then fill($it.input) else null end),
       output: (if $it.output then fill($it.output) else null end),
       reasoning: (if $it.reasoning then fill($it.reasoning) else null end),
       file: (if $it.file then fill($it.file) else null end)}
   ]) as $trace
| [$trace[] | select(.status == "emitted")] as $E
| def sec($s): [$E[] | select(.section == $s)];
  def sec_prefix($p): [$E[] | select(.section | startswith($p))];
  def bullets($items; $n): if ($items | length) == 0 then empty else $items | map(ind($n) + "- " + .text) | join("\n") end;

# ---- L3 coverage: request roles that no emitted line carries ------------------
  ([$E[] | (.text // ""), (.input // ""), (.output // "")] | join("\n") | ascii_downcase) as $body
| ([ [["desired", "Required outcome"], ["constraint", "Constraint from the request"], ["metric", "Measure from the request"], ["symptom", "Symptom that must no longer occur"]][]
    | . as [$r, $lbl]
    | ($u.roles[$r].text // null) as $txt
    | select($txt != null and ($txt | length) > 3)
    | select(($body | contains($txt | ascii_downcase)) | not)
    | {id: "cover-\($r)", section: "requirements.request", status: "emitted", reasons: [], guards: [],
       text: "\($lbl): \"\($txt | esc)\"."}]) as $cover
| ($E + $cover) as $E

# ---- gaps ----------------------------------------------------------------------
| ($cell.required // {} | if type == "array" then map({key: ., value: 1}) | from_entries else . end) as $req
| ([$req | to_entries[] | .key as $s | .value as $need
    | ([$E[] | select(.section == $s or (.section | startswith($s + ".")))] | length) as $have
    | select($have < $need)
    | {section: $s, mode: "fill", need: $need, have: $have, reason: "required \($s): \($have)/\($need)"}]
   + [$escalate[] | select(.pass) | .gap as $g | {section: $g, mode: "augment", need: 0, have: ([$E[] | select(.section == $g)] | length), reason: "escalate:\(.id)"}]) as $gaps
| ($gaps | map(.section)) as $gap_secs
| def gap($s; $n): if ($gap_secs | index([$s])) then ind($n) + "<!-- GAP:\($s) -->" else empty end;
  def has_gap($s): ($gap_secs | index([$s])) != null;

# ---- render --------------------------------------------------------------------
  (sec("companion")) as $comp
| ([$comp[] | .file] | unique) as $comp_files
| (($cell.task_name // $cell.id) | fill(.) | kebab) as $task_name
| ([$u.files[]? | select(.p >= 0.6 and .path != $t.path) | .path]) as $also
| ($c.request | esc) as $request
| ([sec_prefix("requirements.")[] | .section | ltrimstr("requirements.")] | reduce .[] as $g ([]; if index([$g]) then . else . + [$g] end)) as $groups
| (
    [
      "<context>",
      (if ($vals.project // null) != null then "  <project>\($vals.project)</project>" else empty end),
      "  <scope>",
      (if $t.path then "    - `\($t.path)` (the file to change)" else empty end),
      ($comp_files[] | "    - `\(.)`"),
      ($also[] | "    - `\(.)` (likely affected; confirm before editing)"),
      "  </scope>",
      (sec("current") | if length > 0 then "  <current-behavior>" + (map(.text) | join(" ")) + "</current-behavior>" else empty end),
      (sec("desired") | if length > 0 or has_gap("desired") then "  <desired-behavior>" + (map(.text) | join(" ")) + (if has_gap("desired") then " <!-- GAP:desired -->" else "" end) + "</desired-behavior>" else empty end),
      (if ($u.rules | length) > 0 then "  <conventions>", ($u.rules[] | "    - " + (.text | esc)), "  </conventions>" else empty end),
      "  <user-request>",
      ($request | split("\n")[] | "    " + .),
      "  </user-request>",
      "</context>",
      "",
      "<task id=\"1\" name=\"\($task_name)\">",
      "  <description>" + (sec("description") | map(.text) | join(" ")) + (if has_gap("description") then " <!-- GAP:description -->" else "" end) + "</description>",
      (sec("approach") | if length > 0 or has_gap("approach") then "", "  <approach>", "    Before implementing, reason through:", bullets(.; 4), gap("approach"; 4), "  </approach>" else empty end),
      (if ($groups | length) > 0 or has_gap("requirements") then
         "", "  <requirements>",
         ($groups[] as $g | "    <group name=\"\($g)\">", bullets(sec("requirements." + $g); 6), "    </group>"),
         (if has_gap("requirements") then "    <group name=\"specific\">", gap("requirements"; 6), "    </group>" else empty end),
         "  </requirements>"
       else empty end),
      (sec("example") | if length > 0 or has_gap("example") then
         "", "  <examples>",
         (.[] | "    <example>", "      <input>\(.input)</input>", "      <output>\(.output)</output>", "      <reasoning>\(.reasoning)</reasoning>", "    </example>"),
         gap("example"; 4),
         "  </examples>"
       else empty end),
      "",
      "  <verification>",
      bullets(sec("verification"); 4),
      gap("verification"; 4),
      "  </verification>",
      "</task>",
      (if ($comp | length) > 0 then
         "",
         "<task id=\"2\" name=\"regression-coverage-and-changelog\" depends-on=\"1\">",
         "  <description>Record the change where the project keeps its tests and history.</description>",
         "  <requirements>",
         ($comp[] | "    - In `\(.file)`: \(.text)"),
         "  </requirements>",
         "  <verification>",
         (if $vals.test_cmd != null then "    - `\($vals.test_cmd)` passes." else empty end),
         "    - `git diff --name-only` lists " + ($comp_files | map("`\(.)`") | join(" and ")) + ".",
         "  </verification>",
         "</task>"
       else empty end),
      "",
      "<execution>",
      "  <strategy>" + (if ($comp | length) > 0 then "Sequential: task 2 depends on task 1." else "Single task; finish it completely before reporting." end) + "</strategy>",
      (sec("constraint") | if length > 0 or has_gap("constraint") then "  <constraints>", bullets(.; 4), gap("constraint"; 4), "  </constraints>" else empty end),
      (sec("out_of_scope") | if length > 0 then "  <out-of-scope>", bullets(.; 4), "  </out-of-scope>" else empty end),
      "  <escape>",
      (sec("escape")[] | "    " + .text),
      gap("escape"; 4),
      "  </escape>",
      "</execution>",
      "",
      "<check>",
      "  Before reporting completion:",
      bullets(sec("check"); 2),
      gap("check"; 2),
      (if ($u.rules | length) > 0
       then "  - Re-read every changed file and confirm each project rule listed under conventions still holds."
       else "  - Re-read every changed file and confirm nothing outside the requested change was altered." end),
      (if $vals.test_cmd != null then "  - Run `\($vals.test_cmd)` and confirm it passes." else empty end),
      "  - Compare the result against every point in the user request; report done / partial / skipped for each requirement.",
      "</check>"
    ] | map(select(. != null)) | join("\n")
  ) as $xml

| {
    ok: ($requires | all(.pass)),
    reason: (if ($requires | all(.pass)) then null else "requires: " + ([$requires[] | select(.pass | not) | .id] | join(", ")) end),
    xml: $xml,
    trace: ($trace + $cover | map(del(.text, .input, .output, .reasoning, .file) + {})),
    emitted: [$E[] | {id, section, text, input, output, reasoning, file} | with_entries(select(.value != null))],
    requires: $requires,
    escalate: $escalate,
    gaps: $gaps,
    slots: $vals,
    stats: {items: ($cell.items | length), emitted: ($E | length), dropped: ([$trace[] | select(.status == "dropped")] | length), covered_from_request: ($cover | length)}
  }
