# prompt-improver

**Transform vague prompts into precise, verifiable, structured XML prompts that coding agents execute reliably.**

prompt-improver is a portable skill and set of prompting principles that takes rough user intent and turns it into high-quality, executable specifications. It works across major coding CLI agents — both with strong headless support and without.

## Why it works

It systematically applies battle-tested prompting techniques:

- **Verification + self-check** at every step (highest leverage)
- Few-shot examples with reasoning (the most effective steering technique)
- `<approach>` blocks for think-then-commit reasoning
- Explicit `<escape>` clauses so agents flag problems instead of silently failing
- Task-specific constraints instead of generic boilerplate
- Data-first ordering and concrete specifications
- Strict validation of generated prompts

These patterns are documented in the `references/` and demonstrated in `examples/before-after.md`.

## Quickstart

### Using with Grok Build (this environment)

```bash
/prompt-improver plan "your vague request here"
# or just
/prompt-improver "your vague request here"
```

### Portable usage with any CLI (recommended for most agents)

We provide a small helper that assembles the generator instructions + all reference materials:

```bash
# Assemble once
PROMPT=$(bash scripts/assemble-generation-prompt.sh "Add rate limiting to the API")

# Then use with your favorite CLI
claude -p "$PROMPT"
gemini -p "$PROMPT"
grok -p "$PROMPT"
# etc.
```

### Using with Claude Code (headless)

```bash
claude -p "$(cat references/* examples/* assets/generation-agent-prompt.md) RAW INPUT: Add proper error handling and retries to the payment flow" --allowedTools "Read,Write,Edit,Bash"
```

### Using with Gemini CLI (headless)

```bash
gemini -p "$(cat references/* examples/* assets/generation-agent-prompt.md) RAW INPUT: Refactor the auth module to use JWT with refresh tokens" 
```

### Using with Cline, OpenCode, Kimi Code CLI, Kiro CLI, etc.

Most modern coding CLIs support a direct prompt / headless flag (`-p`, `--prompt`, `exec`, etc.). Feed them the core materials:

```bash
YOUR_CLI_HEADLESS_FLAG "$(cat references/xml-template.md references/prompting-principles.md references/prompt-chaining.md examples/before-after.md assets/generation-agent-prompt.md) 

Improve this request: <your original vague request>"
```

The generator will return a clean XML prompt you can then feed back to the same (or any other) agent.

**Non-headless / interactive use**: Paste the contents of the `references/` and `assets/generation-agent-prompt.md` files (plus your raw request) into any capable agent and ask it to act as the prompt improver.

## Modes

| Mode     | Invocation                  | What happens |
|----------|-----------------------------|--------------|
| **Execute** (default) | `/prompt-improver "..."`   | Generate improved prompt internally, give a brief plan, then execute it. |
| **Plan** | `/prompt-improver plan "..."` | Generate the full structured XML prompt, show it for review, then let you decide (Execute / Revise / Edit / Discard). |

**Task mode is deprecated.** The previous integration with an external persistent task system is no longer active. The underlying generator can still produce excellent structured `<task>` blocks inside the XML when decomposition is useful. You can request task-style output explicitly in your prompt.

## How it works

1. **Triage** the input (trivial / already good / rough / mixed).
2. Summarize conversation context.
3. Load the reference materials (XML template, prompting principles, chaining guidance, before/after examples).
4. A specialized generator produces a high-quality XML prompt.
5. The prompt is validated (`scripts/validate-prompt.sh`).
6. You either review it (Plan) or it is executed with strong verification.

The heavy lifting of good prompting lives in the reference files so the same high standards apply no matter which CLI you use.

## Project structure

```
.
├── SKILL.md                      # Main skill definition (portable)
├── assets/
│   └── generation-agent-prompt.md
├── examples/
│   └── before-after.md
├── references/
│   ├── xml-template.md
│   ├── prompting-principles.md
│   └── prompt-chaining.md
├── scripts/
│   ├── gather-context.sh
│   └── validate-prompt.sh
└── README.md
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) (coming soon — the contribution workflow is being formalized as part of this release).

We care deeply about:
- Preserving the prompting principles and verification standards
- Keeping the skill portable across CLIs
- Clear, testable improvements

## License

MIT — see LICENSE.txt.

---

Made with the same rigor the skill itself teaches. Use it to make your agents dramatically more reliable.