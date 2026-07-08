# Contributing to prompt-improver

Thank you for helping make prompt-improver better for everyone.

## Core Principles

Any contribution must respect the philosophy documented in `references/prompting-principles.md`:

- Verification and self-check are highest leverage
- Few-shot examples with reasoning are extremely powerful
- Use `<approach>` blocks for important decisions
- Add `<escape>` clauses instead of forcing workarounds
- Write task-specific constraints, not generic boilerplate
- Be concrete. Replace adjectives with specifications.
- Data first, instructions later

We apply the same standards to changes in this repo that the skill teaches agents to apply to code.

## How to Contribute

1. **Open an issue** (or start a discussion) before large changes.
2. **Fork + branch** from `main` (or the current release branch).
3. **Make focused changes**.
4. **Verify**:
   - Run `bash scripts/validate-prompt.sh` on any example prompts or generated output you touch.
   - Re-read changed files.
   - Update documentation (especially README and SKILL.md) when behavior changes.
5. **Open a PR** with a clear description of the problem and solution.

## What We're Looking For

- Improvements to the reference materials (principles, template, chaining, examples)
- Better portability across coding CLIs (new invocation patterns, better documentation, adapters)
- High-quality before/after examples that demonstrate specific techniques
- Fixes to validation logic in `scripts/validate-prompt.sh`
- Documentation and README improvements
- Making the generator prompt (`assets/generation-agent-prompt.md`) more effective and portable

## Modes & Deprecations

- `execute` and `plan` are the primary supported modes.
- Task mode is deprecated. Structured `<task>` output is still valuable and lives in the XML template.
- If you propose new flags or output formats, they must work (or have clear documented fallbacks) when the skill is used with Claude Code, Grok Build, Gemini CLI, Cline, OpenCode, Kiro, Kimi Code CLI, and similar tools — via their standard headless/prompt flags.

## Style

- Follow the tone and precision of the existing references.
- Prefer clarity over cleverness.
- When adding rules or examples, explain the *why* (the failure mode being prevented).

## Questions?

Open an issue. We're happy to discuss approach before you invest time.

Thanks for contributing!