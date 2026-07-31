# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- **codex backend produced garbage instead of a prompt.** `codex exec` streams its
  whole session log to stdout — version banner, workdir/model/session-id block,
  `hook:` lines, MCP and skill-loading `ERROR` lines, the echoed prompt, and a
  trailing token count — and `codex.sh` piped all of it through as the improved
  prompt. It now takes the agent's final message from `--output-last-message`,
  and only falls back to emitting the session log (on failure) so rate-limit
  detection can still cascade.
- **codex backend consumed inherited stdin**, appending a duplicate `<stdin>`
  block to the prompt. It now runs with `</dev/null`.
- **grok backend never ran.** The shipped default `grok-composer-2.5-fast` is
  retired — `grok models` lists only `grok-4.5`, and the old id fails with
  `Invalid params: "unknown model id"`. Defaults and fallback chains now target
  `grok-4.5`; the retired composer/`grok-build` aliases are still accepted but
  cascade to `grok-4.5` instead of dead-ending.
- **grok output carried a narration line** ahead of the XML. `generate-prompt.sh`
  now drops anything before the first XML tag, for every backend.

### Changed
- Default generator models: `claude` → `claude-opus-5`, `grok` → `grok-4.5`,
  `codex` → `gpt-5.6-terra` (`gemini` unchanged). Added `opus-5` / `opus5` /
  `claude-opus-5` aliases; note the claude CLI rejects the bare string `opus-5`,
  so the shipped default is the full `claude-opus-5` id.
- `codex`/`openai` shorthand now resolves to `gpt-5.6-terra` and cascades
  `gpt-5.6-terra` → `gpt-5.6-luna` → `gpt-5.5`.

### Security
- The codex generator ran with `sandbox: danger-full-access` and
  `approval: never`, letting it execute the user's request rather than only
  improve the prompt. It now runs `--sandbox read-only`.

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
