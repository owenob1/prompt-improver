<div align="center">

# /prompt-improver

**Turn vague agent prompts into precise, verifiable specs — then run them.**

<br />

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![CI](https://github.com/owenob1/prompt-improver/actions/workflows/ci.yml/badge.svg)](https://github.com/owenob1/prompt-improver/actions/workflows/ci.yml)
[![Agent Skills](https://img.shields.io/badge/Agent%20Skills-compatible-blue)](https://agentskills.io/)
[![GitHub stars](https://img.shields.io/github/stars/owenob1/prompt-improver?style=social)](https://github.com/owenob1/prompt-improver/stargazers)

<br />

[Features](#-features) ·
[Install](#-install) ·
[Usage](#-usage) ·
[How it works](#-how-it-works) ·
[Models](#-default-generator-models) ·
[Advanced](#-advanced) ·
[Contributing](#-contributing)

</div>

---

## ✨ Features

| | |
|:--|:--|
| **Headless generation** | Improves prompts in a separate model call — not by grinding the host agent session |
| **Improvement-only** | Generator never implements your feature; it only rewrites the request |
| **Execute or plan** | Run immediately, or review the XML first |
| **Per-prompt model override** | `model:sonnet` / `model:gpt-5.5` like the `plan` flag |
| **Multi-CLI** | Claude Code, Grok Build, Gemini, Codex, and more |
| **Portable skill** | [Agent Skills](https://agentskills.io/) format · [skills.sh](https://skills.sh) · Claude marketplace |

---

## 📦 Install

**Recommended**

```bash
npx skills add -g owenob1/prompt-improver
```

<details>
<summary><strong>Other install options</strong></summary>

<br>

**Project only**

```bash
npx skills add owenob1/prompt-improver
```

**Claude Code — add marketplace**

```text
/plugin marketplace add owenob1/prompt-improver
```

**Claude Code — install plugin**

```text
/plugin install prompt-improver@prompt-improver
```

**Manual (clone + copy)**

```bash
git clone https://github.com/owenob1/prompt-improver.git && cp -R prompt-improver/skills/prompt-improver ~/.claude/skills/prompt-improver
```

</details>

---

## 🚀 Usage

```text
/prompt-improver "Fix the flaky auth tests"
```

### Flags

Leading tokens (any order), same idea as slash-command options:

| Flag | Effect |
|------|--------|
| *(none)* | Improve headlessly, then **execute** |
| `plan` | Improve headlessly, **show** XML, wait |
| `model:<id>` | Override generator model for this run |

```text
/prompt-improver plan "Add rate limiting"
/prompt-improver model:sonnet "Add rate limiting"
/prompt-improver plan model:gpt-5.5 "Refactor payments"
```

---

## ⚙️ How it works

```text
  you
   │
   ▼
 host agent  ──starts──►  /prompt-improver
   │
   │  headless generator (mid-tier model, improvement-only)
   ▼
 structured XML spec
   │
   ▼
 host agent  ──executes──►  your task
```

1. **Triage** — skip generation if the input is already a solid spec  
2. **Generate** — headless rewrite via `scripts/generate-prompt.sh`  
3. **Validate** — structural checks  
4. **Execute or review** — host runs the plan (or shows it with `plan`)

Host frontier models (Fable, Opus, …) stay on **execution**. Generation defaults to a capable mid-tier model.

---

## 🧠 Default generator models

| Backend | Default | Notes |
|---------|---------|--------|
| `claude` | `sonnet` → **Sonnet 5** | Daily-driver quality for structured prompts |
| `grok` | `grok-composer-2.5-fast` | Strong speed / quality balance |
| `gemini` | `gemini-2.5-pro` | Pro reasoning for specs |
| `codex` | `gpt-5.5` | GPT-5 family Codex default |

**Pick order:** `model:` flag → env/settings → table → CLI default.

---

## 🔧 Advanced

<details>
<summary><strong>Standalone CLI (no agent skill)</strong></summary>

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
<summary><strong>Settings</strong></summary>

<br>

```bash
mkdir -p ~/.config/prompt-improver
cp skills/prompt-improver/config/settings.example.json \
  ~/.config/prompt-improver/settings.json
```

| Key / env | Purpose |
|-----------|---------|
| `model` / `PROMPT_IMPROVER_MODEL` | Force one generator model |
| `default_models` | Per-backend defaults |
| `backend` / `PROMPT_IMPROVER_BACKEND` | `auto`, `claude`, `grok`, … |

</details>

<details>
<summary><strong>Repository layout</strong></summary>

<br>

```text
skills/prompt-improver/   # installable skill
plugins/prompt-improver/  # Claude Code plugin
.claude-plugin/           # marketplace catalog
tests/                    # smoke tests
```

</details>

<details>
<summary><strong>Security</strong></summary>

<br>

Scripts under `skills/prompt-improver/scripts/` run shell and may invoke coding CLIs. Review before install.

</details>

---

## 🤝 Contributing

```bash
bash tests/smoke-test.sh
```

[CONTRIBUTING.md](./CONTRIBUTING.md) · [Roadmap](./docs/ROADMAP.md)

---

## 📄 License

[MIT](./LICENSE) © [owenob1](https://github.com/owenob1)
