<div align="center">

# /prompt-improver

**Turn vague prompts into precise, verifiable specs your coding agent can execute.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![CI](https://github.com/owenob1/prompt-improver/actions/workflows/ci.yml/badge.svg)](https://github.com/owenob1/prompt-improver/actions/workflows/ci.yml)
[![Agent Skills](https://img.shields.io/badge/Agent%20Skills-compatible-blue)](https://agentskills.io/)

[Install](#install) · [Usage](#usage) · [How it works](#how-it-works) · [Structure](#structure)

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

Once installed, invoke the skill:

```text
/prompt-improver plan "Add rate limiting to the payment API"
/prompt-improver "Fix the flaky auth tests"
```

| Mode | Command | Behaviour |
|------|---------|-----------|
| **Execute** (default) | `/prompt-improver "…"` | Improve the prompt, then run the work with verification |
| **Plan** | `/prompt-improver plan "…"` | Improve the prompt, show the XML, wait for your decision |

### Without installing (one-shot)

```bash
# Assemble materials → paste into any coding CLI
bash skills/prompt-improver/scripts/assemble-generation-prompt.sh "your request"

# Headless improve if a supported CLI is on PATH
bash skills/prompt-improver/scripts/standalone-improve.sh "your request" plan
```

## How it works

1. **Triage** — skip generation if the input is already a solid spec  
2. **Generate** — embed references + improvement-only contract → structured XML  
3. **Validate** — `scripts/validate-prompt.sh` checks tasks, verification, and check blocks  
4. **Execute or review** — run the work, or inspect the plan first  

### Who runs the “improver” model?

**Default (when you invoke `/prompt-improver` inside an agent):** generation runs **in the same session**. The host agent follows the skill instructions and writes the improved XML itself. There is **no** automatic second process and **no** nested “spawn yourself headless” loop.

That matters for cost: if a frontier agent (e.g. a high-end Claude / Fable / Grok session) shelled out to another full copy of itself to improve the prompt, you would pay roughly twice for the same class of model. The skill is written to **avoid that**.

**Optional (standalone scripts / CI):** `scripts/generate-prompt.sh` can call a coding CLI headlessly. Use this when you want improvement **outside** an interactive agent, or when you pin a **cheaper/faster** model for generation only:

```bash
PROMPT_IMPROVER_MODEL="<fast-or-cheap-model>" \
  bash skills/prompt-improver/scripts/generate-prompt.sh \
  --mode plan \
  --raw-input "your request"
```

Set `PROMPT_IMPROVER_BACKEND` / `model` in settings if you use this path often. Leaving model unset uses the CLI’s default — which may still be expensive.

Bundled under the skill:

- Prompting principles & XML template (`references/`)
- Generator instructions (`assets/`)
- Multi-CLI backends for optional headless generation (`scripts/backends/`)
- Offline smoke tests (`tests/smoke-test.sh`)

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
