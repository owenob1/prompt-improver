# Supported generator models

Canonical reference for headless generation models used by `/prompt-improver`.

Implementation: `scripts/lib/settings.sh` + shipped tables in `config/runtime-defaults.json`
(`normalize_model_id`, `infer_backend_for_model`, `get_model_fallback_chain`).

**Customise without code:** override `model_aliases`, `model_fallback_chains`, `model_backend_patterns`,
`default_models`, etc. in `~/.config/prompt-improver/settings.json` (see `docs/CUSTOM-BACKENDS.md`).
**Keep this file in sync when changing shipped defaults.**

---

## How models are chosen

1. Per-prompt `model:<id>` or `generate-prompt.sh --model <id>`
2. `PROMPT_IMPROVER_MODEL` or settings `"model"`
3. `default_models[backend]` in settings
4. Backend CLI default (`null` in `default_models`)

**Unknown IDs pass through** (not rejected), as long as they only contain letters, digits and
`. _ - : / @ + [ ]`. Family prefixes still select the generator CLI when possible.

**Cross-host:** the *host* agent can be Claude while the *generator* is GPT (codex), and vice versa, if that CLI is on `PATH`.

**Fallback CLIs get their own models.** When the primary CLI is exhausted and another backend is
tried, that backend uses its own `default_models` entry — a Claude model id is never sent to grok.

---

## Defaults (shipped)

| Generator CLI | Default model ID | Notes |
|---------------|------------------|--------|
| `claude` | `opus` | Claude Code alias for the newest Opus (Opus 5.5 today) |
| `codex` | `gpt-6-sol` | GPT-6 Sol |
| `grok` | `grok-4.7` | Grok 4.7 |
| `gemini` | `gemini-3.8-flash` | Newest stable Gemini model |
| `agy`, `copilot`, `cursor`, `opencode`, `cline`, `qwen`, `droid`, `amp`, `kimi`, `kiro` | *(CLI default)* | Multi-provider CLIs use their own model ids — set `default_models.<cli>` to pin one |

Want a cheaper improver? `model:sonnet` per prompt, or `"default_models": {"claude": "sonnet"}`.

---

## Claude (`claude` CLI)

### Aliases → normalized ID

| You type (`model:…`) | Normalized ID | Access notes |
|----------------------|---------------|--------------|
| `fable` | `fable` | Claude Code alias → Fable 5.1 (needs Claude Code ≥ 2.1.257) |
| `fable-5.1`, `fable5.1`, `claude-fable-5-1` | `claude-fable-5-1` | Frontier model |
| `fable-5`, `fable5`, `claude-fable-5` | `claude-fable-5` | Legacy, still active |
| `opus` | `opus` | Claude Code alias → Opus 5.5 (the shipped default) |
| `opus-5.5`, `opus5.5`, `claude-opus-5-5` | `claude-opus-5-5` | Pinned Opus 5.5 |
| `opus-5`, `opus5`, `claude-opus-5` | `claude-opus-5` | Legacy, still active |
| `opus-4.8`, `opus-4.7`, `opus-4.6` (and `claude-opus-4-*`) | `claude-opus-4-8` / `-4-7` / `-4-6` | Legacy |
| `sonnet` | `sonnet` | Claude Code alias → Sonnet 5 (Anthropic API; differs on Bedrock/Vertex/Foundry) |
| `sonnet-5`, `sonnet5`, `claude-sonnet-5` | `claude-sonnet-5` | Cheaper improver |
| `sonnet-4.6`, `claude-sonnet-4-6` | `claude-sonnet-4-6` | Legacy |
| `haiku` | `haiku` | Claude Code alias → Haiku 4.5 |
| `haiku-4.5`, `haiku4.5`, `claude-haiku-4-5` | `claude-haiku-4-5` | Fast / cheap |
| `claude-haiku-4-5-20251001` | `claude-haiku-4-5-20251001` | Dated snapshot |
| `mythos`, `mythos-5.1`, `claude-mythos-5-1` | `claude-mythos-5-1` | Invitation-only (Project Glasswing) |
| `mythos-5`, `claude-mythos-5` | `claude-mythos-5` | Invitation-only |
| `mythos-preview`, `claude-mythos-preview` | `claude-mythos-preview` | **Deprecated** since 2026-06-09 |

Any other `claude-*` ID is passed through unchanged and routed to the `claude` backend.

### Fallback cascade (access / rate limit / unavailable)

Every chain starts with the model you asked for.

| Primary request | Try order |
|-----------------|-----------|
| Mythos family | requested → `claude-mythos-5-1` → `claude-mythos-5` → `fable` → `opus` → `sonnet` |
| Fable family | requested → `fable` → `opus` → `sonnet` |
| Opus family (any version) | requested → `opus` → `sonnet` |
| Sonnet family | requested → `sonnet` |
| Haiku family | requested → `haiku` → `sonnet` |

---

## OpenAI / Codex (`codex` CLI)

### Aliases → normalized ID

| You type (`model:…`) | Normalized ID | Notes |
|----------------------|---------------|--------|
| `gpt-6-sol`, `gpt6-sol`, `sol`, `gpt-6`, `gpt6` | `gpt-6-sol` | Default Codex improver |
| `gpt-6-astra`, `gpt6-astra`, `astra` | `gpt-6-astra` | GPT-6 Astra |
| `gpt-6-luna`, `gpt6-luna`, `luna` | `gpt-6-luna` | GPT-6 Luna |
| `codex`, `openai` | `gpt-6-sol` | Shorthand → default Codex improver + `codex` CLI |
| `gpt-5.6-sol`, `gpt-5.6`, `gpt5.6` | `gpt-5.6-sol` | Previous generation |
| `gpt-5.6-terra`, `terra` | `gpt-5.6-terra` | Previous generation |
| `gpt-5.6-luna` | `gpt-5.6-luna` | Previous generation |
| `gpt-5.5`, `gpt5.5`, `gpt-5`, `gpt5` | `gpt-5.5` | **Retires from Codex 2026-10-14** |
| `gpt-5.3-codex`, `gpt-5.2-codex` | same | Deprecated for ChatGPT sign-in |
| `o4-mini`, `o4mini` | `o4-mini` | Smaller OpenAI model |

GPT-6 rejects the `minimal` reasoning level. Any other `gpt-*`, `o1*`, `o3*`, `o4*`, `codex-*` ID is passed through and routed to `codex`.

### Fallback cascade

| Primary request | Try order |
|-----------------|-----------|
| GPT-6 family | requested → `gpt-6-sol` → `gpt-6-luna` → `gpt-5.6-terra` → `gpt-5.5` |
| GPT-5.6 family | requested → `gpt-6-sol` → `gpt-5.6-terra` → `gpt-5.6-luna` → `gpt-5.5` |
| Older GPT-5 / `*-codex` / o-series | requested → `gpt-6-sol` → `gpt-6-luna` |

---

## Grok / xAI (`grok` CLI)

### Aliases → normalized ID

| You type (`model:…`) | Normalized ID | Notes |
|----------------------|---------------|--------|
| `grok-4.7`, `grok4.7`, `grok` | `grok-4.7` | Flagship (2026-09) |
| `grok-4.6`, `grok4.6` | `grok-4.6` | |
| `grok-4.5`, `grok4.5` | `grok-4.5` | |
| `grok-4.3`, `grok4.3` | `grok-4.3` | |
| `grok-build`, `grok-build-0.1`, `grok-code-fast-1`, `composer-*`, `grok-composer-*` | `grok-build-0.1` | Retired composer/code-fast ids map to the Grok Build model |

Any other `grok-*` / `composer-*` ID is passed through and routed to `grok`.

### Fallback cascade

| Primary request | Try order |
|-----------------|-----------|
| Grok 4.x | requested → `grok-4.7` → `grok-4.6` → `grok-4.5` |
| Other grok ids | requested → `grok-4.7` |

---

## Gemini (`gemini` CLI) and Antigravity (`agy` CLI)

Since **2026-06-18** Gemini CLI only serves paid Gemini API keys, Enterprise Agent Platform keys and
Code Assist Standard/Enterprise. Personal Google accounts should use the **`agy`** backend
(Antigravity CLI; `agy models` lists its ids). `model:gemini-*` still routes to `gemini`; set
`"backend": "agy"` (and optionally `default_models.agy`) to use Antigravity.

### Aliases → normalized ID

| You type (`model:…`) | Normalized ID |
|----------------------|---------------|
| `gemini`, `gemini-flash`, `gemini-3.8-flash` | `gemini-3.8-flash` |
| `gemini-3.7-flash`, `gemini-3.6-flash`, `gemini-3.5-flash` | same |
| `gemini-3.5-flash-lite`, `gemini-3.1-flash-lite` | same |
| `gemini-pro`, `gemini-3.1-pro`, `gemini-3.1-pro-preview` | `gemini-3.1-pro-preview` (preview) |
| `gemini-2.5-pro`, `gemini-2.5-flash` | same (access-limited to existing users) |

Any other `gemini-*` ID is passed through and routed to `gemini`.

### Fallback cascade

| Primary request | Try order |
|-----------------|-----------|
| Pro-class | requested → `gemini-3.1-pro-preview` → `gemini-3.8-flash` → `gemini-2.5-pro` |
| Flash-class | requested → `gemini-3.8-flash` → `gemini-3.7-flash` → `gemini-2.5-flash` |
| Other gemini ids | requested → `gemini-3.8-flash` |

---

## Other backends

| Backend | Executable | Headless call | Model ids |
|---------|-----------|---------------|-----------|
| `agy` | `agy` | `agy -p` | `agy models` |
| `copilot` | `copilot` | `copilot -p -s --no-ask-user` (shell/write denied) | e.g. `claude-sonnet-5`, `gpt-6-sol` |
| `cursor` | `cursor-agent` or `agent` | `-p --mode ask` (read-only) | `agent models` |
| `opencode` | `opencode` | `opencode run` | `provider/model` |
| `cline` | `cline` | `cline --plan -y` | `provider/model` |
| `qwen` | `qwen` | `qwen -p --approval-mode default` | Qwen Code ids |
| `droid` | `droid` | `droid exec -f <file>` (read-only autonomy) | Factory ids |
| `amp` | `amp` | `amp -x` (prompt on stdin) | none — Amp picks its own model |
| `kimi` | `kimi` | `kimi -p` (auto-approves tools; not in the default fallback list) | Kimi aliases |
| `kiro` | `kiro-cli` or `kiro` | `kiro-cli chat --no-interactive` | Kiro ids |

For these CLIs a requested model is tried first, then the CLI's own default.

---

## Cross-CLI routing

| Model family | Generator CLI (if installed) |
|--------------|------------------------------|
| Claude / Mythos / Fable / Opus / Sonnet / Haiku | `claude` |
| Grok / Composer | `grok` |
| Gemini | `gemini` |
| GPT / Sol / Astra / Luna / Terra / o-series / Codex | `codex` |

If the preferred CLI is missing, auto-detect keeps the available backend (with its own default model) and logs a warning.

---

## Retryable failure signals

Headless falls through the cascade when stdout **or stderr** suggests:

- rate limit / quota / usage, session, weekly or spend limit / `429` / `RESOURCE_EXHAUSTED`
- access denied / `403` / invitation / Glasswing / "not available with the … plan"
- unknown / invalid / unrecognized model, "model … not found"
- capacity / overloaded / `503` / `529` / "temporarily limiting requests"

Account-level limits (weekly/session/spend limit, credit balance too low, daily quota exhausted,
Grok Build usage limit) skip the rest of that CLI and move to the next backend.

---

## Examples

```text
/prompt-improver "Fix the flaky auth tests"
/prompt-improver plan "Fix the flaky auth tests"
/prompt-improver model:fable "Fix the flaky auth tests"
/prompt-improver model:sonnet "Cheaper spec for a small change"
/prompt-improver model:gpt-6-sol plan "Large refactor"
/prompt-improver model:grok-4.7 "Design the migration"
```

```bash
bash skills/prompt-improver/scripts/generate-prompt.sh --mode plan --model fable --raw-input-file - <<'REQ'
Fix the flaky auth tests
REQ
```

---

*Last updated: 2026-09-23 — align with `config/runtime-defaults.json` and the bash fallbacks in `scripts/lib/settings.sh` when changing aliases or cascades.*
