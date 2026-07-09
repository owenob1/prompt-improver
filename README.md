<div align="center">

# /prompt-improver

**Turn vague prompts into precise, verifiable specs your coding agent can execute.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![CI](https://github.com/owenob1/prompt-improver/actions/workflows/ci.yml/badge.svg)](https://github.com/owenob1/prompt-improver/actions/workflows/ci.yml)
[![Agent Skills](https://img.shields.io/badge/Agent%20Skills-compatible-blue)](https://agentskills.io/)

[Install](#install) · [Usage](#usage) · [Default generator models](#default-generator-models) · [How it works](#how-it-works) · [Structure](#structure)

</div>

---

## What is it?

Coding agents often jump into implementation from fuzzy requests — missing edge cases, verification, and clear scope. **/prompt-improver** rewrites the request into structured XML with tasks, checks, and escape clauses *before* work starts.

The generator is **improvement-only**: it will not execute your request while improving it.

| You say | You get |
|---------|---------|
| “Add rate limiting” | Spec with scope, verification commands, and failure modes |
| “Fix auth” | Repro-first plan, concrete checks, explicit out-of-scope |
| “Refactor payments” | Phased tasks with acceptance criteria |

Works with Claude Code, Grok Build, Codex, Cursor, Gemini CLI, and other [Agent Skills](https://agentskills.io/)-compatible agents.

## Install

### skills.sh (recommended)

```bash
# Global — available in every project
npx skills add -g owenob1/prompt-improver

# Project-local — commit with the repo
npx skills add owenob1/prompt-improver
```

```bash
# Preview without installing
npx skills add owenob1/prompt-improver --list
```

### Claude Code marketplace

```text
/plugin marketplace add owenob1/prompt-improver
/plugin install prompt-improver@prompt-improver
```

### Manual

```bash
git clone https://github.com/owenob1/prompt-improver.git
cp -R prompt-improver/skills/prompt-improver ~/.claude/skills/prompt-improver
```

Many agents also load from `~/.agents/skills/` or project `.claude/skills/`.

## Usage

```text
/prompt-improver "Fix the flaky auth tests"
/prompt-improver plan "Add rate limiting to the payment API"
/prompt-improver model:sonnet "Add rate limiting"
/prompt-improver plan model:gpt-5.5 "Refactor payments"
```

| Flag | Meaning |
|------|---------|
| *(default)* | **Execute** — improve headlessly, then run the work |
| `plan` | Improve headlessly, **show** the XML, wait for your decision |
| `model:<id>` or `model=<id>` | Override the **generator** model for this run only |

Flags are leading tokens (same style as `plan`); they can be combined in any order.

### Without installing (one-shot)

```bash
bash skills/prompt-improver/scripts/assemble-generation-prompt.sh "your request"
bash skills/prompt-improver/scripts/standalone-improve.sh "your request" plan
bash skills/prompt-improver/scripts/standalone-improve.sh "your request" plan sonnet
```

## Default generator models

Headless improvement uses a **capable mid-tier generator** — strong enough for high-quality specs, cheaper than host frontier models (Fable / Opus / max Grok Build session). Your interactive host only **executes** the improved plan.

| Backend CLI | Default generator model | Why |
|-------------|-------------------------|-----|
| **claude** | `sonnet` | Claude Code alias → **Sonnet 5** (`claude-sonnet-5`) — daily-driver quality for structured prompts |
| **grok** | `grok-composer-2.5-fast` | High-quality agentic coding model; strong speed/quality balance in Grok Build |
| **gemini** | `gemini-2.5-pro` | Pro-class reasoning for specs (not Flash-lite) |
| **codex** | `gpt-5.5` | Current recommended Codex CLI default (GPT-5 family) |
| **opencode / cline / kimi / kiro** | *(CLI default)* | No pin yet — set `model:` or settings |

Still **not** the host frontier tier (e.g. `fable` / Opus). Override upward when you want:

```text
/prompt-improver model:claude-sonnet-5 "…"
/prompt-improver model:gpt-5.5 plan "…"
```

**Resolution order** (first wins):

1. Per-prompt `model:…` / `generate-prompt.sh --model …`
2. `PROMPT_IMPROVER_MODEL` or settings `"model"`
3. `default_models[backend]` in settings (table above)
4. Backend CLI default

```bash
export PROMPT_IMPROVER_BACKEND=claude
export PROMPT_IMPROVER_MODEL=sonnet   # optional global pin

bash skills/prompt-improver/scripts/generate-prompt.sh \
  --mode plan \
  --raw-input "Add rate limiting to the payment API" \
  --model sonnet
```

Optional user settings (later roadmap: richer skill-side settings UX):

```bash
mkdir -p ~/.config/prompt-improver
cp skills/prompt-improver/config/settings.example.json \
  ~/.config/prompt-improver/settings.json
# edit "model" or "default_models"
```

## How it works

**Headless generation is the core design.**

```text
Host agent  →  headless generator (default: cheap/fast model)  →  XML  →  host executes
```

1. **Triage** — skip generation if the input is already a solid spec  
2. **Generate (headless)** — `scripts/generate-prompt.sh` + improvement-only contract  
3. **Validate** — `scripts/validate-prompt.sh`  
4. **Execute or review** — host agent runs the improved plan (or shows it in Plan mode)

Bundled under the skill: references, generator assets, multi-CLI backends, offline smoke tests.
## Structure

```text
skills/prompt-improver/     ← install this package
├── SKILL.md
├── scripts/                # generate, validate, assemble, backends
├── references/             # principles, template, chaining
├── assets/                 # generator prompt
├── examples/               # before/after + fixtures
└── config/                 # optional settings defaults

plugins/prompt-improver/    ← Claude Code plugin wrapper
.claude-plugin/             ← marketplace catalog
tests/                      ← repo CI smoke tests
```

## Security

Shell scripts live in `skills/prompt-improver/scripts/`. Review `SKILL.md` and scripts before install — same caution as any code you run on your machine.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

```bash
bash tests/smoke-test.sh
```

## Roadmap

See [docs/ROADMAP.md](./docs/ROADMAP.md).

## License

[MIT](./LICENSE) © owenob1
