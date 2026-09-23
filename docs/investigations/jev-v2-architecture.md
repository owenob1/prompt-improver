# Jev v2: compile-time LLM, run-time Jev

*Branch `claude/jev-fast-path-investigation` · 2026-09-23 · status: design, backed by live probes against `jev-1.13.0`*

## Why v1 is not good enough

v1 made a single Jev call. That call classified the request, picked one of 9 static templates, and pasted the request into it. On live data:

- **Jev's own quality rubric** scored v1 specs as generic, while opus specs scored as specific and actionable:

  | Spec for the `--verbose` request | faithful | specific (0–2) | actionable (0–2) |
  |---|---|---|---|
  | v1 template output | 0.75 | **0.29** | **0.33** |
  | opus baseline | 0.83 | 2.00 | 0.98 |

- **It served few requests.** In the first 38 corpus runs, v1 composed only about a quarter of requests; the rest paid the full 30–40 s opus call.
- **It used Jev as a router.** v1 asked Jev ~10 questions, but Jev answers thousands of questions in one pass for roughly the same latency (see below).

## What the probes established

All numbers come from live calls through the session proxy on 2026-09-23. The raw scripts are in the session scratchpad; the method is described inline.

| Probe | Result | Design consequence |
|---|---|---|
| **Questions per call** | 10 q → 383 ms · 100 → 616 ms · 800 → 618 ms · 1,500 → 791 ms · **2,500 → 1,144 ms** (~54k input tokens, about $0.002) | One *wide* pass can make every decision a spec needs. Stage count, not question count, drives latency. |
| **Determinism** | 6 identical calls gave identical discrete choices; scores jittered by about ±0.05 | Quantise with margins wider than the jitter, then cache the decisions. Reruns become byte-identical. |
| **Retrieval** (card-in-question: each file's path and header in its own yes/no question; state = request only) | Top-1 correct on **7/7** single-target requests (including "the claude backend" → `backends/claude.sh`); ~57 tokens per file | Jev ranks repo files for scope, about 1,000 files per call, with parallel shards beyond that. "Rename everywhere" needs exact evidence (identifier search) instead. |
| **Extraction by choice** (every contiguous word span of the request as an option, ≤254) | Each role picked correctly on 5/5 requests: target, new element, desired behaviour, symptom, constraint, metric | Jev can't *write*, but it can *select any substring*. The request becomes a typed parse, and requirements and acceptance checks get request-specific wording. |
| **Decomposition** (ordinal span choice "piece of work N", deduplicated) | 3/3 multi-part requests split correctly and in order; 1/1 single-task request stopped at one. Jev's own "count" score was poorly calibrated, so we don't use it | Multi-task specs without an LLM. |
| **Curated bank selection** (one yes/no per expert-written item; 42 items) | The correct items were at the top for all 6 domain probes (auth, rate limiting, timezones, CSV, migrations, CLI). Some "attractor" items score 0.6–0.87 everywhere | **Select on lift over a per-item prior** measured on the corpus. With lift ≥ 0.25 and p ≥ 0.7, the selections were precise (e.g. `bump actions/checkout` → pin actions + check breaking changes; typo fix → nothing). |
| **Verification** (coverage of each extracted span + rubric) | A spec for a different request: faithful 0.09, coverage ≤ 0.15. A matching spec: coverage ≥ 0.95 | Jev is a cheap coverage and fidelity gate, and a fast proxy metric during development. |
| **Rubric vs a real judge** | A hand-compiled v2 mock scored 1.99/1.02 on Jev's rubric (equal to opus), but lost to opus 0/2 in a blind opus pairwise judgement. Opus + sonnet design notes ("Tier B") also lost 0/2 | **Jev's rubric is necessary but not sufficient.** Acceptance has to use pairwise judgement. The judge's written critique becomes the checklist for the pattern library (below). |
| **Where opus spec content comes from** (Jev classified all 1,806 content lines of 31 opus specs) | 33% reusable practice · 22% repo facts/conventions · 7% restating the request · 5% structure · 34% "design". Many of those "design" lines are actually CLAUDE.md knowledge | **About 70% or more of an opus spec can be compiled** from the request, the repo and a curated library. The rest is domain design reasoning. |
| **LLM floor** | The `claude -p` CLI costs about 3.3 s before any output. A sonnet design-notes micro-completion took 7.9 s | An LLM on the request path costs ≥ 3.3 s, and realistically 8 s or more. |
| **Validity of today's LLM path** | **12/31 opus specs fail `validate-prompt.sh`**, mostly from tag drift (`<verification_commands>`, `<acceptance_criteria>`) | A compiled spec is valid by construction. The validator and generator prompt also need fixing on `main` (tracked separately). |

### What the opus judge said v2 was missing

This critique of v2 against opus is effectively the quality checklist:
- **Companion work:** a regression-test task and a CHANGELOG entry, per CLAUDE.md.
- **Exact output formats and states,** such as `hit / miss / skipped (<reason>)`.
- **Examples with `<reasoning>`.**
- **Checks that run as written,** e.g. `diff <(cmd) <(cmd --verbose 2>/dev/null)`.
- **Negative checks.**
- **A current-behaviour statement.**
- **Callers that must not change.**
- **Project rules spelled out,** with a check for each.
- **An "inventory first" approach** with explicit decision criteria.
- **A specific escape.**
- **An explicit out-of-scope list.**

The one *defect* in the Tier B mock came from the LLM: sonnet's helper used `echo` on variable text, which CLAUDE.md forbids.

## The pivot

> **Move the LLM from the request path to the build path.**
> Opus authors a large, reviewed library of parameterised patterns *offline*, once. At request time, Jev does all the understanding, retrieval, selection, critique and verification in wide parallel passes. Every word of the output comes from the user's request, the repository, or the reviewed library. Nothing is generated at request time unless Jev decides a gap can only be filled that way.

## Architecture

```text
request ─┐
         ▼
L0  Candidates (shell, deterministic, cached by repo HEAD)                   ~50–150 ms
    • request: every word span ≤12 words (≤254) + regex entities (paths, flags, env vars, identifiers, quantities)
    • repo:    git ls-files → file cards (path + own header); caller/reference edges for extracted identifiers
    • rules:   CLAUDE.md / AGENTS.md / CONTRIBUTING / .cursorrules split into rule units
    • commands: CI run: steps, package.json scripts, Makefile targets, fenced shell in docs
    • library: reviewed pattern items (below), each with a corpus prior
         ▼
L1  UNDERSTAND + RETRIEVE + SELECT — one Jev call, ~300–1,000 questions          ~0.5–0.7 s
    triage · fine-grained intent · element kind · clarity/complexity/risk (paraphrase twins)
    roles by span choice (target, new element, desired, symptom, constraint, metric, ambiguity)
    decomposition by ordinal span choice · file relevance (card-in-question) · rule relevance
    command roles (test/lint/typecheck/build) · library relevance (lift over prior)
    companion needs (regression test, docs, changelog, migration note, compatibility)
         ▼
L2  COMPILE (shell) — typed spec AST → XML, one <task> per decomposed piece       ~50 ms
    patterns are parameterised by the parse: {target} {new_element} {desired} {runner} {test_cmd} …
         ▼
L3  CRITIQUE + VERIFY — one Jev call                                            ~0.4–0.5 s
    coverage of every role span and task span · faithful · specific · actionable
    the judge checklist as yes/no questions ("has a regression task?", "exact output format?", "negative check?" …)
    rule-violation scan of every line against the selected rules · per-requirement relevance in context
         ▼
L4  REPAIR — only for failed checklist items                                     0 or ~0.4 s
    select more library patterns for the missing dimension (Jev), recompile, re-verify
         ▼
L5  TIER DECISION
    A  compiled + verified → serve                                              ≈ 1.5–2.5 s total
    B  compiled + a gap only an LLM can fill → LLM writes ONLY that block,
       Jev re-checks it against rules/coverage                                  ≈ 6–9 s
    C  unclear / high-risk / novel → full LLM, with a Jev-shaped prompt
       (retrieved files, selected rules, selected patterns, parse) → shorter,
       grounded, cheaper tier possible                                          ≈ 15–30 s
         ▼
L6  CACHE + TRACE — decisions keyed by sha256(request, repo HEAD, library version, pinned model)
```

### The pattern library: the core asset

- **Schema.** Each item has:
  - `id`, `kind` (requirement | check | approach | example | escape | out-of-scope | companion-task | format-default)
  - `applies_to` (intent × element kind), `slots` (e.g. `{target}`, `{flag}`), `text`
  - `check` (a runnable verification template, when there is one)
  - `prior` (median relevance on the corpus, used for lift), `source`, `reviewed_by`
- **Authoring (offline, one-time, then incremental):**
  1. Opus writes candidate items per (intent × element kind) cell, e.g. "cli-flag × feature", "env-var × feature", "auth-session × bugfix", "migration × risky data".
  2. Items are also **distilled from real opus specs**: Jev labels lines as reusable practice, and a Jev choice question deduplicates them against existing items.
  3. A human reviews everything before it ships.
- **Calibration.** Priors and thresholds are fitted on the benchmark corpus, and expanded to more repos over time.
- **Target size.** 500–1,500 items is still well inside one call's capacity (≤2,500 questions).

### Determinism and robustness

- **Pinned model** (`jev-1.13.0`, not `-latest`) plus the decision cache: the same request on the same tree gives byte-identical output.
- **Margins:** decisions within ±0.1 of a threshold count as *uncertain*, and uncertain decisions route to the safer tier.
- **Paraphrase twins** on the gates (clarity, multi-task, risk): both phrasings must agree, otherwise abstain.
- **Nothing hallucinated:** the output text comes only from the request, the repo, or the reviewed library. Tier B/C LLM text is scanned against the selected rules before it's served.
- **Fail open:** every Jev failure drops to the next tier.

## Evaluation protocol

- **Acceptance** is blind pairwise judgement against the opus baseline, in both orderings. Wins and ties must be ≥ 90% on the requests served at each tier, and 100% of served specs must be valid.
- **Jev's rubric plus the judge checklist** is the fast inner-loop metric during library development: about 1 s per spec, near-zero cost.
- The corpus grows from 40 requests on one repo to at least 100 across several repos (Node, Python, Go, a web app), because a single-repo corpus overfits the library.

## Build plan

1. **L0 + L1 + L2 engine.** Candidate generation, the wide call, and a typed compiler that produces a spec AST and then XML. It replaces `jev-decide.sh` and `fast-compose.sh`.
2. **L3 + L4.** The checklist critic, coverage and rule-violation scan, and the repair loop.
3. **Library v0.** About 300 items for the commonest cells, authored offline by opus from the judge checklist plus distillation of the 40 baseline specs, then human-reviewed.
4. **Tiers B/C.** Gap-only LLM completion, and the Jev-shaped full-LLM prompt.
5. **Calibration + evaluation** on the expanded corpus. Iterate the library until Tier A clears the bar on its served share.
6. **Cache, trace and docs.** Keep it opt-in until the numbers hold.

## Decisions needed

1. **A deterministic repo index in the fast path.** This means `git ls-files` file cards, plus exact-identifier `git grep -l -F` for references and callers. CLAUDE.md currently limits context to fixed-path probes. The index is reproducible for a given tree, but it widens that rule. *Recommendation: allow it, fast path only, cached by HEAD.*
2. **Offline opus authoring of the pattern library.** This is a one-time spend of tokens, with human review before items ship. *Recommendation: yes. This is where the quality comes from.*
