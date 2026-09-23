You are authoring one cell of a prompt-compilation library. At request time a small decision model (Jev) selects this cell, fills its slots from verbatim candidates taken from the request and the repository, and answers each item's guard questions. The compiler then emits only the items whose guards pass, as an XML specification that a coding agent carries out. Nothing is generated at request time: every spec compiled from this cell is exactly as good as what you write now.

<schema>
@@SCHEMA@@
</schema>

<example-cell>
@@EXAMPLE@@
</example-cell>

<what-makes-a-cell-good>
These lessons were measured on real requests, in blind comparisons against specifications written by a frontier model:
1. Mis-fit loses. A spec that says something wrong for the request in front of it loses to a specific spec. Examples: the wrong result vocabulary, a verification command that cannot run for this tool, or wording about positional arguments for a tool that has none. So every item that depends on a judgement about the request or the target gets a guard. Alternatives are separate items with complementary guards (min on one, max on the other).
2. Guards are narrow yes/no facts about the request or the target file, phrased so that a high value means the item applies.
   - Jev answers them with the state {request, target: {path, summary, usage}}, where usage is the target's header comment, its usage/help text and the options it parses.
   - Refer to `target.usage` in a guard when the fact is about the file.
   - Jev handles negation poorly: never phrase a guard as "Does the request not …" or "Is it false that …".
3. Guard thresholds: use min 0.6 for "applies when clearly yes" and max 0.35 to 0.4 for "applies when clearly no"; the engine adds a 0.05 margin.
   - A value in between drops both alternatives. If that empties a required section, the section becomes a gap that an LLM writes, which is the safe outcome.
   - Fact guards ("target_has" / "target_lacks") check the target's text deterministically. Use them for claims such as "it has no `{flag}` option today".
4. Specific beats generic.
   - Verification items are runnable commands with the expected result; use {runner}, {target_path}, {syntax_check} and {test_cmd}.
   - Give concrete output shapes and named files.
   - No vague adjectives (clean, robust, proper, appropriate, efficient, seamless, nice, good).
5. The best specs read the code before designing: approach items tell the agent what to find in the target before editing, and which design decision to settle, with the criteria.
6. Code-specific reasoning the library cannot know belongs to an "escalate" guard. Examples are which branches, loops or call sites in this particular file are affected. The escalate guard hands the approach section to an LLM that reads the source.
7. Every example has input, output and reasoning. Escape items say exactly when to stop and ask for this kind of change. The check section re-reads the changed files.
8. Items must read well for any request this cell fits, in any language or repository (shell, Python, JavaScript, Go…); request specifics go in slots. Never mention a particular project, file or tool by name, apart from the slots.
9. Items that use optional slots ({test_file}, {changelog}, {callers}, {lint_cmd}, {test_cmd}, …) are dropped when the slot does not resolve. Nothing essential should live only in such items.
10. Write for an agent that is capable and literal: state what to do and how to confirm it, not motivation.
</what-makes-a-cell-good>

<node>
id: @@ID@@
requests this cell is for: @@MATCH@@
boundaries: @@BOUNDARIES@@
</node>

Write the cell for this node.
- Output JSON only: no commentary and no code fences. It must parse.
- "id" is the node id and "schema" is 1.
- "provenance" is {"authored_by": "opus via bench/jev/authoring/author.sh", "reviewed_by": null, "created": "@@DATE@@"}.
- "match" is the node's sentence; you may tighten the wording, but keep it one sentence.
- 2 or 3 "fit" questions that together confirm the request is this kind of work. They are asked with the request only, not the target, so each must be answerable from the request's wording ("Does the code already exist?" is not).
- When the file to reason about is not the file to edit (for example tests for a function), set "target_from" to the slot that names it.
- "requires" and "escalate" entries where they apply, and a "task_name" (kebab-case, may use slots).
- "slots": only what the items need.
  - Entity slots accept the entity kinds that can carry the value: file, path, code, identifier, env, flag, quoted, version, quantity, number, url, word.
  - Role slots use one of: target, new_element, desired, symptom, constraint, metric.
- 30 to 45 items. Cover description, current, desired, approach (3 or more), requirements in 2 to 4 named groups, 2 to 4 examples, verification (3 or more, runnable), companion (tests, changelog, docs where relevant), constraints, out_of_scope, escape (one generic plus specific ones) and check.
- "required": {"description": 1, "desired": 1, "approach": 2, "verification": 3, "check": 1, "escape": 1}, unless this node needs different minimums.
- When several items ask the same question, reuse the guard id with identical "q" text.
