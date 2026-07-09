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
[Models](#-default-generator-models) ·
[How it works](#-how-it-works) ·
[Advanced](#-advanced) ·
[Contributing](#-contributing) ·
[Full model list](./skills/prompt-improver/references/models-supported.md) ·
[Custom backends](./docs/CUSTOM-BACKENDS.md)

</div>

---

## ✨ Features

| | |
|:--|:--|
| **Headless generation** | Improves prompts in a separate model call — not by grinding the host agent session |
| **Improvement-only** | Generator never implements your feature; it only rewrites the request |
| **Execute or plan** | Run immediately, or review the XML first |
| **Any model override** | `model:fable-5`, `model:sonnet`, `model:gpt-5.5`, … — routes to the right CLI when installed |
| **Cross-host / cross-CLI** | Claude host + GPT generator, Grok host + Claude generator — OK if that CLI is on PATH |
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

```bash
# Improve + execute (default)
/prompt-improver "Fix the flaky auth tests"

# Improve only — review the XML before running
/prompt-improver plan "Fix the flaky auth tests"

# Use a specific generator model for this run
/prompt-improver model:fable-5 "Fix the flaky auth tests"
```

| Flag | Effect |
|------|--------|
| *(none)* | Improve headlessly, then **execute** |
| `plan` | Improve headlessly, **show** XML, wait |
| `model:<id>` | Override generator model for this run (any family / future ID) |

---

## 🧠 Default generator models

| Backend CLI | Default model | Notes |
|-------------|---------------|--------|
| `claude` | `sonnet` → Sonnet 5 | Daily-driver structured rewrite |
| `grok` | `grok-composer-2.5-fast` | Fast high-quality improver |
| `gemini` | `gemini-2.5-pro` | Pro reasoning for specs |
| `codex` | `gpt-5.5` | GPT-5 family Codex default |

**Model override:** `model:` flag → env/settings → table → CLI default.

<details>
<summary><strong>Recognized models & aliases</strong></summary>

<br>

Pass full IDs or short aliases. **Unknown future IDs pass through** (e.g. `gpt-5.6-sol-ultra`, `grok-4.6`) and still route by family prefix.

| Family | Examples (`model:…`) | Generator CLI |
|--------|----------------------|---------------|
| Claude | `fable-5`, `fable`, `opus`, `sonnet`, `haiku`, `claude-*` | `claude` |
| Grok | `grok-4.5`, `grok-4.3`, `grok-composer-2.5-fast`, `grok-build`, `composer-*` | `grok` |
| Gemini | `gemini-2.5-pro`, `gemini-2.5-flash`, `gemini-3.1-pro`, `gemini-*` | `gemini` |
| OpenAI / Codex | `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, `sol`, `terra`, `luna`, `gpt-5.5`, `gpt-5`, `gpt-5.3-codex`, `o4-mini`, `gpt-*` | `codex` |

**Cross-host is fine:** Claude Code + `model:gpt-5.6-sol` uses **codex** if installed; Grok + `model:sonnet` / `model:fable-5` uses **claude** if installed.

</details>

<details>
<summary><strong>Access / rate-limit fallbacks</strong></summary>

<br>

If a model is unavailable, restricted, or out of usage, headless generation:

1. Walks the **model** cascade on the current CLI (first success wins)
2. On **account/org** limits, skips the rest of that CLI and tries the **next installed** generator
3. If every generator is limited → **host bounce**: the calling agent CLI finishes the user request in-session

| CLI | Fallback |
|-----|----------|
| Claude | fable → opus → sonnet |
| Codex | sol → terra → luna → gpt-5.5 |
| Grok | grok-4.5 → composer-2.5-fast → grok-build |
| Gemini | gemini-2.5-pro → gemini-2.5-flash |

</details>

**Full alias + cascade reference:** [models-supported.md](./skills/prompt-improver/references/models-supported.md) (also under `docs/MODELS.md`).

---

## ⚙️ How it works

<p align="center">
  <img src="docs/how-it-works.svg" alt="You → host agent → headless generator → XML spec → execute task" width="780" />
</p>

1. **Triage** — skip generation if the input is already a solid spec  
2. **Generate** — headless rewrite via `scripts/generate-prompt.sh` (model/backend resolved as above)  
3. **Validate** — structural checks  
4. **Execute or review** — host runs the plan (or shows it with `plan`)

---

## 🔧 Advanced

<details>
<summary><strong>Standalone CLI (no agent skill)</strong></summary>

<br>

```bash
# Standalone: improve only (plan mode), default generator model
bash skills/prompt-improver/scripts/standalone-improve.sh "Fix the flaky auth tests" plan

# Same, but force Fable as the generator
bash skills/prompt-improver/scripts/standalone-improve.sh "Fix the flaky auth tests" plan fable-5

# Lower-level generate script (same flags the skill uses headlessly)
bash skills/prompt-improver/scripts/generate-prompt.sh \
  --mode plan \
  --raw-input "Fix the flaky auth tests" \
  --model fable-5
```

</details>

<details>
<summary><strong>Settings</strong></summary>

<br>

```bash
mkdir -p ~/.config/prompt-improver
cp skills/prompt-improver/config/settings.example.json \
  ~/.config/prompt-improver/settings.json
# Keys starting with // are comments (safe to leave or delete)
```

| Key / env | Purpose |
|-----------|---------|
| `model` / `PROMPT_IMPROVER_MODEL` | Force one generator model |
| `default_models` | Per-backend defaults |
| `backend` / `PROMPT_IMPROVER_BACKEND` | `auto`, `claude`, `grok`, `opencode`, … |
| `custom_command` / `PROMPT_IMPROVER_CUSTOM_COMMAND` | Any CLI: prompt on stdin → improved text on stdout |

Built-in backends include Claude, Grok, Gemini, Codex, Cline, OpenCode, Kimi, and Kiro. For anything else (Kilo, private wrappers, …), use **custom mode** — full guide: [docs/CUSTOM-BACKENDS.md](./docs/CUSTOM-BACKENDS.md).

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
