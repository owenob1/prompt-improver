# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-07-09

Initial public release.

### Added
- Agent skill package at `skills/prompt-improver/` ([Agent Skills](https://agentskills.io/) format)
- Claude Code marketplace packaging (`.claude-plugin/`, `plugins/prompt-improver/`)
- Portable generator scripts: assemble, generate, validate, multi-CLI backends
- Settings layers (defaults, user, project, env)
- Improvement-only generator contract
- Offline smoke tests (`tests/smoke-test.sh`) and GitHub Actions CI
- Prompting references, before/after examples, validation fixtures

### Install
```bash
npx skills add -g owenob1/prompt-improver
```
