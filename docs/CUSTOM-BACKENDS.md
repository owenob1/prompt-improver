# Custom generator backends

How headless generation picks a CLI, and how to plug in **any** tool that is not in the built-in list.

Config file (first match wins):

1. `.prompt-improver/settings.json` (project)
2. `~/.config/prompt-improver/settings.json` (user)
3. Shipped defaults under the skill `config/`

Copy the example (keys starting with `//` are human guidance only — the loader ignores them):

```bash
mkdir -p ~/.config/prompt-improver
cp skills/prompt-improver/config/settings.example.json \
  ~/.config/prompt-improver/settings.json
```

Env overrides (when set) win over the JSON keys of the same name:

| Env | Setting key |
|-----|-------------|
| `PROMPT_IMPROVER_BACKEND` | `backend` |
| `PROMPT_IMPROVER_MODEL` | `model` |
| `PROMPT_IMPROVER_CUSTOM_COMMAND` | `custom_command` |

---

## Built-in backends

These names work with `"backend": "…"` and as **host-matched** generators.  
**Default pick is not “first CLI on PATH.”** Auto mode uses the **host** agent (Claude session → `claude` + `opus`, Codex → `codex` + `gpt-6-sol`, Grok → `grok` + `grok-4.7`, …).  
`preferred_backends` is only the order to try **other** CLIs after the primary fails; each fallback CLI uses its own default model.

| Name | Typical CLI | Notes |
|------|-------------|--------|
| `claude` | `claude` | Default model: `opus`. Runs `claude -p` with `--tools ""` and `--permission-mode dontAsk` |
| `codex` | `codex` | Default model: `gpt-6-sol` (`openai` aliases to `codex`). `codex exec --sandbox read-only --ephemeral` |
| `grok` | `grok` | Default model: `grok-4.7`. Bounded by `grok_timeout_secs` (hang workaround) |
| `gemini` | `gemini` | Default model: `gemini-3.8-flash`. Paid API keys / Code Assist only since 2026-06-18 |
| `agy` | `agy` | Antigravity CLI — Gemini for personal Google accounts. CLI default model |
| `copilot` | `copilot` | GitHub Copilot CLI, `-p -s --no-ask-user`, shell/write denied |
| `cursor` | `cursor-agent` / `agent` | Cursor CLI, `-p --mode ask` (read-only) |
| `opencode` | `opencode` | `opencode run`, `-m provider/model` |
| `cline` | `cline` | `cline --plan -y`, `-m provider/model` |
| `qwen` | `qwen` | Qwen Code, `-p --approval-mode default` |
| `droid` | `droid` | Factory Droid, `droid exec -f <file>` (read-only autonomy) |
| `amp` | `amp` | `amp -x`, prompt on stdin; no model flag |
| `kimi` | `kimi` | `kimi -p` auto-approves tools, so it is not in the default fallback list |
| `kiro` | `kiro-cli` / `kiro` | `kiro-cli chat --no-interactive` (tools not pre-trusted) |

Every built-in backend is bounded by `generation.backend_timeout_secs` (default 300; env `PROMPT_IMPROVER_BACKEND_TIMEOUT`, `0` disables). Prompts too large for one argv string (~120 KB) go through stdin or a file where the CLI supports it; otherwise that backend is skipped.

Force one:

```json
{
  "backend": "opencode"
}
```

Prefer order when `"backend": "auto"`:

```json
{
  "backend": "auto",
  "preferred_backends": ["opencode", "claude", "grok", "codex"]
}
```

Per-backend default model IDs:

```json
{
  "default_models": {
    "opencode": "your-opencode-model-id",
    "claude": "sonnet"
  }
}
```

Model aliases, routing, and access cascades for Claude / Codex / Grok / Gemini:  
[models-supported.md](../skills/prompt-improver/references/models-supported.md).

---

## Custom mode (`custom_command`)

Use this when the generator is **not** in the built-in list (Kilo, a private wrapper, another agent CLI, a curl script, etc.).

When `custom_command` is set (settings or `PROMPT_IMPROVER_CUSTOM_COMMAND`), headless generation:

1. Assembles the improver prompt as usual  
2. **Skips** built-in backend detection, model flags, and fallback cascades  
3. Runs your command with the full prompt on **stdin**  
4. Treats **stdout** as the improved prompt; stderr is shown as diagnostics only  
5. Validates the output like any backend (exit `4` on failure). A non-zero exit or a limit message bounces to the host (exit `3`), or exits `2` with `fallback_strategy=error`  

The command runs under `bash -c`, bounded by `generation.backend_timeout_secs`. The prompt file path is also exported as `PROMPT_IMPROVER_PROMPT_FILE`.

### Minimal example

```json
{
  "custom_command": "my-cli --prompt-file \"$PROMPT_IMPROVER_PROMPT_FILE\""
}
```

### Read stdin directly

Many CLIs accept `-` or pipe input:

```json
{
  "custom_command": "kilo --headless --prompt -"
}
```

(Adjust flags to match your tool; the important contract is: **prompt in on stdin, improved text out on stdout**.)

### Env instead of JSON

```bash
export PROMPT_IMPROVER_CUSTOM_COMMAND='my-cli --from-stdin'
bash skills/prompt-improver/scripts/generate-prompt.sh \
  --mode plan \
  --raw-input "Fix the flaky auth tests"
```

### Wrapper script (recommended for complex CLIs)

```bash
#!/usr/bin/env bash
# ~/.config/prompt-improver/run-kilo.sh
set -euo pipefail
prompt=$(cat)
# translate to whatever your CLI needs
exec kilo run --system improver --input "$prompt"
```

```json
{
  "custom_command": "bash ~/.config/prompt-improver/run-kilo.sh"
}
```

---

## What custom mode does *not* do

| Built-in path | Custom path |
|---------------|-------------|
| `model:` / `--model` flags + aliases | Not applied — encode model in your command or wrapper |
| Access / rate-limit cascades | Not applied — implement retries yourself if needed |
| `default_models[backend]` | Ignored while `custom_command` is set |
| `scripts/backends/*.sh` | Bypassed |

Unset `custom_command` (or set it to `null`) to return to normal backend selection.

---

## Security

`custom_command` is passed to the shell (`eval`). Only use commands and scripts you trust. Review any shared project settings that set this key.

---

## Fully customisable settings

Beyond scalars (`backend`, `model`, `custom_command`, …), **runtime tables** ship in  
`skills/prompt-improver/config/runtime-defaults.json` and can be **overridden or extended** in your settings file.

| Table / key | Purpose |
|-------------|---------|
| `model_aliases` | Map short names → canonical IDs (`"myfast": "haiku"`) — **merged** with shipped map |
| `model_fallback_chains` | Pattern → ordered model cascade (`$primary` = requested id) — **replaces** table when set |
| `model_backend_patterns` | Pattern → generator CLI (`codex`, `claude`, …) |
| `default_models` | Per-backend default when `model` is null |
| `backend_commands` | CLI templates with `{prompt_file}` `{model}` `{model_args}` `{max_tokens}` (`{model}` is shell-quoted; templates run via `bash -c`) |
| `backend_model_flags` | How to pass model id per backend (`-m {model}`, …) |
| `backend_invocation` | `scripts` \| `commands` \| `auto` |
| `supported_backends` | Host-match allowlist |
| `preferred_backends` | Cascade order after primary fails (not default pick) |
| `limit_detection` | Regexes for account / retry / “looks like XML” |
| `host_env_markers` | Env vars that identify the host CLI |
| `parent_process_patterns` | Process-name globs for host detection |
| `cascade_scan_order` | Fallback scan when preferred list empty |
| `generation` | Prompt materials, output instructions, **deterministic context** (see below) |

### Generation materials & deterministic context (`generation`)

| Field | Default | Purpose |
|-------|---------|---------|
| `context_mode` | `deterministic` | Shell runs `gather-context.sh` before headless; injects fixed context. `off` skips gather. |
| `forbid_agent_codebase_search` | `true` | Generator must not grep/glob/find/search the repo |
| `include_xml_template` / `include_principles` / `include_chaining` / `include_examples` / `include_system_prompt` | `true` | Toggle which reference blocks are assembled |
| `*_path` fields | skill-relative paths | Point at your own system prompt, XML template, principles, chaining, examples |
| `extra_reference_paths` | `[]` | Extra files to append to the generator prompt |
| `output_instructions` | XML-only string | Final line the generator sees (customise output contract) |
| `require_xml_output` | `true` | Overlay flag for XML-only responses |

`gather-context.sh` is **deterministic shell only** (manifest probes, top-level listing, git metadata). It does not use AI search.

**Merge rules**

- Scalar keys: project → user → `settings.default.json` → `runtime-defaults.json`
- Object maps (`model_aliases`, `default_models`, …): deep-merge, **later layers win per key**
- Arrays of chain/pattern tables: **first non-empty** layer wins (set the whole table to replace)

**Example** — add an alias and shorten a cascade:

```json
{
  "model_aliases": {
    "cheap": "haiku",
    "codex": "gpt-6-luna"
  },
  "model_fallback_chains": [
    { "patterns": ["*sonnet*", "sonnet"], "chain": ["$primary", "haiku"] }
  ],
  "backend_commands": {
    "mycli": "mycli --prompt-file \"{prompt_file}\" --model {model} </dev/null"
  },
  "supported_backends": ["claude", "grok", "gemini", "codex", "mycli"],
  "default_models": {
    "mycli": "default"
  }
}
```

Env still wins for scalars (`PROMPT_IMPROVER_MODEL`, `PROMPT_IMPROVER_BACKEND`, `PROMPT_IMPROVER_CUSTOM_COMMAND`, …).

---

## Related

- [MODELS.md](./MODELS.md) — pointer to full model list  
- Settings keys in skill `config/settings.example.json`  
- Shipped tables: `config/runtime-defaults.json`  
- Implementation: `scripts/generate-prompt.sh`, `scripts/lib/settings.sh`
