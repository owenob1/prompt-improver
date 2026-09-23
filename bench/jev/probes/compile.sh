#!/usr/bin/env bash
# Data-driven compile: every section comes from the cell file (kind<TAB>text), slots, and selected rules.
# Cell kinds: desc desired current approach req.<group> example(i|o|r) verify companion(file|text)
#             constraint out escape check task2.desc
LIB="$1"; SLOTS="$2"; RULES="$3"; REQ="$4"
shopt -u patsub_replacement 2>/dev/null || true
fill() { local t="$1" k v; while IFS=$'\t' read -r k v; do t="${t//\{$k\}/$v}"; done < "$SLOTS"; printf '%s' "$t"; }
items() { awk -F'\t' -v k="$1" '$1==k {print $2}' "$LIB"; }
one() { items "$1" | head -n 1; }
S() { awk -F'\t' -v k="$1" '$1==k {print $2}' "$SLOTS"; }
groups=$(awk -F'\t' '$1 ~ /^req\./ {sub(/^req\./,"",$1); if (!seen[$1]++) print $1}' "$LIB")
{
echo "<context>"
echo "  <project>$(S project)</project>"
echo "  <scope>"
for f in $(S scope_files); do echo "    - $f"; done
echo "  </scope>"
echo "  <current-behavior>$(fill "$(one current)")</current-behavior>"
echo "  <desired-behavior>$(fill "$(one desired)")</desired-behavior>"
echo "  <conventions>"
while IFS= read -r r; do [ -n "$r" ] && echo "    - $r"; done < "$RULES"
echo "  </conventions>"
echo "  <user-request>"
echo "    $REQ"
echo "  </user-request>"
echo "</context>"
echo
echo "<task id=\"1\" name=\"$(S task_name)\">"
echo "  <description>$(fill "$(one desc)")</description>"
echo
echo "  <approach>"
echo "    Before implementing, reason through:"
items approach | while IFS= read -r l; do echo "    - $(fill "$l")"; done
echo "  </approach>"
echo
echo "  <requirements>"
for g in $groups; do echo "    <group name=\"$g\">"; items "req.$g" | while IFS= read -r l; do echo "      - $(fill "$l")"; done; echo "    </group>"; done
echo "  </requirements>"
echo
echo "  <examples>"
items example | while IFS='|' read -r i o r; do echo "    <example>"; echo "      <input>$(fill "$i")</input>"; echo "      <output>$(fill "$o")</output>"; echo "      <reasoning>$(fill "$r")</reasoning>"; echo "    </example>"; done
echo "  </examples>"
echo
echo "  <verification>"
items verify | while IFS= read -r l; do echo "    - $(fill "$l")"; done
echo "  </verification>"
echo "</task>"
echo
echo "<task id=\"2\" name=\"regression-coverage-and-changelog\" depends-on=\"1\">"
echo "  <description>$(fill "$(one task2.desc)")</description>"
echo "  <requirements>"
items companion | while IFS='|' read -r f t; do echo "    - In \`$(fill "$f")\`: $(fill "$t")"; done
[ -n "$(S changelog)" ] && echo "    - Add a \`$(S changelog)\` entry describing the change."
echo "  </requirements>"
echo "  <verification>"
echo "    - \`$(S test_cmd)\` passes."
echo "  </verification>"
echo "</task>"
echo
echo "<execution>"
echo "  <strategy>Sequential: task 2 depends on task 1.</strategy>"
echo "  <constraints>"
items constraint | while IFS= read -r l; do echo "    - $(fill "$l")"; done
echo "  </constraints>"
echo "  <out-of-scope>"
items out | while IFS= read -r l; do echo "    - $(fill "$l")"; done
echo "  </out-of-scope>"
echo "  <escape>"
items escape | while IFS= read -r l; do echo "    $(fill "$l")"; done
echo "  </escape>"
echo "</execution>"
echo
echo "<check>"
echo "  Before reporting completion:"
items check | while IFS= read -r l; do echo "  - $(fill "$l")"; done
echo "  - Re-read every changed file and confirm each project rule listed under conventions still holds."
echo "  - Run \`$(S test_cmd)\`."
echo "  - Compare the result against every point in the user request; report done / partial / skipped for each requirement."
echo "</check>"
}
