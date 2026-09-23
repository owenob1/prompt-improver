# Pattern library schema (Jev v2 compiler)

Each `*.json` file in this directory is one **cell**: a reusable, reviewed recipe for one kind of request, such as "add a diagnostic CLI flag". At request time Jev selects a cell, fills its slots, and evaluates every item's guards. The compiler then emits only the items whose guards pass. Nothing in a compiled spec is generated at request time. Every line comes from an item here, filled from the request, the repository, or a Jev choice among verbatim candidates.

```jsonc
{
  "id": "cli-flag.diagnostic",          // unique, dot-separated taxonomy path
  "schema": 1,
  "provenance": { "authored_by": "…", "reviewed_by": null, "created": "YYYY-MM-DD" },
  "match": "One sentence describing the requests this cell is for",   // a Jev choice option
  "fit": [ { "id": "adds_flag", "q": "…?", "min": 0.6 } ],           // all must pass for the cell to be used
  "slots": {
    "tool":     { "kind": "entity", "accept": ["file","path","identifier"], "q": "Which candidate …?" },
    "flag":     { "kind": "entity", "accept": ["flag"], "q": "Which candidate …?" },
    "desired":  { "kind": "role", "role": "desired" },
    "reported": { "kind": "word", "q": "Which single word …?" }
  },
  "items": [
    { "id": "req-stdout", "section": "requirements.behaviour",
      "text": "Without `{flag}`, stdout is byte-for-byte identical to today's output.",
      "guards": [ { "id": "stdout_product", "q": "…?", "min": 0.5 } ] }
  ],
  "required": ["description", "verification", "check", "escape"]
}
```

## Fields

- **`fit`**: cell-level preconditions, asked about the request. Every one must pass, or the cell is not used.
- **`slots`**: values interpolated as `{name}` into item text.
  - `entity`: a Jev choice over request entities (paths, flags, identifiers, env vars…) whose kind is in `accept`, plus `none`.
  - `role`: taken from the L1 role extraction (`target`, `new_element`, `desired`, `symptom`, `constraint`, `metric`).
  - `word`: a Jev choice over single words of the request.
  - **Built-in slots** come from the engine, not the cell:
    - the target file (the one file the request changes, resolved from the request or by Jev relevance): `{target_path}` (repo-relative), `{target_name}` (basename), `{target_stem}` (basename without extension), `{target_summary}` (first sentence of its own header), `{runner}` (for example `bash`, `python3`, `node`), `{syntax_check}` (for example `bash -n <path>`), `{callers}` (files that invoke it, excluding tests). `{tool_path}`, `{tool_name}` (= stem) and `{tool_summary}` are aliases kept for command-line tools.
    - the project: `{test_file}` (the test file that already covers the target, else Jev's pick), `{test_cmd}`, `{typecheck_cmd}`, `{lint_cmd}`, `{build_cmd}` (commands whose role Jev classified), `{changelog}`, `{project}`.
    - A slot that does not resolve drops every item that uses it, so write items that still read well when optional slots are missing.
- **`items`**: one line of the spec each.
  - `section` is one of: `description`, `current`, `desired`, `approach`, `requirements.<group>`, `example` (with `input` / `output` / `reasoning` instead of `text`), `verification`, `companion` (with `file`), `constraint`, `out_of_scope`, `escape`, `check`.
  - An item is emitted only if **all** its slots resolve and **all** its guards pass.
- **Guards**: `{ "id", "q", "min" }` passes when p ≥ `min` + margin. `{ "id", "q", "max" }` passes when p ≤ `max` − margin. The margin (default 0.05, `fast_path.guard_margin`) sits above Jev's measured run-to-run jitter. An answer between the two bounds drops both alternatives, so a required section left empty becomes a gap instead of a guess.
  - **Fact guards** are deterministic checks on the target file's text: `{ "id", "fact": "target_has" | "target_lacks", "text": "{flag}" }`.
- **`requires`** (cell level): guards that must all pass, or the cell is not used at all (for example "the target is a library, not a command").
- **`escalate`** (cell level): `{ "id", "q", "min" | "max", "gap": "<section>", "prompt"? }`. When it passes, that section is handed to tier B: an LLM that sees the target's source adds what the library cannot know, such as the concrete functions and branches to change.
- **`key_slots`**: the cell slots the cell cannot do without (for example `["flag"]`). If one does not resolve, the cell is not used. Every other slot, including every role slot, is optional. Each required section needs at least one unguarded item that uses only key slots, `{target_*}` and `{project}`, so a fitting request never leaves the description or the desired behaviour empty.
- **`task_name`**: kebab-case name for the task, may use slots (`add-{flag}-flag`).
- **`target_from`**: the slot that locates the target when the file to reason about is not the file to edit. For example, tests.add uses its `subject` slot: the target becomes the file that defines that function (from `git grep` references), and `{test_file}` is where the tests go.
- **Fit questions** are asked with the request alone, so they must be answerable from its wording. "Does the code already exist?" is not answerable; put such facts in guards or fact guards.
  - Guards are asked about the **request**, with the target file's usage text and header in the state. They are never asked about the draft.
  - Phrase each guard as the narrowest fact that decides the item, with a high value meaning "the item applies".
  - The same `id` in several items means the same question, asked once.
- **`required`**: sections that must be non-empty after guards, as a list or as `{section: minimum items}`. A required section below its minimum is a **gap**; gaps go to tier B (an LLM writes only that section).

## Authoring rules

- **Generic, not tailored.** Write items for the whole cell and use slots for request specifics. An item that only makes sense for one request belongs in no cell.
- **Every judgement-dependent item gets a guard.** Examples: result vocabularies, argument positions, verification invocations, caller lists.
- **Alternatives are separate items with complementary guards.** For instance, "hit / miss / skipped" results for lookups vs "success / limit / error" for attempts.
- **Follow `references/prompting-principles.md`.** Use runnable checks over adjectives, give examples a `<reasoning>`, and keep escapes specific to the cell.
- **Review is required.** Set `provenance.reviewed_by` after a human has read the cell. Unreviewed cells are only used when `fast_path.allow_unreviewed` is true, which is the default on the investigation branch only.
