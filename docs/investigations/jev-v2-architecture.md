# Jev v2: compile-time LLM, run-time Jev

*Branch `claude/jev-fast-path-investigation` · 2026-09-23 · status: v2 built and benchmarked; it does not reach opus quality (see §10)*
*Every number below comes from live calls to `jev-1.13.0` and the real `claude` CLI. The probes are reproducible from [`bench/jev/probes/`](../../bench/jev/probes).*

## 1. Verdict on v1

v1 made one Jev call that classified the request and picked one of 9 static templates.

| Benchmark: 40 requests, this repo | v1 `auto` | opus baseline (`off`) |
|---|---|---|
| p50 latency | 31.2 s (1.7 s on the 30% served fast) | 34.3 s |
| Served without an LLM | 12 / 40 | 0 |
| Valid per `validate-prompt.sh` | 28 / 40 (all 12 fast-served are valid) | **25 / 40** |
| **Blind pairwise, fast-served vs opus** | **0 win / 0 tie / 12 loss** | — |

Jev's own rubric agrees: the v1 spec for the `--verbose` request scored *specific 0.29 / actionable 0.33* against opus's 2.0 / 0.98. **v1 is not fit for purpose.**

## 2. What Jev can do (probed live)

| Capability | Evidence | Source |
|---|---|---|
| **Wide calls** | 10 q → 383 ms · 800 → 618 ms · 2,500 → 1,144 ms (54k input tokens, ~$0.002). A real 141-question L1 call runs in 519–808 ms | `scale.sh` |
| **Near-determinism** | Discrete choices were identical across 6 runs; scores jitter by about ±0.05. The docs confirm it is *not* bit-deterministic: a top label flipped on 2 of 8 questions over 15 runs, and a policy of "top p < 0.60 → uncertain" restores 99.2% agreement | `determinism.sh`; docs cookbooks |
| **Retrieval (card in question)** | Top-1 correct on 7/7 single-target requests at ~57 tokens per file. This is TypeSafe's documented "candidate in instructions" pattern. Packing rows into *state* degrades (a position effect of about 0.42 on late rows) | `retrieval.sh`; docs §6 |
| **Extraction by choice** | Every role was correct on 5/5 requests: target, new element, desired behaviour, symptom, constraint, metric. The docs' official pattern for this is "turn extraction into a Choice over the options". Very wide choices lose resolution (95.8% of options in a 200-option choice return 0.00), so over-find with regexes and clauses, then choose | `extract.sh`; docs |
| **Decomposition** | Ordinal span choices split 3/3 multi-part requests correctly. Jev's own "count" score was poorly calibrated, so it isn't used | probe |
| **Selecting from a curated bank** | The correct expert items came top in every domain probed. "Attractor" items are handled with lift over a per-item corpus prior | `bank.sh` |
| **Rule selection** | Sentence-level CLAUDE.md units with the phrasing "would an engineer need to follow this rule while changing the code?" selected the same rules opus used. Paragraph units and other phrasings did worse | `slots.sh` |
| **Item guards** (premised on the request) | They caught every failure the judge found in an out-of-sample spec (table in §4). A generic "is this section wrong?" battery did **not** discriminate | `guards.sh` |
| **Confidence** | `confidence = (K·p_max − 1)/(K − 1)`, so it depends on option count. Use p_max, margins and bands, not raw confidence | docs §4 |
| **LLM floor for comparison** | `claude -p` costs about 3.3 s before any output. An 8-line sonnet section took 7.9 s. Opus specs took 30–46 s | probe |

## 3. The decisive experiments

| Experiment | Result |
|---|---|
| **A. Compiled spec on the request its library cell was written from** (`--verbose` → `gather-context.sh`) | **Tie with opus.** The judge chose whichever spec was shown first in all 4 runs, 2 in each order. Compile time is under 1 s; opus took 35 s |
| **B. The same cell on an unseen request** (`--trace` → `generate-prompt.sh`) | **Opus won 4/4.** v2 compiled in **0.73 s**; opus took **39.5 s** and its spec failed validation. The judge said v2 mis-fit the request: `hit/miss` results for backend attempts, "every backends site", verification that runs the tool without its required `--raw-input`, positional-argument wording for a flag-only tool, and caller lists in the wrong direction. It also missed code-specific content: the cascade, limit classes and exit codes 0–4 |
| **C. Would a generic verifier catch B?** | **No.** Five broad yes/no questions per section fired about equally on the good and bad specs |
| **D. Would item guards catch B?** | **Yes.** See §4 |

The conclusion:
- **Compilation can reach opus parity**, and it takes about a second instead of 35 s.
- **But only when the selected library items actually fit the request.** Fit has to be proven item by item, by narrow guards written with each item.
- **Requests that hinge on a specific module's internals need an LLM for exactly those parts.** For B, that meant the backend cascade and limit handling in `generate-prompt.sh`.

## 4. Item guards: the robustness mechanism

Every library item carries 1–3 narrow guard questions, written by the item's author. They are asked about the *request* (plus facts such as the target's usage text), never about the draft.

| Guard | `--verbose` (fits) | `--trace` (does not fit) | Action when it fails |
|---|---|---|---|
| Reports on fixed checks/steps in the code? | 0.74 | **0.25** | Drop the "each … site" items |
| Tool takes positional arguments? | 0.97 | **0.12** | Drop "accepted before or after positional arguments" |
| Tool runs with no arguments? | 0.77 | **0.22** | Swap to a verification item that supplies the required arguments |
| Reports a sequence of attempts that succeed or fail? | 0.49 | **0.61** | Use success/limit/error result vocabulary instead of hit/miss |
| Each reported thing is a lookup that can come up empty? | 0.74 | 0.62 | Weak on its own; combined with the attempts guard |

Guards make Tier A deterministic and auditable. Every compiled line has passed a logged precondition. When a *required* section has no item whose guards pass, that section is a **gap**, and only the gap goes to an LLM.

## 5. Where opus's quality comes from

Jev classified all 1,806 content lines of 31 opus specs:

| Source | Share | How v2 covers it |
|---|---|---|
| Reusable practice | 33% | Library items (with guards) |
| Repo facts and conventions | 22% | Sentence-level rule selection, file cards, command discovery, and reference lines with direction |
| Request restatement | 7% | Extraction by choice |
| Structure | 5% | Compiler |
| "Design" | 34% | Partly library "house defaults" (formats, states, examples). Many of these lines are really CLAUDE.md knowledge. The code-specific part goes to Tier B |

## 6. Architecture

```text
L0  Candidates (shell, deterministic, cached by repo HEAD)                            ≤150 ms
    request: regex entities (paths, flags, env vars, identifiers, quantities) + clause/NP chunks
             (over-find, then choose; no 200-wide span choices)
    repo:    git ls-files → file cards; git grep -n -F for extracted identifiers (lines, with direction)
    rules:   CLAUDE.md / AGENTS.md / CONTRIBUTING → sentence units
    usage:   target's own usage/help text, read from the file (not executed)
    commands: CI run: steps, package scripts, Makefile targets, fenced shell in docs
    library: typed items {kind, cell, slots, text, check, guards[], prior}, arranged as a taxonomy

L1  ONE wide Jev call (premised fan-out, every question independent of every other) ~0.6–0.9 s
    triage · intent/element taxonomy (top levels) · clarity/complexity/risk (+ paraphrase twins)
    roles by choice over candidates + an "exists?" noul per role · ordinal decomposition
    file relevance (card in question) · rule relevance · command roles · reference direction
    library item relevance (lift) · ALL guards of candidate items (premised on the request + usage)
    companion needs (regression test, docs, changelog, migration note, compatibility)

L1b Parallel second calls only where the first answer changes the options          ~0.4 s
    taxonomy beam (K=3) below the top levels · semantic-find over the target file's lines
    (choice over line IDs + exists) → code anchors for the spec

L2  COMPILE (shell): typed AST → XML; include only items whose guards pass (margin ±0.1)   ~50 ms
    slots filled only from verbatim candidates; every line keeps a trace back to its item and guard

L3  COVERAGE (Jev, narrow + grounded): each extracted role and each task span must be covered;
    required sections present (current behaviour, verification per task, check, escape)   ~0.4 s

L4  TIER
    A  no gaps, all guards/coverage pass → serve                                       ≈1.5–2.5 s
    B  gaps only → a fast LLM writes ONLY the gap sections (in parallel, capped length), given
       the request + compiled context + code anchors; Jev re-checks those sections with the
       gap-type guards; opus only if they still fail                                    ≈6–10 s
    C  unclear / high-risk / no fitting cell → full LLM with a Jev-shaped prompt (retrieved
       files, anchors, selected rules and items); still Jev-verified                   ≈15–30 s

L5  Cache raw answers (re-threshold without calls) + trace; pin jev-1.13.0; fail open.
```

**Offline, the "compile-time LLM":**
- Opus authors library cells per taxonomy node, *with guards and checks*.
- Items are also distilled from real opus specs.
- An autoresearch loop grows and tunes the library: the LLM proposes items and guard wordings, Jev answers over the corpus, the pairwise judge scores the results, and weak items are revised or dropped (TypeSafe's autoresearch cookbook).
- Thresholds are placed "in the gap" on labelled runs, with raw answers stored.
- Humans review every item before it ships.

## 7. Honest expectations

- **Tier A share grows with library coverage.** It is limited by requests that hinge on a module's internals. A realistic first target is 30–50% of requests at *judge parity* in about 2 s.
- **Tier B targets most of the rest in about 8 s,** 4× faster than today, with a grounded, verified skeleton. It still has to prove parity. The earlier Tier B mock lost, but it used a weak skeleton; v2's is the Experiment-A-quality skeleton minus the guard-failed items.
- **Tier C remains for vague, high-risk or novel requests.**
- **Validity is structural.** Compiled specs pass `validate-prompt.sh` by construction, whereas today's opus path fails it 37% of the time (15/40), mostly from tag drift.

## 8. Build plan (milestones, each gated by the benchmark)

1. **Engine:** L0 candidates + the L1 wide call + the typed compiler with traces and guards. This replaces v1's `jev-decide.sh`/`fast-compose.sh`.
2. **Library v0:** 6–8 cells for the commonest nodes (CLI flag and option kinds, env var, docs edit, CI/config bump, bugfix in a script, test addition, perf of a script), authored offline by opus with guards, then reviewed. Target: Tier A parity on those cells.
3. **L1b + L3:** semantic-find code anchors, taxonomy beam, coverage.
4. **Tier B:** parallel gap-section LLM completion with guard re-checks. Measure parity and latency.
5. **Corpus + calibration:** grow to 100+ requests across several repos; autoresearch loop; thresholds in the gap.
6. **Ship opt-in.** Default `off` until the judge numbers hold.

## 9. Decisions taken

1. The deterministic repo index (`git ls-files` cards, `git grep -F`) is allowed on the fast path only; `gather-context.sh` stays fixed-path.
2. Opus authors the library offline (`bench/jev/authoring/`). All 9 cells are still unreviewed (`provenance.reviewed_by: null`).
3. Tier B uses an LLM on the request path for gap sections only.

## 10. What was built and what it measured

**Built:** the L0–L5 engine in `skills/prompt-improver/scripts/compile/`, tiers A, B and C in `generate-prompt.sh`, 9 guarded cells, and the authoring loop (author, validate, calibrate, revise).

Engine lessons from calibration:
- **The L0 target is a guess from file names.** Jev's file relevance overrides a clear miss, for example "the link to docs/X.md in the README".
- **One broad multi-task question fired at 0.62–0.79 on single-task requests.** Two narrower questions, combined by taking the larger answer, separate them.
- **Role slots (`{desired}` etc.) often do not resolve.** So cells declare `key_slots`, and every required section has an item that needs only those slots.

**Calibration:** 29 requests about this repo, distinct from the corpus, run after one revision round.
- The right cell was picked for 23 of 23 fitting requests.
- All 6 near-misses were rejected.
- Tiers: 9 A, 13 B, 1 C.

**Benchmark:** the 40-request corpus with live `jev-1.13.0`. The opus baseline was regenerated under the Opus 5.5 XML rules. Every pair was judged blind by opus in both orders, so each request gives two verdicts.

| mode | path | n | p50 | p95 | valid | win/tie/loss vs opus |
|---|---|---|---|---|---|---|
| opus alone | llm | 40 | 34.2 s | 46.9 s | 40/40 | – |
| v2 auto | all | 40 | 31.5 s | 64.9 s | 40/40 | 15/0/65 |
| v2 auto | A (compiled, no LLM) | 3 | 2.0 s | 2.0 s | 3/3 | 0/0/6 |
| v2 auto | B (compiled + LLM gaps) | 10 | 13.3 s | 78.7 s | 10/10 | 0/0/20 |
| v2 auto | C (opus + Jev grounding) | 26 | 33.9 s | 45.4 s | 26/26 | 15/0/37 |
| v2 auto | passthrough | 1 | 2.3 s | 2.3 s | 1/1 | 0/0/2 |

Two tier-B runs were slow because of a single sonnet call writing one section: 170 s (r04, 25 KB prompt) and 79 s (r37, 56 KB prompt).

**Why v2 loses** (the judge's own reasons on r06, r08 and r02):
- **Compiled specs read as filled templates.** Examples: "probes items", duplicated lines, a JSON "format" with no schema, and verification that is generic or omits a documented argument. Opus writes concrete example lines and names the repo's traps from CLAUDE.md. Guards stop wrong items from being emitted, but they cannot add the request-specific content that decides these comparisons.
- **Tier C grounding hurts requests that are not about this repository.** An auth bug in some other application got this repo's Bash rules, test suite and changelog. Opus alone asked which codebase was meant.
- **The baseline moved.** Under the Opus 5.5 XML rules, opus specs went from 25/40 to 40/40 valid, so structural validity no longer favours v2.

**Verdict:** v2 cuts latency only where it cuts quality. On this corpus there is no tier at which it matches opus. v2 stays opt-in and off, and is not recommended.

**What would have to change for another attempt** (not planned):
- Ground tier C only when the request resolves to a real target in the repository.
- Treat compiled output as grounding for the LLM rather than as the spec itself.
- Measure that change on a corpus drawn from real use of the repository, not a mixed one.
