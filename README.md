<div align="center">

# /prompt-improver

**Turn vague agent prompts into precise, verifiable specs — then run them.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![CI](https://github.com/owenob1/prompt-improver/actions/workflows/ci.yml/badge.svg)](https://github.com/owenob1/prompt-improver/actions/workflows/ci.yml)
[![Agent Skills](https://img.shields.io/badge/Agent%20Skills-compatible-blue)](https://agentskills.io/)

[Install](#1-install) · [Use](#2-use) · [What happens](#3-what-happens) · [Models](#4-default-generator-models) · [Advanced](#5-advanced-optional) · [Contributing](#contributing)

</div>

---

## 1. Install

```bash
npx skills add -g owenob1/prompt-improver
```

| Also | Command |
|------|---------|
| Project only | `npx skills add owenob1/prompt-improver` |
| Claude Code | `/plugin marketplace add owenob1/prompt-improver` then `/plugin install prompt-improver@prompt-improver` |
| Manual | Copy `skills/prompt-improver/` → `~/.claude/skills/prompt-improver` |

---

## 2. Use

```text
/prompt-improver "Fix the flaky auth tests"
```

Optional leading flags (any order):

| Flag | Effect |
|------|--------|
| `plan` | Improve, **show** the XML, wait before running |
| `model:<id>` | Override the **generator** model for this run |

```text
/prompt-improver plan "Add rate limiting"
/prompt-improver model:sonnet "Add rate limiting"
/prompt-improver plan model:gpt-5.5 "Refactor payments"
```

---

## 3. What happens

```text
you → host agent → headless generator (mid-tier model) → XML spec → host executes
```

1. Host starts `/prompt-improver`
2. A **separate headless** call rewrites the request (improvement-only — it does not build your feature)
3. Host **executes** that spec (or shows it in `plan` mode)

That split is intentional: generation uses a strong but not frontier-host model; your interactive session only runs the plan.

---

## 4. Default generator models

| CLI backend | Default model | Role |
|-------------|---------------|------|
| `claude` | `sonnet` → Sonnet 5 | Structured rewrite quality |
| `grok` | `grok-composer-2.5-fast` | Fast agentic improver |
| `gemini` | `gemini-2.5-pro` | Spec reasoning |
| `codex` | `gpt-5.5` | GPT-5 family default for Codex |

Not host-frontier (e.g. Fable / Opus). Override with `model:…` when needed.

**Model pick order:** `model:` flag → `PROMPT_IMPROVER_MODEL` / settings → table above → CLI default.

---

## 5. Advanced (optional)

<details>
<summary><strong>Standalone CLI (no agent)</strong></summary>

<br>

```bash
bash skills/prompt-improver/scripts/standalone-improve.sh "your request" plan
bash skills/prompt-improver/scripts/standalone-improve.sh "your request" plan sonnet

bash skills/prompt-improver/scripts/generate-prompt.sh \
  --mode plan \
  --raw-input "your request" \
  --model sonnet
```

</details>

<details>
<summary><strong>Settings file</strong></summary>

<br>

```bash
mkdir -p ~/.config/prompt-improver
cp skills/prompt-improver/config/settings.example.json \
  ~/.config/prompt-improver/settings.json
```

Edit `model`, `default_models`, or `backend`. Env wins: `PROMPT_IMPROVER_MODEL`, `PROMPT_IMPROVER_BACKEND`.

</details>

<details>
<summary><strong>Repo layout</strong></summary>

<br>

```text
skills/prompt-improver/   # installable skill (SKILL.md, scripts, refs)
plugins/prompt-improver/  # Claude Code plugin wrapper
.claude-plugin/           # marketplace catalog
tests/                    # smoke tests
```

</details>

<details>
<summary><strong>Security</strong></summary>

<br>

`skills/prompt-improver/scripts/` runs shell and may call coding CLIs. Read them before install.

</details>

---

## Contributing

```bash
bash tests/smoke-test.sh
```

See [CONTRIBUTING.md](./CONTRIBUTING.md) · Roadmap: [docs/ROADMAP.md](./docs/ROADMAP.md)

## License

[MIT](./LICENSE) © owenob1
