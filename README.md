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

**Headless generation is the core design.** Improving the prompt is a separate, improvement-only model call — not something the host agent should grind through as a full in-session rewrite.

```text
Host agent  →  headless generator (cheap/fast model)  →  XML spec  →  host executes
```

1. **Triage** — skip generation if the input is already a solid spec  
2. **Generate (headless)** — `scripts/generate-prompt.sh` embeds references + the improvement-only contract and calls a coding CLI headlessly  
3. **Validate** — structural checks via `scripts/validate-prompt.sh`  
4. **Execute or review** — the **host** agent runs the improved plan (or shows it in Plan mode)

### Generator model vs host model

| Role | Who | Model |
|------|-----|--------|
| **Generator** | Headless CLI (`generate-prompt.sh`) | Prefer a **fast/cheap** model via `PROMPT_IMPROVER_MODEL` |
| **Executor** | Your interactive agent (Fable, Claude Code, Grok, …) | Your normal session model |

If you leave `model` unset, the backend CLI’s default is used — which can accidentally be another full-cost frontier run. **Pin a cheap generator model** in settings or env:

```bash
# Example: generate with an explicit model, then use the result in your agent
export PROMPT_IMPROVER_MODEL="your-fast-model-id"
export PROMPT_IMPROVER_BACKEND="claude"   # or grok, gemini, …

bash skills/prompt-improver/scripts/generate-prompt.sh \
  --mode plan \
  --raw-input "Add rate limiting to the payment API"
```

User/project settings (optional):

```bash
mkdir -p ~/.config/prompt-improver
cp skills/prompt-improver/config/settings.example.json \
  ~/.config/prompt-improver/settings.json
# edit "model" and "backend"
```

Bundled under the skill:

- Prompting principles & XML template (`references/`)
- Generator instructions (`assets/`)
- Multi-CLI headless backends (`scripts/backends/`)
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
