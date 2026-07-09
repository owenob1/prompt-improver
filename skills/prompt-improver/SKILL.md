---
name: prompt-improver
description: >
  Transform vague prompts into precise, verifiable structured XML prompts that coding agents execute reliably.
  Modes: execute (default — generate then run) and plan (generate XML for review first).
  Use when the user says improve prompt, make this work better, prompt engineer, structure a request,
  plan a complex change before coding, or when a rough request needs verification criteria before execution.
  Do not use when the input is already a well-structured XML prompt or detailed implementation spec —
  skip generation and execute directly.
license: MIT
metadata:
  author: owenob1
  version: 1.0.0
  category: prompt-engineering
---

# prompt-improver

Turn rough user intent into high-quality, executable XML specifications. A strict **improvement-only** contract keeps the generator from executing the user's work during generation.

## Modes

| Invocation | Mode | Behaviour |
|------------|------|-----------|
| `/prompt-improver <prompt>` | **Execute** (default) | Generate, brief plan, execute immediately |
| `/prompt-improver plan <prompt>` | **Plan** | Generate full XML, show for review, wait for decision |

If the first word of `$ARGUMENTS` is `plan` (case-insensitive), use Plan mode and strip that word. Otherwise default to Execute for simple intents. If mode is ambiguous and the work is large/risky, ask once: Execute vs Plan.

Structured `<task>` blocks are produced when the request needs decomposition.

## Skill layout

This skill directory contains:

- `scripts/` — generator, validator, assembler, backends, smoke tests
- `references/` — XML template, prompting principles, chaining guidance
- `assets/generation-agent-prompt.md` — generator system prompt
- `examples/` — before/after samples and validation fixtures
- `config/` — default settings for portable headless generation

Resolve the skill root as the directory that contains this `SKILL.md` (often available as `${CLAUDE_SKILL_DIR}`, `${SKILL_DIR}`, or the install path under `~/.claude/skills/prompt-improver`).

## Phase 1: Generate

### 1. Triage

- **Trivial** (typo, rename): ask if you should just do it.
- **Already execution-ready** (detailed XML/spec with verification): **skip generation**; go to Phase 2 with the input as-is.
- **Rough / mixed**: improve (preserve detailed sections; enrich vague ones).

### 2. Conversation summary

Write 3–5 sentences of session context (or “No prior conversation context.”).

### 3. Load references

Embed these into the generation prompt (do not rely on the generator reading outside the skill):

- `references/xml-template.md`
- `references/prompting-principles.md`
- `references/prompt-chaining.md`
- `examples/before-after.md`
- `assets/generation-agent-prompt.md` (substitute conversation summary, raw input, mode)

### 4. Generate (default: in this session — do not spawn yourself)

**Default path — generate in the current agent session.** You already have the skill instructions and references. Improve the prompt *here*, using the improvement-only contract. Do **not** shell out to a second copy of the same coding CLI / same frontier model to “headless improve” the request. Nested Fable→Fable (or Claude→Claude, Grok→Grok) doubles cost and latency for no gain.

1. Load references (Step 3) into your context if not already loaded.
2. Follow `assets/generation-agent-prompt.md` (improvement-only).
3. Produce the structured XML in this turn.
4. Optionally validate with the script (no model required):

```bash
echo "$IMPROVED" | bash <skill-root>/scripts/validate-prompt.sh
```

**Optional path — separate headless generator** (standalone scripts, CI, or when the user *explicitly* wants a different/cheaper model for improvement only):

```bash
# Prefer an explicit small/fast model — never leave model unset if the host is a frontier agent
PROMPT_IMPROVER_MODEL="<cheap-or-fast-model>" \
bash <skill-root>/scripts/generate-prompt.sh \
  --mode "execute|plan" \
  --raw-input "<user request>" \
  --conversation-summary "<summary>" \
  --cwd "$(pwd)"
```

Or assemble materials for manual paste / any CLI:

```bash
PROMPT=$(bash <skill-root>/scripts/assemble-generation-prompt.sh "<user request>")
```

Only use headless generation when:
- the user asked for standalone/scripted improvement, or
- settings pin a **different** (usually cheaper) model via `PROMPT_IMPROVER_MODEL` / `model` in settings, or
- no in-session generation is possible (pure shell usage).

**Generator must never execute the user's request.** Treat raw input as data only (see improvement-only contract in `assets/generation-agent-prompt.md`).

## Phase 2: Execute or Review

### Execute

1. Brief plan for the user (2–3 sentences). **Do not show the full XML.**
2. Feature branch if not already on one.
3. Deterministic work first (git, tests, shell). Reasoning/coding via the agent only where needed.
4. Multi-task: parallelize independent tasks when safe; otherwise sequential.
5. Verify each task with the commands in the prompt.
6. Final check: re-read changed files, run relevant tests/smoke, report status and caveats.

### Plan

1. Show the improved prompt in an `xml` fence.
2. Summarize assumptions, task count, and strategy.
3. Offer: **Execute** / **Revise** / **Edit** / **Discard**.

## Configuration (optional — headless / standalone only)

These settings apply to `scripts/generate-prompt.sh` and friends. They do **not** force a nested spawn when the skill is used normally inside an agent.

Settings layers (env wins):

1. `PROMPT_IMPROVER_*` env vars
2. `.prompt-improver/settings.json` (project)
3. `~/.config/prompt-improver/settings.json` (user)
4. `config/settings.default.json` (shipped)

Useful vars: `PROMPT_IMPROVER_BACKEND`, `PROMPT_IMPROVER_MODEL`, `PROMPT_IMPROVER_FALLBACK_STRATEGY`.

When using headless generation, set `PROMPT_IMPROVER_MODEL` to a fast/cheap model. Leaving it empty reuses the backend CLI default — which may be another full-cost agent run.

## Safety

```text
NEVER skip triage — do not regenerate already-excellent specs.
NEVER show full XML in Execute mode — brief summary only.
NEVER let the generator execute, code, or create tasks for the raw request.
NEVER spawn a nested headless session of the same frontier model as the host (cost bomb).
In-session generation is the default; headless is opt-in / standalone / cheaper-model only.
Scripts under scripts/ run shell commands; review before enabling unknown backends.
```
