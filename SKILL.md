---
name: prompt-improver
description: Transforms vague prompts into structured XML and executes them. Modes: execute (default), plan (review before running), task (create persistent tasks without executing). Use when the user says improve prompt, make this work better, prompt engineer, or structure a prompt.
argument-hint: [plan|task] [prompt-text or description of what to improve]
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent, AskUserQuestion
metadata:
  author: Owen Innes
  version: 6.0.0
  category: prompt-engineering
  tags: [prompting, xml, claude-code, workflow]
intelligence_tier: 3
cache_class: cold
when_not_to_use: When the input is already a well-structured XML prompt or detailed implementation spec — skip generation and execute directly.
---

# Improving Prompts

Transform rough user input into structured XML prompts and execute them directly.

## Modes

| Invocation | Mode | Behaviour |
|------------|------|-----------|
| `/prompt-improver <prompt>` | **Execute** (default) | Generate, brief summary, execute immediately |
| `/prompt-improver plan <prompt>` | **Plan** | Generate, show full XML, wait for user decision |
| `/prompt-improver task <prompt>` | **Task** | Generate, create persistent tasks via task_create, do not execute |

When the first word of $ARGUMENTS is `plan` or `task` (case-insensitive), activate that mode. Strip the mode word from the arguments before passing the rest as raw input.

**Mode ambiguity:** If $ARGUMENTS does not start with a mode word AND the input is complex enough that multiple modes could apply, use AskUserQuestion to disambiguate:

- **Single-select** with `preview` enabled
- **question**: describe what you received and why you're unsure (e.g. "This is a multi-step spec — should I execute it now or create a task tree for later?")
- **header**: "Mode"
- **Options**: the 3 modes (Execute, Plan, Task) — but tailor the descriptions to the ACTUAL input. E.g. if the input has 8 tasks, the Task option description should say "Creates 8 subtasks with dependencies" not generic text. The preview for each should show what the output would look like for THIS specific input.
- **Recommend the best fit** by putting it first with "(Recommended)" in the label — base the recommendation on input complexity (simple → Execute, risky/large → Plan, multi-session/team → Task).

If the input is clearly simple (single action, obvious intent), default to Execute without asking.

## Execution model

Two phases:
1. **Generate** — Delegate prompt construction to a subagent (keeps main context clean)
2. **Execute or Review** — Follow the prompt directly, or present it for review

## Phase 1: Generate

### Step 1: Triage the input

Before doing anything, resolve and classify the input:

**Resolve**: If the input is a file path, read it. If it's a URL, fetch it. The resolved content is what you classify.

**Classify** the resolved content:
- **Trivial** (typo, rename, single-line fix): Ask: "This looks straightforward — should I just do it directly?"
- **Already execution-ready** (well-structured XML, detailed spec with code examples/schemas/verification criteria, comprehensive implementation guide, long structured prompt with clear requirements): **Skip the generation agent entirely.** The input is already good — go straight to Phase 2 using the content as-is. In task mode, go straight to task creation/decomposition.
- **Rough input** (vague description, bullet points, incomplete thoughts, missing context): This is where prompt-improver adds the most value. Proceed to Step 2 and the generation agent.
- **Mixed** (some sections detailed, others vague): Proceed to Step 2, but tell the generation agent to preserve detailed sections and enrich only the vague ones.

### Step 2: Summarise conversation context

Write 3-5 sentences of context for the generation agent:
- What the user has been building/fixing this session
- Key decisions or constraints discussed
- Current codebase state
- If first message: note "No prior conversation context."

### Step 3: Load reference materials

Before spawning the agent, read these 4 files and store their contents (you will embed them in the agent prompt so the agent does not need to read files outside the project):
- ${CLAUDE_SKILL_DIR}/references/xml-template.md
- ${CLAUDE_SKILL_DIR}/references/prompting-principles.md
- ${CLAUDE_SKILL_DIR}/references/prompt-chaining.md
- ${CLAUDE_SKILL_DIR}/examples/before-after.md

### Step 4: Spawn the generation agent

Read the agent prompt from `${CLAUDE_SKILL_DIR}/assets/generation-agent-prompt.md`.

Spawn a general-purpose Agent with that prompt, substituting:
- `{CONVERSATION_SUMMARY}` — the summary from Step 2
- `{RAW_INPUT}` — the user's original prompt text
- `{MODE}` — execute, plan, or task
- `{REFERENCE_MATERIALS}` — content from the reference files read in Step 3

---

## Phase 2: Execute or Review

### Execute mode (default)

1. **Brief plan**: Tell the user in 2-3 sentences what you're about to do. Do not show the XML.

2. **Branch**: Create a feature branch if not already on one.

3. **Deterministic first**: Run all deterministic operations directly via Bash — git, tests, typecheck, grep, sed. AI handles code generation, reasoning, and debugging only.

4. **Execute**: For multi-task work with 3+ independent tasks, use TeamCreate for parallel execution. For simpler work, execute directly. Match the execution approach to the task scope.

5. **Verify per task**: Run verification commands via Bash. Parse output deterministically (exit codes, grep matches). Commit with a conventional message if verification passes.

6. **Check your work** (mandatory final step):
   - Re-read every changed file for correctness
   - Run typecheck and test suite
   - Verify no regressions
   - Push the branch
   - Report: what was done, what was verified, any caveats

### Plan mode (`/prompt-improver plan ...`)

1. **Show the prompt** in an xml code fence.

2. **Summarise** (3-5 sentences): context pulled, assumptions made, ambiguities resolved, task count, recommended execution strategy.

3. **Offer options**:
   > **Ready to proceed?**
   > - **Execute** — run this prompt as-is
   > - **Revise** — tell me what to change
   > - **Edit** — paste back modified prompt
   > - **Discard** — cancel

4. **Handle response**:
   - **Execute**: Brief plan, then follow the prompt.
   - **Revise**: Re-spawn agent with original input + revision notes, present again.
   - **Edit**: Acknowledge changes, ask again.
   - **Discard**: Acknowledge and stop.

### Task mode (`/prompt-improver task ...`)

Create persistent tasks from the generated prompt instead of executing. This mode connects prompt-improver to the task management system.

1. **Run Phase 1 (Generate)** identically to execute/plan modes — same agent, same references, same validation.

2. **Create parent task**: Call the MCP `task_create` tool with:
   - `content`: the overall description from the user's input
   - `priority`: "high"
   - `tags`: ["prompt-improved"]
   - `metadata`: `{"generated_prompt": "<the full XML prompt>"}`

3. **Create subtasks**: When creating subtasks, create ALL phases upfront with equal detail. Verification, testing, and documentation tasks must have the same depth of acceptance criteria and verification commands as implementation tasks. Do not create partial task trees.

   For each `<task>` block in the generated XML prompt, call `task_create` with:
   - `parent_id`: the parent task's ID (returned from step 2)
   - `priority`: derive from position (first tasks get "high", later ones get "medium")
   - `tags`: ["prompt-improved", task-name-from-xml]
   - `dependencies`: map `depends-on` attributes to the corresponding subtask IDs (create tasks in order, track ID mapping)
   - `content`: structured as a **self-contained PRD** so an autonomous agent can execute with zero clarification:

     ```markdown
     ## [Task Title]

     ## Description
     [What this task does and why it matters in the context of the parent goal]

     ## Acceptance Criteria
     - [ ] [Verb-led, measurable, pass/fail criterion]
     - [ ] [Each criterion independently verifiable]

     ## File References
     - **Read:** [exact paths the agent needs to understand before starting]
     - **Modify:** [exact paths the agent will change]
     - **Do not touch:** [paths that must remain unchanged]

     ## Reference Patterns
     - Follow `[path]` for [aspect — e.g. naming conventions, error handling, test structure]

     ## Constraints
     - [Hard limits — e.g. no new dependencies, must be backwards compatible]

     ## Out of Scope
     - [Explicitly excluded items to prevent scope creep]

     ## Verification
     - `[exact shell command]` — [what it proves]
     - `[exact shell command]` — [what it proves]

     ## Risk Level
     [low / medium / high — with one-line justification]
     ```

     Every section is required. An executing agent must be able to complete this task from the content alone without re-reading the source spec.

   - `metadata`: structured data for programmatic access:
     ```json
     {
       "file_references": { "read": [...], "modify": [...], "do_not_touch": [...] },
       "acceptance_criteria": ["verb-led criterion 1", "..."],
       "out_of_scope": ["excluded item 1", "..."],
       "verification_commands": ["npm test -- --grep auth", "..."],
       "reference_patterns": [{ "path": "src/example.ts", "aspect": "error handling" }],
       "risk_level": "low|medium|high"
     }
     ```

4. **Parallel execution note**: When the task tree contains 3+ independent subtasks (no mutual dependencies), include a recommendation to use TeamCreate for parallel execution when the user starts the work. Add `"recommended_strategy": "parallel"` or `"sequential"` to the parent task's metadata.

5. **Completeness validation**: After creating all tasks, verify:
   - Count the number of `<task>` blocks in the generated prompt vs the number of subtasks created. If there's a mismatch, warn the user about missing tasks.
   - Verify each subtask has acceptance criteria, file references, and verification commands. Warn about any that are missing sections.
   - Check that verification/testing tasks are not significantly thinner than implementation tasks.

6. **Present the task tree** to the user:
   ```
   Created task tree:
   - [task-parent-id] Overall description (high, prompt-improved)
     - [task-sub1] First subtask (high, depends on: none)
     - [task-sub2] Second subtask (medium, depends on: sub1)
     - [task-sub3] Third subtask (medium, depends on: sub1)
   ```

7. **Execute immediately**. After presenting the task tree, invoke the `/claudetools:task-manager start` skill to begin executing the tasks automatically — do not wait for the user to run it manually.

## Edge cases

### Weak prompt returned
If the result is missing verification, too vague, or ignores the principles — re-spawn the agent with specific feedback.

### Prompt needs chaining
If the agent returns "Phase 1 of N":
- **Execute mode**: Execute Phase 1. Ask before proceeding to Phase 2.
- **Plan mode**: Show Phase 1. Note subsequent phases. Execute only after approval.

## Reference files

Read by the main conversation in Step 3 and embedded in the agent prompt (the agent does not read these files directly):
- XML template: [references/xml-template.md](references/xml-template.md)
- Prompting principles: [references/prompting-principles.md](references/prompting-principles.md)
- Prompt chaining: [references/prompt-chaining.md](references/prompt-chaining.md)
- Before/after examples: [examples/before-after.md](examples/before-after.md)

---

<critical_safety_rules>
NEVER skip the triage step — classify the input before spawning any agent. Spawning a generation agent on already-excellent input wastes tokens and may overwrite good structure.
NEVER show the XML to the user in Execute mode — brief summary only. The XML is the implementation detail, not the deliverable.
NEVER create a partial task tree in Task mode — ALL phases must have the same depth of acceptance criteria and verification commands. Thin verification tasks fail downstream agents.
</critical_safety_rules>

<decision_boundaries>
CORRECT: Input is a well-structured XML prompt with clear requirements, code examples, and verification criteria → classify as "already execution-ready," skip generation agent, go straight to Phase 2.
INCORRECT: Input is a well-structured XML prompt → always spawn the generation agent anyway "just to improve it."

CORRECT: Task mode, 5 `<task>` blocks in the generated XML → create exactly 5 subtasks, verify count matches, warn if any is missing sections.
INCORRECT: Task mode, 5 `<task>` blocks → create 3 subtasks because the other 2 seemed redundant.
</decision_boundaries>

<reasoning>
Edge case — mode word collision: If the user says `/prompt-improver plan a CI pipeline`, the first word is "plan" which activates Plan mode. But the user may have meant "plan" as a noun (i.e., plan for a CI pipeline), not as a mode selector. When the resulting mode would change execution significantly (Plan mode shows XML, Execute mode runs immediately), use AskUserQuestion to confirm: "I detected 'plan' as the mode — did you mean to review the prompt before running, or to improve a CI pipeline plan?" Strip the ambiguity before proceeding.
</reasoning>
