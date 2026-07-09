# prompt-improver TODO

Tracks work for public release and multi-CLI robustness.

## Release Goals

- [x] Prepare prompt-improver for public release (scripts work offline; docs clear; CI green)
- [x] Core improvements for launch (path fixes, validation, backends, smoke tests)
- [x] README with install, quickstarts, config, compatibility table, structure
- [x] Contribution workflow (`CONTRIBUTING.md` + issue/PR templates)
- [x] Easy to use, extend, and contribute (adapters + smoke-test gate)

## Broad CLI Compatibility

- [x] Backend adapters for major CLIs (`scripts/backends/`)
- [x] Auto-detect preferred backends in order
- [x] Graceful fallback when headless is missing (`fallback_strategy: manual`)
- [x] Simple `/prompt-improver` / standalone entrypoints with no user preambles required
- [ ] Re-test adapters against current CLI flag surfaces as vendors change (ongoing)

Supported / target CLIs: Claude Code, Grok Build, Gemini CLI, Codex, OpenCode, Kimi, Kiro, Cline, others via adapters.

## Configuration & Overrides

- [x] `settings.json` layers (default → user → project → env)
- [x] Backend / model / max_tokens / research / thinking / fallback / preferred_backends / custom_command
- [x] Env var overrides (`PROMPT_IMPROVER_*`)
- [ ] Additional settings as community requests land

## Prevention of Premature Execution

- [x] IMPROVEMENT-ONLY contract in generator materials + raw-request wrapping
- [x] Documented in README / SKILL
- [ ] Periodic adversarial checks that host agents still respect the contract across CLI versions

## Modes & Output Formats

- [x] Task mode deprecated in SKILL, README, CONTRIBUTING
- [ ] Optional future: portable `--structured-tasks` export if demand appears

## Technical Architecture

- [x] Extensible backend system
- [x] Main entrypoint `scripts/generate-prompt.sh`
- [x] Validation via `scripts/validate-prompt.sh` (typecheck optional by default)
- [x] Assembler `scripts/assemble-generation-prompt.sh`
- [x] Offline smoke suite + GitHub Actions CI
- [ ] Optional: extract JSON content from grok `--output-format json` more robustly across versions

## Extensibility & Future Directions

- [x] Document MCP / standalone patterns in README
- [x] `scripts/standalone-improve.sh`
- [ ] Investigate a thin published CLI package if distribution demand grows
- [ ] More high-quality before/after examples

## Documentation

- [x] README (install, modes, config, compatibility, structure)
- [x] CONTRIBUTING.md
- [x] Issue + PR templates
- [x] SKILL.md architecture + deprecations
- [x] CHANGELOG.md
- [x] MIT license

## Other / Backlog

- [ ] Decide primary distribution (standalone repo vs skill marketplaces)
- [ ] Measure / document token cost of the generation step
- [ ] Evaluate recursive self-improvement of the generator prompt
- [ ] Expand real-world matrix testing across CLIs (auth, output formats)

---

**Prioritization**

- **P0 (launch)**: Done for this release — working scripts, docs, CI, improvement guard.
- **P1**: Ongoing adapter flag accuracy, more examples, adversarial guard tests.
- **P2**: Packaged CLI, MCP server, advanced settings.

Last updated: 2026-07-09
