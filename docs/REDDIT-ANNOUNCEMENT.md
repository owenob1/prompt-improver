# Reddit announcement — prompt-improver

Copy **title** + **body** into Reddit (Markdown mode). Structure: explainer → repo → install snippets.

---

## Title

```text
Introducing /prompt-improver: The antidote to bad prompting
```

---

## Body

```markdown
**Introducing `/prompt-improver`: the antidote to bad prompting.**

Vague prompts kill agent runs. No verification, no constraints, no task split — so you either burn the frontier session rewriting the request, or you get half-baked code with no "done when."

**What it does:**

* Rewrites your rough request into a **precise, verifiable XML spec** (tasks, requirements, checks)
* **Context aware** — uses your session summary and working directory
* Pulls stack / test / build commands and real repo paths so the spec fits *this* project
* Rewrites in a **separate headless call** — doesn't grind your host session
* **Improvement-only** — never implements the feature
* Host then **executes**, or `plan` to review the XML first

Works across Claude, Grok, Codex, Gemini, and friends. MIT.

**Repo:** https://github.com/owenob1/prompt-improver

---

**Install** (Agent Skills / skills.sh):

    npx skills add -g owenob1/prompt-improver

**Claude Code** (marketplace):

    /plugin marketplace add owenob1/prompt-improver
    /plugin install prompt-improver@prompt-improver

**Usage:**

    /prompt-improver "Fix the flaky auth tests"
    /prompt-improver plan "Fix the flaky auth tests"
    /prompt-improver model:sonnet "Add rate limiting"
```

---

## Optional first comment

```markdown
Full model list, fallbacks, and `custom_command` for other CLIs are in the repo under `docs/` and `references/`. Feedback welcome.
```

---

## Notes

- Prefer **Markdown mode** when pasting.
- 4-space indent = code blocks on old Reddit.
- Stagger cross-posts; tweak the first line per sub.
