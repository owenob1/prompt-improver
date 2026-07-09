# Custom generator backends

How headless generation picks a CLI, and how to plug in **any** tool that is not in the built-in list.

Config file (first match wins):

1. `.prompt-improver/settings.json` (project)
2. `~/.config/prompt-improver/settings.json` (user)
3. Shipped defaults under the skill `config/`

Copy the example:

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

These names work with `"backend": "…"` and `preferred_backends`. Auto mode picks the first binary found on `PATH` in that order.

| Name | Typical CLI | Notes |
|------|-------------|--------|
| `claude` | `claude` | Default model: `sonnet` |
| `grok` | `grok` | Default model: `grok-composer-2.5-fast` |
| `gemini` | `gemini` | Default model: `gemini-2.5-pro` |
| `codex` | `codex` | Default model: `gpt-5.5` (`openai` aliases to `codex`) |
| `cline` | `cline` | Headless flags as wired in `settings.sh` |
| `opencode` | `opencode` | Built-in command template |
| `kimi` | `kimi` | Built-in command template |
| `kiro` | `kiro` | Built-in command template |

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
4. Treats **stdout** as the improved prompt (XML / text)  
5. Exits non-zero if your command exits non-zero  

### Minimal example

```json
{
  "custom_command": "cat >/tmp/pi-in.txt && my-cli --prompt-file /tmp/pi-in.txt"
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

## Related

- [MODELS.md](./MODELS.md) — pointer to full model list  
- Settings keys in skill `config/settings.example.json`  
- Implementation: `scripts/generate-prompt.sh` (custom branch), `scripts/lib/settings.sh`
