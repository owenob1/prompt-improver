---
name: prompt-improver
description: Transforms vague prompts into structured XML and executes them. Modes: execute (default), plan (review before running). Task mode is deprecated. Portable across major coding CLIs (headless + non-headless). Use when the user says improve prompt, make this work better, prompt engineer, or structure a prompt.
argument-hint: [plan] [prompt-text or description of what to improve]
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent, AskUserQuestion
metadata:
  author: Owen Innes
  version: 6.1.0
  category: prompt-engineering
  tags: [prompting, xml, agentic-coding, workflow, portable]
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

**Task mode is deprecated.** The original integration with an external task system is no longer active. Structured `<task>` output is still produced by the underlying XML template when useful and can be requested via the prompt content itself.

When the first word of $ARGUMENTS is `plan` (case-insensitive), activate Plan mode. Strip the mode word from the arguments before passing the rest as raw input.

**Mode ambiguity:** If $ARGUMENTS does not start with a mode word AND the input is complex enough that multiple modes could apply, use AskUserQuestion to disambiguate:

- **Single-select** with `preview` enabled
- **question**: describe what you received and why you're unsure
- **header**: "Mode"
- **Options**: Execute or Plan (tailor descriptions to the ACTUAL input). Task-related structured output can still be produced by the generator when the prompt benefits from it.
- **Recommend the best fit** by putting it first with "(Recommended)" in the label — base the recommendation on input complexity (simple → Execute, risky/large/review-needed → Plan).

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
- **Already execution-ready** (well-structured XML, detailed spec with code examples/schemas/verification criteria, comprehensive implementation guide, long structured prompt with clear requirements): **Skip the generation agent entirely.** The input is already good — go straight to Phase 2 using the content as-is.
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
- `{MODE}` — execute or plan (task mode is deprecated)
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

### Task mode (deprecated)

**Task mode is deprecated.** The previous integration with an external persistent task system (e.g. `task_create`) is no longer active in this release.

The generator can still produce high-quality structured `<task>` blocks inside the XML output when the input benefits from decomposition (this is part of the core XML template and prompting principles). Users who want task-style output can request it explicitly in the prompt text or use the Plan mode to review a generated prompt that includes a task tree.

If a portable, CLI-agnostic "export structured tasks" flag or output format proves valuable across many coding agents, it may be re-introduced in a future version behind a clean, optional flag (e.g. `--structured-tasks`). Any such addition will be designed to work via headless invocation on all supported CLIs.

## Edge cases

### Weak prompt returned
If the result is missing verification, too vague, or ignores the principles — re-spawn the agent with specific feedback.

### Prompt needs chaining
If the agent returns "Phase 1 of N":
- **Execute mode**: Execute Phase 1. Ask before proceeding to Phase 2.
- **Plan mode**: Show Phase 1. Note subsequent phases. Execute only after approval.

## Reference files

Read by the orchestrator (embedded into the generation prompt so the generator does not need to read external files):
- XML template: [references/xml-template.md](references/xml-template.md)
- Prompting principles: [references/prompting-principles.md](references/prompting-principles.md)
- Prompt chaining: [references/prompt-chaining.md](references/prompt-chaining.md)
- Before/after examples: [examples/before-after.md](examples/before-after.md)

## Portability & Configuration

This skill is designed to work with many coding agents (Grok Build, Claude Code, Gemini CLI, Cline, OpenCode, Kiro, Kimi, Codex, etc.).

**Default behavior**: Auto-detects the host CLI and uses its headless mode for generation (e.g. `grok -p`, `claude -p`). Falls back gracefully.

**Global guard**: A strict "IMPROVEMENT-ONLY" contract is embedded so raw requests are never executed by the generator — no user preambles required.

**Configuration**: See `config/settings.default.json` and README. Supports:
- `backend`, `model`, `max_tokens`
- `enable_research`, `enable_thinking`
- `fallback_strategy`
- Custom commands and preferred backends

Full details and quickstarts in README.md.

New CLIs: Add adapter in `scripts/backends/`.

---

<critical_safety_rules>
NEVER skip the triage step — classify the input before spawning any agent. Spawning a generation agent on already-excellent input wastes tokens and may overwrite good structure.
NEVER show the XML to the user in Execute mode — brief summary only. The XML is the implementation detail, not the deliverable.
When producing structured task output (even in deprecated Task mode paths), all phases must have the same depth of acceptance criteria and verification commands.
</critical_safety_rules>

<decision_boundaries>
CORRECT: Input is a well-structured XML prompt with clear requirements, code examples, and verification criteria → classify as "already execution-ready," skip generation agent, go straight to Phase 2.
INCORRECT: Input is a well-structured XML prompt → always spawn the generation agent anyway "just to improve it."

When generating structured `<task>` output: 5 `<task>` blocks in the generated XML should be treated as 5 units of work with matching verification depth.
</decision_boundaries>

<reasoning>
Edge case — mode word collision: If the user says `/prompt-improver plan a CI pipeline`, the first word is "plan" which activates Plan mode. But the user may have meant "plan" as a noun (i.e., plan for a CI pipeline), not as a mode selector. When the resulting mode would change execution significantly (Plan mode shows XML, Execute mode runs immediately), use AskUserQuestion to confirm: "I detected 'plan' as the mode — did you mean to review the prompt before running, or to improve a CI pipeline plan?" Strip the ambiguity before proceeding.
</reasoning>
