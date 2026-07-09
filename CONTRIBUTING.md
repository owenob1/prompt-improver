# Contributing to prompt-improver

Thank you for helping make prompt-improver better.

## Layout (important)

Installable skill content lives only under:

```text
skills/prompt-improver/
```

Root `README.md` is for humans. Claude marketplace packaging is under `.claude-plugin/` and `plugins/`.

## Principles

Contributions should respect `skills/prompt-improver/references/prompting-principles.md`:

- Verification and self-check are highest leverage
- Few-shot examples with reasoning
- `<approach>` and `<escape>` over forced workarounds
- Concrete specs, not vague adjectives

## Workflow

1. Open an issue for large changes.
2. Branch from `main`.
3. Make focused changes inside the skill package (or marketplace manifests).
4. Verify:
   ```bash
   bash tests/smoke-test.sh
   ```
5. Update `CHANGELOG.md` for user-facing changes.
6. Open a PR.

## What we want

- Better references / examples
- New or fixed backend adapters (`skills/prompt-improver/scripts/backends/`)
- Validation improvements
- Install/docs clarity for skills.sh and Claude marketplace

## License

By contributing, you agree your contributions are licensed under the MIT License.
