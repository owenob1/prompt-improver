# Contributor notes (not a skill)

This repository packages **prompt-improver** as an [Agent Skill](https://agentskills.io/).

- Canonical skill lives in `skills/prompt-improver/`.
- Do not put installable skill content at the repo root.
- Claude marketplace entry: `.claude-plugin/marketplace.json` → `plugins/prompt-improver/`.
- The plugin skill path is a symlink to the canonical skill folder.
- Offline checks: `bash tests/smoke-test.sh`.
- Prefer short root README; deep prompting material stays in `skills/prompt-improver/references/`.
