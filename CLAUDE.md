# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A pure-Bash Agent Skill (no build step, no package manager, no compiled code). It takes a vague coding request and rewrites it into a structured XML spec by shelling out to a *separate* coding CLI (`claude`, `grok`, `codex`, `gemini`, …) headlessly, then hands the result back to the host agent to execute.

## Commands

```bash
bash tests/smoke-test.sh                          # full suite — this is what CI runs
bash skills/prompt-improver/scripts/smoke-test.sh # skill-package checks only (14 groups, faster)
```

There is no test-name filter. To iterate on one check, run the underlying script directly:

```bash
cd skills/prompt-improver
bash scripts/validate-prompt.sh examples/fixtures/valid-prompt.xml    # expect exit 0
bash scripts/validate-prompt.sh examples/fixtures/invalid-prompt.xml  # expect exit 1
bash scripts/assemble-generation-prompt.sh "some request"             # inspect assembled generator prompt
bash scripts/gather-context.sh .                                      # inspect deterministic context block
bash scripts/generate-prompt.sh --raw-input "..." --mode plan --skip-validate  # end-to-end, needs a CLI on PATH
```

Group `[1/8]` of the skill smoke test runs `bash -n` over every `scripts/**/*.sh`, so syntax errors are caught without a separate lint step. There is no typecheck, formatter, or linter.

## Architecture

```
Host agent session (Claude Code / Grok / …)
  └─ scripts/generate-prompt.sh          orchestrator
       ├─ lib/settings.sh                settings + model/backend resolution + limit detection
       ├─ gather-context.sh              deterministic repo facts (shell only, never AI search)
       ├─ assemble-generation-prompt.sh  references + context + raw request → one prompt file
       ├─ backends/<cli>.sh              headless invoke of the generator CLI
       └─ validate-prompt.sh             structural checks on the XML
  └─ host executes the XML (execute mode) or shows it (plan mode)
```

`generate-prompt.sh` exit codes are load-bearing — `SKILL.md` and any caller branch on them:

| Code | Meaning |
|------|---------|
| 0 | Improved XML on stdout |
| 1 | Bad usage |
| 2 | Hard generation failure |
| 3 | **Host bounce** — stdout begins `HOST_BOUNCE:NO_HEADLESS` or `HOST_BOUNCE:RATE_LIMITED`. The calling agent must finish the user's request in-session. Never treat this body as a prompt. |
| 4 | Generated, but `validate-prompt.sh` rejected it (body still printed) |

### Backend/model resolution

Deliberately **not** "first CLI on PATH". Order in `generate-prompt.sh`:

1. `--model` / per-prompt `model:<id>` → normalize → infer CLI from model family → use if that CLI is installed (cross-host is intentional: Claude host + `model:gpt-5.5` runs `codex`)
2. `settings.backend` when not `auto`
3. Host CLI, if it's a supported generator (detected via env markers, then walking up 8 parent PIDs)
4. Otherwise exit 3 / `NO_HEADLESS`

On failure the loop walks a **model cascade** on the current CLI; an *account-level* limit (vs. a retryable one) skips the rest of that CLI and moves to the next `preferred_backends` entry on PATH. `is_account_limit_failure` / `is_model_retryable_failure` / `is_rate_limit_message_only` in `lib/settings.sh` draw that line — note that limit messages sometimes arrive with **exit 0**, so output is sniffed even on success.

### Settings

Four merge layers, later wins: `config/runtime-defaults.json` → `config/settings.default.json` → `~/.config/prompt-improver/settings.json` → `.prompt-improver/settings.json`. Every key then has a `PROMPT_IMPROVER_*` env override applied last in `load_settings`. Keys beginning with `//` are comments.

`runtime-defaults.json` holds the runtime *tables* (`model_aliases`, `model_fallback_chains`, `model_backend_patterns`, `backend_commands`, `backend_model_flags`, `supported_backends`, `limit_detection`, `host_env_markers`, `parent_process_patterns`, `cascade_scan_order`, `generation`). All are user-overridable — that's the design, not an accident.

## Conventions and traps

**jq is optional.** Every table lookup in `lib/settings.sh` has a hardcoded Bash fallback for when `jq` is absent. Adding a model alias means editing *two* places: the `model_aliases` object in `runtime-defaults.json` **and** the `case` in `_builtin_normalize_model_id`. Same for fallback chains (`model_fallback_chains` + `get_model_fallback_chain`), backend inference (`model_backend_patterns` + `infer_backend_for_model`), defaults (`default_models` + `_PI_BUILTIN_DEFAULT_MODELS_*`), and the supported list. Smoke groups `[9]`–`[11]` cover these pairs.

**`lib/settings.sh` must never assign `SCRIPT_DIR`.** It's sourced by scripts that own that variable; it uses `_PI_*` names for its own paths. Smoke group `[2/8]` asserts this.

**jq's `//` treats `false` as missing.** `load_settings` uses explicit `if .key == null` checks when reading booleans out of the `generation` object. Don't "simplify" those back to `//`.

**Don't pipe large strings into an early-exiting `grep -q` under `set -o pipefail`.** SIGPIPE fails the script on Ubuntu CI. Use `[[ "$VAR" == *"needle"* ]]` — see the comment above smoke group `[3/8]`.

**The generator must never do the work.** The raw request is wrapped in `<raw-request-to-improve>` and labelled DATA ONLY. `generation.forbid_agent_codebase_search` (default true) forbids the generator from grepping or globbing; repo facts come only from `gather-context.sh`, which is strictly fixed-path probes plus git metadata — no recursive `find`, no glob search, no index. Smoke group `[14]` fails if an explorer creeps back in. This keeps context reproducible for a given tree.

**Layout is enforced.** Installable content lives only under `skills/prompt-improver/`. `plugins/prompt-improver/skills/prompt-improver` is a symlink back to it, and `tests/smoke-test.sh` group `[1]` checks that the symlink resolves to a real `SKILL.md`. Never duplicate skill files at the repo root.

Backends resolve two ways depending on `backend_invocation`: `scripts` (default) runs `scripts/backends/<name>.sh`; `commands` renders the `backend_commands` template; `auto` uses the template only when the user overrode it. A new backend generally needs an entry in `supported_backends`, `backend_commands`, `backend_model_flags`, `default_models`, and `parent_process_patterns` — plus the script if it has quirks (see `backends/grok.sh`, which bounds the CLI with `timeout` because grok 0.2.x hangs after printing its answer, and treats a non-empty stdout on exit 124/137/143 as success).

## Prompt-content changes

`SKILL.md` and the files under `references/` are the actual product — the generator model reads them verbatim. Changes there should respect `references/prompting-principles.md`: verification blocks over vague adjectives, `<approach>` and `<escape>` over forced workarounds, few-shot examples carrying `<reasoning>`. `validate-prompt.sh` enforces a subset of this mechanically (requires `<task>`, matching `<verification>` per task, a `<check>` block with file re-read; warns on vague adjectives, emphasis saturation above 20%, missing `<escape>`, UI tasks without visual verification).

Update `CHANGELOG.md` for user-facing changes.
