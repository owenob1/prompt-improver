# prompt-improver

Transform vague prompts into precise, verifiable structured XML that coding agents can execute reliably.

Compatible with the [Agent Skills](https://agentskills.io/) format. Works with Claude Code, Grok Build, Codex, Cursor, Gemini CLI, and other skill-aware agents.

## Install

### Global (recommended) — skills.sh CLI

```bash
npx skills add -g owenob1/prompt-improver
```

### Project-local

```bash
npx skills add owenob1/prompt-improver
```

List without installing:

```bash
npx skills add owenob1/prompt-improver --list
```

### Claude Code marketplace

```text
/plugin marketplace add owenob1/prompt-improver
/plugin install prompt-improver@prompt-improver
```

Then invoke:

```text
/prompt-improver plan "Add rate limiting to the payment API"
/prompt-improver "Fix the flaky auth tests"
```

### Manual copy

```bash
git clone https://github.com/owenob1/prompt-improver.git
# Symlink or copy the skill package into your agent skills dir:
#   Claude Code:  ~/.claude/skills/prompt-improver
#   Many agents:  ~/.agents/skills/prompt-improver
cp -R prompt-improver/skills/prompt-improver ~/.claude/skills/prompt-improver
```

## Use

| Mode | Command | What happens |
|------|---------|--------------|
| **Execute** (default) | `/prompt-improver "…"` | Improve the prompt, then run the work with verification |
| **Plan** | `/prompt-improver plan "…"` | Improve the prompt, show XML for review, wait for your decision |

The generator is **improvement-only**: it will not start building what you asked for while it is improving the prompt.

## What you get

- Structured XML with tasks, verification, escape clauses, and a final check block
- Portable scripts: assemble materials, generate headlessly, validate output
- Multi-CLI backends (`claude`, `grok`, `gemini`, …) with manual fallback if headless fails

## Optional: run scripts without an agent

From a clone of this repo:

```bash
# Offline smoke tests (no API keys)
bash tests/smoke-test.sh

# Assemble generator materials for any CLI
bash skills/prompt-improver/scripts/assemble-generation-prompt.sh "your request"

# One-shot improve (needs a coding CLI on PATH, or prints manual fallback)
bash skills/prompt-improver/scripts/standalone-improve.sh "your request" plan
```

## Repository layout

```text
.
├── README.md                 # You are here (humans)
├── skills/prompt-improver/   # Canonical skill package (install this)
│   ├── SKILL.md
│   ├── scripts/
│   ├── references/
│   ├── assets/
│   ├── examples/
│   └── config/
├── plugins/prompt-improver/  # Claude Code plugin wrapper
├── .claude-plugin/           # Marketplace catalog
└── tests/                    # Repo CI smoke tests
```

## Security

This skill includes shell scripts under `skills/prompt-improver/scripts/`. Treat installs like code: review `SKILL.md` and scripts before use, especially backends that invoke external CLIs.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Run `bash tests/smoke-test.sh` before opening a PR.

## License

[MIT](./LICENSE)
