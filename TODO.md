# prompt-improver TODO

This document tracks work needed to prepare `prompt-improver` for public release and make it robust across many coding CLIs.

## Release Goals

- [ ] Prepare prompt-improver for public release
- [ ] Implement all identified improvements
- [ ] Create a beautifully designed and structured README.md
- [ ] Define and document a clear, followed contribution workflow
- [ ] Ensure the project is easy for others to use, extend, and contribute to

## Broad CLI Compatibility (Core Requirement)

The skill must work with (and default to) the user's chosen coding CLI for the generation step.

Supported / Target CLIs:
- Claude Code
- Grok Build
- Gemini CLI
- Codex
- OpenCode
- Kimi (Kimi Code CLI)
- Kiro
- Cline
- Others as they emerge

### Requirements
- [ ] By default, automatically use the host CLI's headless mode for prompt improvement (e.g. inside Claude Code → use `claude` headless; inside Grok Build → use `grok` headless)
- [ ] Support CLIs with strong headless capability
- [ ] Provide graceful support / fallbacks for CLIs with weak or no headless support
- [ ] Work via a simple `/prompt-improver` (or equivalent) call with no special preambles required

## Configuration & Overrides

- [ ] Implement a proper `settings.json` system (user + project + default layers)
- [ ] Support overriding the inference provider/backend for prompt improvement
- [ ] Allow selection of different models or providers regardless of host CLI
- [ ] Support environment variable overrides (highest priority)
- [ ] Make the system extensible for future settings

## Settings & Features

- [ ] `backend`: auto | grok | claude | gemini | openai | custom | etc.
- [ ] `model`: override specific model
- [ ] `max_tokens`: token limit on the generated (improved) prompt
- [ ] `enable_research`: research on/off
- [ ] `enable_thinking`: thinking / reasoning on/off
- [ ] `fallback_strategy`: manual | error | use_another_backend
- [ ] `preferred_backends`: ordered list for auto detection
- [ ] `custom_command`: full override for advanced users
- [ ] Additional useful settings as they are identified

## Robustness & Edge Cases

- [ ] Handle the case where a CLI tool removes or never provides headless mode
- [ ] Strategy for keeping model availability information reasonably up-to-date
- [ ] Proper token limitation support on generated output
- [ ] Clear error messages and graceful degradation

## Prevention of Premature Execution (Critical)

This is a major usability issue.

- [ ] Investigate how Grok Build (and other strong decomposition/parallel agents) can start executing parts of the raw input before it has been improved
- [ ] Design and implement a **global solution** that prevents the host CLI from breaking down or acting on the raw prompt
- [ ] The solution must work regardless of which CLI is being used
- [ ] Goal: users can call `prompt-improver <prompt>` cleanly with **no preambles, guardrails, or "DO NOT EXECUTE" instructions** required in the raw input
- [ ] Ensure the generation step happens first, then the improved prompt is executed/reviewed

## Modes & Output Formats

- [ ] Mark Task mode as deprecated in all documentation and code
- [ ] Decide what (if any) replacement flag or output format for structured task trees is worth keeping
- [ ] Ensure any retained capability remains portable across CLIs

## Technical Architecture

- [ ] Create a clean, extensible backend/adapter system (`scripts/backends/`)
- [ ] Implement reliable CLI/host detection for "auto" mode
- [ ] Build a main entrypoint (`scripts/generate-prompt.sh` or equivalent) that respects settings
- [ ] Support both explicit backend scripts and generic command templates
- [ ] Proper validation of generated prompts after delegation
- [ ] Assembly of generator materials in a reusable way

## Extensibility & Future Directions

- [ ] Consider MCP tool integration (both local and cloud-based solutions)
- [ ] Explore the idea of a standalone application (in addition to skill/plugin form)
- [ ] Design for easy addition of new CLIs and providers
- [ ] Investigate whether a small core "prompt-improver" CLI wrapper would help portability

## Documentation & Release

- [ ] Beautiful, scannable README.md with:
  - Clear value proposition
  - Quickstarts for all major CLIs (headless + non-headless)
  - Configuration guide
  - Robustness / limitations section
- [ ] High-quality CONTRIBUTING.md
- [ ] GitHub issue and PR templates
- [ ] Update SKILL.md to reflect current architecture and deprecations
- [ ] Versioning and changelog process
- [ ] Licensing and attribution

## Other / Backlog

- [ ] Decide on distribution method (standalone repo, skill marketplace, etc.)
- [ ] Consider performance / token cost of the generation step
- [ ] Evaluate whether the generator itself should be improved using prompt-improver recursively
- [ ] Add more high-quality before/after examples
- [ ] Test thoroughly across real-world CLIs (headless behavior, auth, output formats)

---

**Prioritization Guidance**

- **P0 (Must have for release)**: Core CLI compatibility, settings system, premature execution prevention, beautiful README, contribution workflow.
- **P1 (Strongly desired)**: Robust fallbacks, good documentation of limitations, MCP consideration.
- **P2 (Nice to have / future)**: Standalone app, advanced settings, model registry.

Last updated: 2026-07-08

To update this file, edit it directly or open an issue referencing specific items.