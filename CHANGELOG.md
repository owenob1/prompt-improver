# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added (experimental)
- **Jev fast path, v2** (`fast_path.mode`: `off` by default, or `auto` | `ground`).
  - Specs are compiled from a reviewed library of cells (`assets/library/`). Jev, TypeSafe's decision model, only picks: the cell, the slot values among verbatim candidates from the request and the repository, the project rules that apply, and whether each item's guard passes. It never writes text.
  - Tier A serves the compiled spec with no LLM call (about 1.3 s on a cold cache). Tier B keeps the compiled spec and has a fast model write only the sections the library could not fill, such as code-specific approach notes (about 14 s instead of 35 s). Tier C adds the facts Jev selected (target usage text, callers, rules, test command and file) to the full generation prompt.
  - Guards make serving auditable: an item that does not fit the request is dropped, and every decision is traced (`PROMPT_IMPROVER_FAST_TRACE_DIR`).
  - Deterministic replay: every Jev answer is cached by a hash of its request, and the model is pinned (`jev-1.13.0`).
  - `ground` mode never serves a compiled spec; it only adds grounding and a model tier. The v1 names `compose` and `route` map to `auto` and `ground`.
  - Unreviewed cells are served only with `fast_path.allow_unreviewed`. Already-structured specs pass through unchanged. An explicit `model:` always wins.
  - Needs `TYPESAFE_API_KEY` or `OPENROUTER_API_KEY`, `curl` and `jq`. Any Jev failure falls back silently. Credentials are redacted before anything leaves the machine, and the API key is never on argv.
  - See `docs/investigations/jev-v2-architecture.md` (v1 results: `docs/investigations/jev-fast-path.md`). The benchmark harness is in `bench/jev/`.

## [1.1.0] — 2026-09-23

### Changed
- **Default generator models updated for September 2026.** `claude` → `opus`
  (the Claude Code alias for the newest Opus, Opus 5.5 today), `codex` →
  `gpt-6-sol`, `grok` → `grok-4.7`, `gemini` → `gemini-3.8-flash`.
- **New model ids and aliases:** `claude-opus-5-5` (`opus-5.5`),
  `claude-fable-5-1` (`fable-5.1`), `claude-mythos-5-1` (now what `mythos`
  means), `claude-haiku-4-5[-20251001]`, `claude-sonnet-4-6`, `claude-opus-4-7`,
  `gpt-6-sol`/`gpt-6-astra`/`gpt-6-luna` (`gpt-6`, `sol`, `astra`, `luna`),
  `grok-4.7`/`grok-4.6` (`grok`), `grok-build-0.1` (the target of the old
  composer / `grok-code-fast-1` ids), `gemini-3.8/3.7/3.6-flash`,
  flash-lite ids and `gemini-3.1-pro-preview` (`gemini-pro`, `gemini`).
  `codex`/`openai` now resolve to `gpt-6-sol`.
- **Fallback chains always try the requested model first.** Previously
  `claude-opus-4-8`, `grok-4.3`, `gemini-3.1-pro` and `gemini-3.5-flash` were
  silently swapped for another model before the requested one was tried.
- **Default `preferred_backends`** is now `claude, codex, grok, gemini, agy,
  copilot, cursor, opencode, cline, qwen, droid, amp, kiro`. `kimi` is left out
  because `kimi -p` auto-approves tool calls.
- The generator prompt no longer repeats the raw request outside the
  `<raw-request-to-improve>` DATA-ONLY wrapper, and the request can no longer
  close that wrapper early.
- `custom_command` output now goes through the same unwrap/strip/validate path
  as built-in backends (exit `4` on validation failure). It runs under
  `bash -c` with a timeout, stderr stays out of the prompt, and
  `PROMPT_IMPROVER_PROMPT_FILE` points at the prompt file.
- `fallback_strategy=error` now also turns "no headless generator" into exit
  `2` instead of `3`, as documented.

### Added
- **Backends:** `agy` (Antigravity CLI — Gemini for personal Google accounts,
  which Gemini CLI stopped serving on 2026-06-18), `copilot` (GitHub Copilot
  CLI), `cursor` (Cursor CLI, `cursor-agent` or `agent`), `qwen` (Qwen Code),
  `droid` (Factory) and `amp`. A `backend_binaries` table maps backends to
  executables whose names differ.
- **`--raw-input-file <path|->`** on `generate-prompt.sh` and
  `assemble-generation-prompt.sh`. The request is read from a file or stdin,
  so `$`, backticks and quotes are never shell-expanded and long requests
  avoid argv limits. `SKILL.md` now tells the host to use it with a quoted
  heredoc.
- **Per-attempt timeout for every backend:** `generation.backend_timeout_secs`
  (default 300, env `PROMPT_IMPROVER_BACKEND_TIMEOUT`, `0` = off). It uses
  `timeout`, then `gtimeout`, then a pure-bash watchdog, so stock macOS is
  covered too.
- `scripts/lib/backend-common.sh`: shared timeout, argv-size, stdin and
  exit-code handling for all backend scripts.
- **Limit detection** for current CLI wording: session and spend limits,
  "Credit balance is too low", `RESOURCE_EXHAUSTED` / daily quota, the Grok
  Build usage limit, "try again at", "not a recognized model id", and Codex's
  "not supported when using Codex with a ChatGPT account". Also `503`.
- **Smoke tests:** stub CLIs exercise every backend script, the model cascade,
  cross-backend fallback, limits on stdout and on stderr, timeouts, a 200 KB
  request, exits `2`/`3`/`4`, `custom_command`, malformed settings, and a run
  with no jq. There is also a jq-vs-bash parity check over every alias and
  chain.
- CI also runs on `macos-latest` under the stock `/bin/bash` 3.2.

### Fixed
- **About 1 in 3 generated specs failed the skill's own validator (exit 4).**
  The generator prompt told the model to put `<verification_commands>` in
  each task, but `validate-prompt.sh` only counted `<verification>`.
  Measured on 40 live opus runs: 15 failed validation before the fix, 1
  after. The one remaining failure is a genuine omission.
  - The generator prompt now names `<verification>` and states the output
    contract.
  - The validator checks verification per task instead of comparing totals,
    so two blocks in one task can no longer hide a missing one elsewhere.
  - It also accepts the `verification_commands`/`verify` variants.
  - It accepts measurable `<acceptance_criteria>` for audit or design tasks,
    with a warning.
  - It ignores tags quoted in backticks, such as a request that is about
    `<task>` itself.
  - It recognises plan-only / read-only `<check>` phrasing, such as "before
    presenting the plan" or "`git status --porcelain` is empty".
- **opencode, cline, kimi and kiro backends were broken.** They used flags
  those CLIs don't have (`opencode -p`, `cline --prompt --headless`,
  `kimi --headless`, `kiro -p`). They now use `opencode run`,
  `cline --plan -y`, `kimi -p` and `kiro-cli chat --no-interactive`, and they
  honour `model:` overrides.
- **The claude generator had full tool access.** It now runs with
  `--tools ""`, `--permission-mode dontAsk` and `--no-session-persistence`, so
  it can only write text.
- **`backend_invocation=commands` undid the codex read-only fix.** The codex
  template (and its bash fallback) now passes `--sandbox read-only`. The grok
  fallback template no longer uses `--yolo`.
- **Cross-backend fallback sent the wrong model.** After a limit on claude,
  grok was called as `grok -m claude-opus-5`, then `-m opus` and `-m sonnet`.
  Each fallback CLI now gets its own default model. An explicit model whose
  CLI is missing is no longer passed to the host CLI either.
- **Limit messages on stderr were ignored.** Most CLIs print 429/quota errors
  there, so failures were classed as hard errors and skipped the model
  cascade. Detection now reads stdout and stderr.
- **Large prompts failed with "Argument list too long".** Linux caps a single
  argument at 128 KiB whatever `ARG_MAX` is, but backends only switched to
  stdin above `ARG_MAX/2` (1 MiB). They now switch at 120 KB, via stdin or a
  prompt file where the CLI supports it.
- **SIGPIPE false results on large text.** `echo "$big" | grep -q` under
  `pipefail` made the validator report "no check block found", and made limit
  detection miss limits, whenever the match was near the top of a large body.
  All such checks now use here-strings.
- **`jq` `//` dropped `false`.** A user's `"enable_research": false` (or any
  boolean `false`) in settings fell through to the shipped `true`.
- A request that was literally `-n`/`-e` vanished (`echo` option parsing).
- A flag with no value (`--raw-input` last) crashed with "unbound variable".
  `--mode` and `--cwd` are now validated too.
- **Command injection:** a `model:` token was interpolated unquoted into
  eval'd templates. Model ids are now restricted to plain id characters, and
  `{model}` is shell-quoted.
- **Host detection:** `CODEX_HOME` (ordinary user config) no longer marks a
  Codex session. Env markers are checked in `supported_backends` order rather
  than jq's alphabetical key order. npm-installed CLIs (process name `node`)
  are recognised from their argv. Invalid marker names no longer abort.
- A malformed settings file is skipped with a warning instead of killing the
  run with jq's exit code. Unexpected internal failures (126/127/141/jq) map
  to exit `2`, keeping the 0–4 contract.
- Project settings are read from `--cwd`, not from the caller's current
  directory.
- `validate-prompt.sh`:
  - counts `<task>` tags rather than lines (`<tasks>` no longer counts as a
    task);
  - errors on a missing file instead of silently reading stdin;
  - uses only POSIX/BSD-compatible regex (no `\s`, `\b` or BRE `\|`).
- `gather-context.sh`:
  - bounds `pnpm ls` with a timeout;
  - survives a missing or stub `python3`;
  - no longer SIGPIPEs on large directories or diffs;
  - reads parent `CLAUDE.md`/`AGENTS.md` only from the git repo root.
- Empty arrays under `set -u` no longer break bash 3.2.
- Temp files are cleaned up on Ctrl-C and on every exit path.
- A dangling closing code fence after the XML is stripped.
- **codex backend produced garbage instead of a prompt.** `codex exec` streams
  its whole session log to stdout, and `codex.sh` piped all of it through as
  the improved prompt. It now takes the agent's final message from
  `--output-last-message`, closes stdin (which previously appended a duplicate
  `<stdin>` block), runs `--ephemeral`, and emits the log only on failure, so
  limit detection can still read it.
- **grok backend never ran.** The retired `grok-composer-2.5-fast` default was
  replaced. Narration before the first XML tag is dropped for every backend.

### Security
- Generators run read-only wherever the CLI allows it:
  - claude: tools disabled;
  - codex: `--sandbox read-only`;
  - cursor: `--mode ask`;
  - copilot: shell/write denied, no `--allow-all-tools`;
  - cline: `--plan`;
  - gemini/qwen: no auto-approval;
  - kiro: tools not pre-trusted.
- Model-id sanitising closes an injection path through `model:` tokens.

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
