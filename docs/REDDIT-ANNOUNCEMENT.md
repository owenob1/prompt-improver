# Reddit announcement — prompt-improver

Copy a **title** + the **body** into Reddit. Reddit’s editor accepts this Markdown almost as-is (paste into Markdown mode if the fancy editor mangles it).

---

## Title (recommended)

```text
Introducing /prompt-improver: The antidote to bad prompting
```

### Alternates

```text
I open-sourced a skill that turns vague agent prompts into structured specs (then runs them)
```

```text
Stop pasting "fix the auth tests" into Claude/Grok and praying — prompt-improver
```

```text
Headless prompt improver for coding agents (Claude, Grok, Codex, Gemini) — MIT
```

---

## Body

```markdown
**Introducing `/prompt-improver`: the antidote to bad prompting.**

**TL;DR:** An Agent Skill that rewrites rough requests into precise, verifiable XML specs in a **separate headless model call**, then your host agent executes (or you review with `plan`). Portable across major coding CLIs. MIT.

**Repo:** https://github.com/owenob1/prompt-improver

---

### The problem

Most of the time the agent fails because the *prompt* is vague: no verification, no constraints, no task split. You either:

* burn the expensive host session rewriting the prompt yourself, or
* get half-baked code with no "done when…" criteria.

### What this does

1. You run something like:  
   `/prompt-improver "Fix the flaky auth tests"`
2. A **headless** generator (not your frontier host by default) turns that into a structured spec (tasks, requirements, verification, escape hatches).
3. Host agent **executes** — or you use `plan` to review the XML first.

Important: the generator is **improvement-only**. It rewrites the request; it does **not** implement the feature. That keeps generation cheap and avoids double-billing the same frontier model for "rewrite then code."

### Defaults (by host — not "first CLI on PATH")

* Claude host → Claude + `sonnet`
* Grok host → Grok + `composer` (fast)
* Override per run: `model:fable-5`, `model:gpt-5.5`, …
* Rate limits cascade models → other CLIs → bounce back to the host so the session still finishes

### Install

    npx skills add -g owenob1/prompt-improver

Claude Code marketplace also works if you prefer plugins.

### Usage

    /prompt-improver "Fix the flaky auth tests"
    /prompt-improver plan "Fix the flaky auth tests"
    /prompt-improver model:sonnet "Add rate limiting"

### Why I built it

I got tired of re-prompting the same rough idea three times. Headless improve → clear verification → execute has been a better loop for me than "ask Opus to think harder about the same sentence."

Happy to take feedback, especially:

* default models / host detection
* XML shape vs what your agent actually follows
* backends you use that aren't wired yet (`custom_command` exists as an escape hatch)

**MIT** · https://github.com/owenob1/prompt-improver
```

---

## Optional first comment

```markdown
Stack: Agent Skills format, works with [skills.sh](https://skills.sh). Generator shells out to whatever headless CLI you have (`claude`, `grok`, `codex`, `gemini`, …). Full model/alias list and custom backends are in the repo under `docs/` and `references/`.
```

---

## Subreddit tips

| Sub | Angle |
|-----|--------|
| r/ClaudeAI | Claude Code skill / headless sonnet improver |
| r/ChatGPTCoding | Codex / `model:gpt-5.5` cross-host |
| r/cursor | Agent Skills / portable skill |
| r/LocalLLaMA | Only if you emphasize `custom_command` / local CLIs |

- Prefer **Markdown mode** when pasting (especially code blocks).
- Reddit treats 4-space indent as a code block (used above for install/usage).
- Don’t multi-post the exact same text to many subs in one minute — stagger and tweak the first line.

---

## Reddit-flavored notes (if something looks wrong)

| You want | Use |
|----------|-----|
| Bold | `**text**` |
| Italic | `*text*` |
| Bullet list | `* item` or `- item` |
| Numbered list | `1. item` |
| Inline code | `` `code` `` |
| Code block | 4 spaces indent, or fenced \`\`\` in some clients |
| Link | `[label](https://…)` |
| Horizontal rule | `---` |

Old Reddit is pickier than new Reddit; 4-space code blocks are the safest.
