# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-07-09

### Changed
- **Marketplace layout**: canonical skill package moved to `skills/prompt-improver/` for [skills.sh](https://skills.sh) / `npx skills add` discovery.
- Added Claude Code marketplace packaging: `.claude-plugin/marketplace.json` and `plugins/prompt-improver/`.
- Root `README.md` rewritten install-first (global `-g`, project, Claude marketplace, manual).
- `SKILL.md` cleaned to portable Agent Skills frontmatter (`name`, `description`, `license`, `metadata`).
- `LICENSE.txt` → `LICENSE`; roadmap moved to `docs/ROADMAP.md`.
- Repo smoke tests live in `tests/smoke-test.sh` (still runs skill-internal checks).

### Fixed
- `npx skills add owenob1/prompt-improver --list` previously returned “No skills found” for root-only layout quirks; skill is now under the standard `skills/` container.

## [6.1.1] — 2026-07-09

### Fixed
- `scripts/lib/settings.sh` no longer overwrites the caller's `SCRIPT_DIR`, which broke backend discovery (`scripts/backends/*.sh`).
- `scripts/generate-prompt.sh` resolves repo root as `scripts/..` (was incorrectly going up two levels before settings load).
- Backend adapters exit non-zero when the CLI is missing instead of printing a success-looking message.
- `scripts/standalone-improve.sh` no longer crashes under `set -u` when invoked without arguments.
- Preferred backend order is respected (no longer hard-preferring `claude` whenever it is installed).
- `validate-prompt.sh` treats missing typecheck as a **warning** by default (skill/docs and script-only repos). Set `PROMPT_IMPROVER_REQUIRE_TYPECHECK=1` for a hard error.

### Added
- `scripts/smoke-test.sh` offline test suite (no API keys required).
- GitHub Actions CI workflow (`.github/workflows/ci.yml`).
- Example validation fixtures under `examples/fixtures/`.
- Public-launch README polish: install paths, clearer quickstarts, accurate project tree.

### Changed
- Default `preferred_backends` includes all shipped adapters (`codex` instead of non-existent `openai` backend name).
- Settings and README document environment variable overrides consistently.

## [6.1.0] — 2026-07-08

### Added
- Multi-CLI backend adapters under `scripts/backends/`.
- Settings system (`config/settings.default.json`, project/user overrides).
- Global IMPROVEMENT-ONLY contract in generator materials.
- Contribution templates and public README.

### Changed
- Task mode marked deprecated; execute and plan remain primary modes.
