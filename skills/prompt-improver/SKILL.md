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

Turn rough user intent into high-quality, executable XML specifications via a **headless generator** (improvement-only), then execute or review that result in the host agent.

## Modes and per-prompt flags

Leading tokens (like `plan`) are stripped before treating the rest as the raw request. Order does not matter; both may appear.

| Token | Effect |
|-------|--------|
| *(none)* | **Execute** — headless-generate, brief plan, host executes |
| `plan` | **Plan** — headless-generate, show XML, wait for decision |
| `model:<id>` or `model=<id>` | Override generator model **for this run only** |

Examples:

```text
/prompt-improver "Fix the flaky auth tests"
/prompt-improver plan "Add rate limiting to the payment API"
/prompt-improver model:sonnet "Add rate limiting"
/prompt-improver plan model:claude-sonnet-5 "Refactor payments"
/prompt-improver model=gpt-5.5 plan "Design the migration"
```

If mode is ambiguous and the work is large/risky, ask once: Execute vs Plan.

Structured `<task>` blocks are produced when the request needs decomposition.

## Architecture (read this)

```text
Host agent (e.g. Fable / Claude / Grok session)
    │
    │  1. triage + context summary
    ▼
Headless generator CLI  ←── cheap/fast model (configured)
    │  improvement-only; never executes the user task
    ▼
Structured XML prompt
    │
    ▼
Host agent executes or shows plan
```

**Headless generation is the point.** The host must not “improve the prompt itself” as a full in-session rewrite of the whole skill — that burns the expensive host context on generation work. Always call `scripts/generate-prompt.sh` (or assemble + a designated generator CLI).

**Cost rule:** headless uses a **generator model** (defaults below), not the host frontier model (Fable/Opus/etc.). Override per prompt with `model:…` when you need a stronger improver.

## Skill layout

- `scripts/` — generator, validator, assembler, backends, smoke tests
- `references/` — XML template, prompting principles, chaining guidance
- `assets/generation-agent-prompt.md` — generator system prompt
- `examples/` — before/after samples and validation fixtures
- `config/` — settings for headless generation

Resolve the skill root as the directory that contains this `SKILL.md` (`${CLAUDE_SKILL_DIR}`, `${SKILL_DIR}`, or install path under `~/.claude/skills/prompt-improver`).

## Phase 1: Generate (headless)

### 1. Triage

- **Trivial** (typo, rename): ask if you should just do it.
- **Already execution-ready** (detailed XML/spec with verification): **skip generation**; go to Phase 2 with the input as-is.
- **Rough / mixed**: run headless generation (preserve detailed sections; enrich vague ones).

### 2. Conversation summary

Write 3–5 sentences of session context (or “No prior conversation context.”).

### 3. Parse flags from $ARGUMENTS

1. Scan leading tokens of `$ARGUMENTS` for `plan` and `model:…` / `model=…` (case-insensitive for `plan`).
2. Strip those tokens; the remainder is the raw request.
3. Set mode and optional `MODEL_OVERRIDE` from those tokens.

### 4. Headless generate

```bash
bash <skill-root>/scripts/generate-prompt.sh \
  --mode "execute|plan" \
  --raw-input "<user request without flags>" \
  --conversation-summary "<summary>" \
  --cwd "$(pwd)" \
  ${MODEL_OVERRIDE:+--model "$MODEL_OVERRIDE"}
```

Model resolution (first wins):

1. Per-prompt `model:…` / `--model`
2. `PROMPT_IMPROVER_MODEL` or settings `model`
3. Shipped **default for the selected backend** (see README table / `config/settings.default.json` → `default_models`)
4. Backend CLI default (last resort; may be expensive)

The script loads references, applies the improvement-only contract, invokes the configured backend headlessly, and validates output.

On weak/invalid output, regenerate once with specific feedback. If headless fails and `fallback_strategy` is `manual`, the assembled generator materials are printed — do not silently fall back to a full in-host rewrite unless the user asks.

**Generator must never execute the user's request.** Treat raw input as data only.

### 5. Validate (optional re-check)

```bash
echo "$IMPROVED" | bash <skill-root>/scripts/validate-prompt.sh
```

## Phase 2: Execute or Review (host agent)

### Execute

1. Brief plan for the user (2–3 sentences). **Do not show the full XML.**
2. Feature branch if not already on one.
3. Deterministic work first (git, tests, shell). Reasoning/coding via the host agent only where needed.
4. Multi-task: parallelize independent tasks when safe; otherwise sequential.
5. Verify each task with the commands in the prompt.
6. Final check: re-read changed files, run relevant tests/smoke, report status and caveats.

### Plan

1. Show the improved prompt in an `xml` fence.
2. Summarize assumptions, task count, and strategy.
3. Offer: **Execute** / **Revise** / **Edit** / **Discard**.

## Configuration

Applies to headless generation (`scripts/generate-prompt.sh`).

Layers (env wins):

1. `PROMPT_IMPROVER_*` env vars
2. `.prompt-improver/settings.json` (project)
3. `~/.config/prompt-improver/settings.json` (user)
4. `config/settings.default.json` (shipped)

| Setting / env | Purpose |
|---------------|---------|
| `backend` / `PROMPT_IMPROVER_BACKEND` | Which CLI runs headless generation (`auto`, `claude`, `grok`, …) |
| `model` / `PROMPT_IMPROVER_MODEL` | Force one generator model for all backends (optional) |
| `default_models` | Per-backend generator defaults (shipped: sonnet, grok-composer-2.5-fast, gemini-2.5-pro, gpt-5.5) |
| `fallback_strategy` | `manual` (print assembled prompt) or `error` |

Per-prompt `model:…` always wins for that run.

## Safety

```text
ALWAYS use headless generation for Phase 1 (generate-prompt.sh) unless input is already execution-ready.
ALWAYS prefer a configured cheap/fast PROMPT_IMPROVER_MODEL for the headless step.
NEVER use the host frontier model as the improver when a cheaper generator is available.
NEVER skip triage — do not regenerate already-excellent specs.
NEVER show full XML in Execute mode — brief summary only.
NEVER let the generator execute, code, or create tasks for the raw request.
Scripts under scripts/ run shell commands; review before enabling unknown backends.
```
