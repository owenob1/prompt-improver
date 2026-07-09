# Supported generator models

Canonical reference for headless generation models used by `/prompt-improver`.

Implementation: `scripts/lib/settings.sh` (`normalize_model_id`, `infer_backend_for_model`, `get_model_fallback_chain`).  
**Keep this file in sync when adding aliases or cascades.**

---

## How models are chosen

1. Per-prompt `model:<id>` or `generate-prompt.sh --model <id>`
2. `PROMPT_IMPROVER_MODEL` or settings `"model"`
3. `default_models[backend]` in settings
4. Backend CLI default

**Unknown IDs pass through** (not rejected). Family prefixes still select the generator CLI when possible.

**Cross-host:** the *host* agent can be Claude while the *generator* is GPT (codex), and vice versa, if that CLI is on `PATH`.

---

## Defaults (shipped)

| Generator CLI | Default model ID | Notes |
|---------------|------------------|--------|
| `claude` | `sonnet` | Resolves to current Sonnet (Sonnet 5 / `claude-sonnet-5`) |
| `grok` | `grok-composer-2.5-fast` | Fast high-quality improver |
| `gemini` | `gemini-2.5-pro` | Pro-class specs |
| `codex` | `gpt-5.5` | GPT-5 family Codex default |

---

## Claude (`claude` CLI)

### Aliases → normalized ID

| You type (`model:…`) | Normalized ID | Access notes |
|----------------------|---------------|--------------|
| `mythos-5`, `mythos5`, `claude-mythos-5` | `claude-mythos-5` | Invite / Project Glasswing; not generally available |
| `mythos`, `mythos-preview`, `claude-mythos-preview` | `claude-mythos-preview` | Mythos Preview (restricted) |
| `fable-5`, `fable5`, `claude-fable-5` | `claude-fable-5` | Frontier widely released |
| `fable` | `fable` | Claude Code alias |
| `opus`, `opus-4.8`, `claude-opus-4-8` | `opus` / `claude-opus-4-8` | High capability |
| `opus-4.6`, `claude-opus-4-6` | `claude-opus-4-6` | Prior Opus |
| `sonnet`, `sonnet-5`, `claude-sonnet-5` | `sonnet` / `claude-sonnet-5` | Default improver for Claude |
| `haiku`, `haiku-4.5`, `claude-haiku-4-5` | `haiku` | Fast / cheap |

Any other `claude-*` ID is passed through unchanged and routed to the `claude` backend.

### Fallback cascade (access / rate limit / unavailable)

| Primary request | Try order |
|-----------------|-----------|
| Mythos family | `claude-mythos-5` → `claude-mythos-preview` → `claude-fable-5` → `fable` → `opus` → `sonnet` |
| Fable family | `claude-fable-5` → `fable` → `opus` → `sonnet` |
| Opus family | `opus` → `sonnet` |
| Sonnet family | requested ID → `sonnet` |
| Haiku family | requested ID → `haiku` → `sonnet` |

---

## OpenAI / Codex (`codex` CLI)

### Aliases → normalized ID

| You type (`model:…`) | Normalized ID | Notes |
|----------------------|---------------|--------|
| `gpt-5.6-sol`, `gpt5.6-sol`, `sol` | `gpt-5.6-sol` | GPT-5.6 flagship (preview / partners) |
| `gpt-5.6-terra`, `gpt5.6-terra`, `terra` | `gpt-5.6-terra` | GPT-5.6 balanced tier |
| `gpt-5.6-luna`, `gpt5.6-luna`, `luna` | `gpt-5.6-luna` | GPT-5.6 fast/affordable tier |
| `gpt-5.6`, `gpt5.6` | `gpt-5.6-sol` | Shorthand → Sol |
| `gpt-5.5`, `gpt5.5`, `gpt-5`, `gpt5` | `gpt-5.5` | Default Codex-class improver |
| `codex`, `openai` | `gpt-5.5` | Shorthand → default Codex improver + `codex` CLI |
| `gpt-5.3-codex`, `gpt5.3-codex` | `gpt-5.3-codex` | Codex-optimized |
| `gpt-5.2-codex`, `gpt5.2-codex` | `gpt-5.2-codex` | Prior Codex |
| `o4-mini`, `o4mini` | `o4-mini` | Smaller OpenAI model |

Any other `gpt-*`, `o1*`, `o3*`, `o4*`, `codex-*` ID is passed through and routed to `codex`.

### Fallback cascade

| Primary request | Try order |
|-----------------|-----------|
| Sol / `gpt-5.6` | `gpt-5.6-sol` → `gpt-5.6-terra` → `gpt-5.6-luna` → `gpt-5.5` |
| Terra | `gpt-5.6-terra` → `gpt-5.6-luna` → `gpt-5.5` |
| Luna | `gpt-5.6-luna` → `gpt-5.5` |
| gpt-5.5 | `gpt-5.5` |

---

## Grok / SpaceXAI (`grok` CLI)

### Aliases → normalized ID

| You type (`model:…`) | Normalized ID | Notes |
|----------------------|---------------|--------|
| `grok-4.5`, `grok4.5` | `grok-4.5` | Flagship coding/agent model (2026-07) |
| `grok-4.3`, `grok4.3` | `grok-4.3` | Prior public API model |
| `grok-composer-2.5-fast`, `composer-2.5-fast`, `composer-2.5` | `grok-composer-2.5-fast` | Default Grok improver |
| `grok-build`, `grokbuild`, `grok-build-0.1` | `grok-build` | Grok Build agent model |
| `grok-code-fast-1` | `grok-code-fast-1` | Early Grok Build coding model |

Any other `grok-*` / `composer-*` ID is passed through and routed to `grok`.

### Fallback cascade

| Primary request | Try order |
|-----------------|-----------|
| Grok 4.x | `grok-4.5` (or requested) → `grok-composer-2.5-fast` → `grok-build` |
| Composer family | requested → `grok-composer-2.5-fast` |

---

## Gemini (`gemini` CLI)

### Aliases → normalized ID

| You type (`model:…`) | Normalized ID |
|----------------------|---------------|
| `gemini-2.5-pro`, `gemini-pro` | `gemini-2.5-pro` |
| `gemini-2.5-flash`, `gemini-flash` | `gemini-2.5-flash` |
| `gemini-3.1-pro` | `gemini-3.1-pro` |
| `gemini-3.5-flash` | `gemini-3.5-flash` |

Any other `gemini-*` ID is passed through and routed to `gemini`.

### Fallback cascade

| Primary request | Try order |
|-----------------|-----------|
| Pro-class | `gemini-2.5-pro` → `gemini-2.5-flash` |
| Flash-class | requested flash ID |

---

## Other backends

| CLI | Default | Notes |
|-----|---------|--------|
| `opencode`, `cline`, `kimi`, `kiro` | *(none pinned)* | Use `model:` or settings if the CLI supports a model flag |

---

## Cross-CLI routing

| Model family | Generator CLI (if installed) |
|--------------|------------------------------|
| Claude / Mythos / Fable / Opus / Sonnet / Haiku | `claude` |
| Grok / Composer | `grok` |
| Gemini | `gemini` |
| GPT / Sol / Terra / Luna / o-series / Codex | `codex` |

If the preferred CLI is missing, auto-detect keeps the available backend and logs a warning.

---

## Retryable failure signals

Headless falls through the cascade when output/exit suggests:

- rate limit / quota / usage limit / 429  
- access denied / 403 / invitation / Glasswing / unavailable  
- unknown / invalid / unsupported model  
- capacity / overloaded / 529  

---

## Examples

```text
/prompt-improver "Fix the flaky auth tests"
/prompt-improver plan "Fix the flaky auth tests"
/prompt-improver model:fable-5 "Fix the flaky auth tests"
/prompt-improver model:mythos "Security-sensitive rewrite"
/prompt-improver model:gpt-5.6-sol plan "Large refactor"
/prompt-improver model:grok-4.5 "Design the migration"
```

```bash
bash skills/prompt-improver/scripts/generate-prompt.sh \
  --mode plan \
  --raw-input "Fix the flaky auth tests" \
  --model mythos
```

---

*Last updated: 2026-07-09 — align with `scripts/lib/settings.sh` when changing aliases or cascades.*
