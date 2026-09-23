# Investigation: a Jev fast path for prompt-improver

*Branch `claude/jev-fast-path-investigation` · started 2026-09-23 · status: prototype built, live measurement pending an API key*

## Question

Can prompt-improver use **Jev** (TypeSafe AI's "System One" decision model) to make prompt creation near-instant, without losing the quality the headless-LLM path produces today?

## Short answer

**Yes, for a subset of requests; never for all of them.**

Jev cannot write text. It only answers typed questions:
- `noul`: a yes/no probability.
- `choice`: one of up to 255 options.
- `score`: 2–10 ordered levels.

So Jev can never produce the improved XML itself. It can do three things:

1. **Replace the LLM entirely** for simple, single-task, low-risk requests. Jev classifies the request, and a template library plus the repo's deterministic facts compose the spec. Measured end to end with an instant stub, this takes about **0.9 s**. A live Jev adds two calls of 70–500 ms each, so the projection is **about 1–2 s, against ~32 s today**.
2. **Make the LLM path cheaper and shorter** for everything else. Jev picks the model tier and prunes reference material that is irrelevant to the request.
3. **Gate quality.** A second Jev call judges each composed spec against the request, and `validate-prompt.sh` must still pass. Anything that fails either check goes to the unchanged LLM path.

The prototype on this branch does all three. It is **opt-in and off by default**, and it **fails open**: any Jev error or timeout silently falls back to the 1.1.0 behaviour.

Whether the fast path loses quality is an empirical question. The benchmark in [`bench/jev/`](../../bench/jev) answers it. Its live numbers are **pending a `TYPESAFE_API_KEY` or `OPENROUTER_API_KEY`**, see [Results](#results).

## What Jev is

All facts below come from TypeSafe's docs, the OpenRouter guide and community tools. Where a claim is the vendor's own, it is marked as vendor-reported.

| | |
|---|---|
| API | `POST https://api.typesafe.ai/v1/systemone`, `Authorization: Bearer $TYPESAFE_API_KEY`; also OpenRouter `POST /api/v1/systemone` with `OPENROUTER_API_KEY` (not chat-completions compatible) |
| Request | `{model, state, questions}` — `state` is a string, JSON or array of text; `questions` is a map of `{type, instructions, criteria?}` |
| Question types | `noul` → `noul` probability; `choice` (≤255 options) → `choice`, `probabilities`, `confidence`; `score` (2–10 levels) → weighted `score`, `probabilities`, `confidence` |
| Limits | 64k tokens per request (32k for state + longest question); 250k tokens/s, 1,200 req/min; max questions per call undocumented |
| Latency | 70–500 ms end to end (vendor); ~240 ms per decision measured by a community Claude Code plugin |
| Cost | $0.042 per million input tokens; output free |
| Model | `jev-1.13.0` (`jev-latest`) |
| Weak at | text generation (none), arithmetic, counting, dates, negation, large irrelevant state, languages other than English (vendor: "not equally well") |
| Calibration | `confidence` measures how concentrated the distribution is; the vendor gives no formal calibration guarantee and says to validate on your own data |

Sources:
- [docs.typesafe.ai/api](https://docs.typesafe.ai/api)
- [primitives](https://docs.typesafe.ai/primitives)
- [models](https://docs.typesafe.ai/models.md)
- [confidence](https://docs.typesafe.ai/confidence.md)
- [OpenRouter guide](https://openrouter.ai/docs/guides/community/typesafe-sdk)
- [Simon Willison](https://simonwillison.net/2026/Sep/21/jev/)
- [Sean Goedecke](https://www.seangoedecke.com/jev-means-structured-output-is-interesting-again/)
- [Gilbert09/jev-cli](https://github.com/Gilbert09/jev-cli)

## Where the time goes today

Measured on this repo in the cloud container, 2026-09-23:

| Stage | Time |
|---|---|
| `gather-context.sh` | ~30 ms |
| `load_settings` (many small `jq` calls) | ~270 ms |
| `assemble-generation-prompt.sh` (65 KB prompt) | ~400 ms |
| `validate-prompt.sh` | ~100 ms |
| **Everything except the LLM** (instant `custom_command`) | **~750 ms** |
| Headless `claude -p` generation, `opus` | **~30 s** |

The LLM call accounts for about 97% of the wall time. "Near-instant" therefore means one thing: **don't make that call**, or make a much shorter one.

A separate cheap win: `load_settings` and the assembler together spend ~0.6 s forking `jq`. Batching those reads would bring the non-LLM floor down to roughly 0.2–0.3 s, whatever happens with Jev.

## Capability map

These are the decisions the skill makes today, mostly implicitly inside the LLM call, with whether Jev can make each one.

| Decision | Jev question | Fit |
|---|---|---|
| Is this trivial / already a spec / rough? | `triage` · choice | Good (classification) |
| What kind of work is it? | `archetype` · choice over 9 templates | Good (routing is Jev's headline use) |
| How big is it? | `complexity` · score (4 levels) | Good (rubric scoring) |
| How risky is it? | `risk` · score (3 levels) | Good |
| Is it several independent tasks? | `multi_task` · noul | Good; this is the key gate for templates |
| Is it clear enough to specify? | `clarity` · score (3 levels) | Good — see [Question design](#question-design-findings); a yes/no `vague` question did not work |
| Needs external research? UI? Autonomous agent? | `needs_research` / `ui` / `autonomous` · noul | Good |
| Does a spec faithfully cover the request? | `faithful` · noul, `fit` · score | Good (claim checking against evidence) |
| **Write the requirements, steps and acceptance criteria for *this* request** | — | **Impossible: text generation** |
| Pick which verification commands apply | (deterministic from `gather-context.sh`) | Not needed — shell already knows |

The last two rows mark the boundary. Anything request-specific that has to be *written* stays with an LLM. The fast path compensates in two ways:
- It embeds the user's request verbatim, instead of paraphrasing it.
- It pairs the request with archetype-specific process guidance, for example:
  - bugfix: reproduce first, then add a regression test;
  - perf: measure a baseline, profile, then re-measure;
  - refactor: capture a behavioural baseline, then search for stale references.

## Strategies

### S1 — Triage passthrough
If Jev says the input is already an execution-ready spec (confidence ≥ 0.8) **and** it passes `validate-prompt.sh`, the input is returned unchanged. This costs one Jev call.

### S2 — Route
When composing isn't safe, Jev hands the LLM path two hints:
- **A model tier.** Low when complexity ≤ 1, risk ≤ 0.5 and not multi-task. The tier maps through `fast_path.route_models`: claude `sonnet`/`opus`, codex `gpt-6-luna`/`gpt-6-sol`, and so on.
- **Reference pruning.** The chaining guide and before/after examples are left out of the generator prompt for single, simple tasks.

An explicit `model:` always wins over the tier. This follows TypeSafe's own "model routing" pattern. It still costs one LLM call, so the win is lower cost and some latency, not "instant".

### S3 — Compose
All of these gates must pass:
- archetype confidence ≥ 0.6
- complexity ≤ 1.0
- risk ≤ 0.5
- `multi_task` ≤ 0.25
- `clarity` ≥ 1.0 (out of 2)

When they do, [`fast-compose.sh`](../../skills/prompt-improver/scripts/fast-compose.sh) fills [`assets/fast-templates/base.xml`](../../skills/prompt-improver/assets/fast-templates/base.xml) with the archetype fragment. The inputs are:
- the verbatim, XML-escaped request;
- the typecheck, test and build commands and platform from `gather-context.sh`;
- optional `<research>`, UI viewport-verification and `<override_rules>` blocks, when Jev flags them.

Every template follows `references/prompting-principles.md` and passes `validate-prompt.sh` with zero warnings. It carries:
- a `<verification>` block per task;
- `<approach>`;
- `<escape>`;
- a `<check>` block that re-reads changed files, or declares the work read-only.

### S4 — Judge
A second Jev call scores the composed spec against the request: `faithful` ≥ 0.7 and `fit` ≥ 1.5 out of 2. On a failure, `auto` mode falls through to S2.

### Rejected or deferred
- **Jev choosing between pre-written LLM specs** (a semantic cache). This is feasible with `choice` over up to 255 cached specs. It is deferred because reusing a spec written for a different request risks fidelity, and the corpus doesn't measure that yet.
- **Running the LLM speculatively in parallel with Jev.** This hides Jev's latency but doubles LLM spend on every served request. Jev is fast enough that it isn't worth it.
- **Letting Jev pick verification commands.** Shell detection is already deterministic and free.

## Prototype on this branch

| File | Role |
|---|---|
| `skills/prompt-improver/scripts/lib/jev.sh` | curl + jq client; provider auto-detect (TypeSafe, then OpenRouter); key sent through a mode-600 header file, never argv; 2 s timeout; one retry on 429/5xx; credential redaction |
| `skills/prompt-improver/scripts/jev-decide.sh` | One parallel Jev call (`decide` or `judge`); state = redacted request + trimmed repo facts (the agent-instruction excerpt and git history are dropped to avoid context rot) |
| `skills/prompt-improver/scripts/fast-compose.sh` | Deterministic composition from a decision |
| `skills/prompt-improver/scripts/fast-path.sh` | Gates S1–S4, returns a prompt (exit 0) or route hints (exit 3) |
| `skills/prompt-improver/assets/fast-templates/` | `questions.json` (the Jev question set), `base.xml` and 9 archetype fragments |
| `generate-prompt.sh` | Calls the fast path before assembly when `fast_path.mode` ≠ `off`; the exit-code contract is unchanged |
| `bench/jev/` | Corpus (40 requests), runner, blind pairwise judge, report |

Settings (`config/runtime-defaults.json` → `fast_path`, env `PROMPT_IMPROVER_FAST_PATH`):

```json
"fast_path": {
  "mode": "off",               // off | route | compose | auto
  "timeout_ms": 2000,
  "judge": true,
  "thresholds": { "ready_confidence": 0.8, "archetype_confidence": 0.6, "max_complexity": 1.0,
                  "max_risk": 0.5, "max_multi_task": 0.25, "min_clarity": 1.0,
                  "min_faithful": 0.7, "min_fit": 1.5 },
  "route_models": { "claude": { "low": "sonnet", "high": "opus" }, … },
  "route_prune_references": true
}
```

Try it:

```bash
export TYPESAFE_API_KEY=…            # or OPENROUTER_API_KEY
PROMPT_IMPROVER_FAST_PATH=auto bash skills/prompt-improver/scripts/generate-prompt.sh --mode plan --raw-input-file - <<'REQ'
fix the typo in the README install section
REQ
# stderr shows e.g.:
#   fast-path: jev decide 180ms — triage=trivial archetype=docs(0.91) complexity=0.1 …
#   fast-path: compose (archetype docs, jev 180ms + judge 150ms faithful=0.95 fit=1.9)
```

Test coverage: smoke group `[25]` runs against a stub `/systemone` API and checks:
- the fast path is off by default and never calls Jev;
- compose serves a confident request with exactly two Jev calls and no LLM call;
- the route tiers and reference pruning;
- an explicit model beating the route tier;
- judge rejection;
- ready passthrough;
- 401, malformed and timeout responses each falling back silently;
- redaction, and the API key staying off curl's argv;
- every template validating, XML escaping, and archetype/template parity;
- no jq meaning the fast path is off.

## Results

Baseline (`off`, 1.1.0 LLM path, claude `opus`, this repo): **see the table below once `bench/jev/run.sh` finishes.** The Jev modes need an API key.

| mode | n | p50 | p95 | served fast | fast p50 | Jev p50 | valid | win/tie/loss (all) | win/tie/loss (fast-served) |
|---|---|---|---|---|---|---|---|---|---|
| off | *pending* | | | | | | | | |
| route | *pending API key* | | | | | | | | |
| compose | *pending API key* | | | | | | | | |
| auto | *pending API key* | | | | | | | | |

To reproduce:

```bash
export TYPESAFE_API_KEY=…
bash bench/jev/run.sh        # all modes over bench/jev/corpus.jsonl (resumable)
bash bench/jev/judge.sh      # blind pairwise vs baseline, claude opus as judge
bash bench/jev/report.sh     # the table above
```

**Acceptance bar for "no quality loss":**
- On the requests the fast path serves, the candidate wins or ties against the baseline in **≥ 90%** of blind pairwise judgements.
- **100%** of served prompts pass `validate-prompt.sh`.

If compose misses the bar, tighten `thresholds` (serve fewer requests fast) until it passes, and record the trade-off. The honest outcome may be that compose only clears the bar for `docs`/`config`/`tests`-type requests, and `route` carries the rest.

## Risks and open questions

- **Privacy.** The fast path sends the request and trimmed repo facts (platform, detected commands, top-level file names) to TypeSafe or OpenRouter. Credential-shaped strings are redacted first, and it is opt-in. It must stay off by default and be documented as a third-party data flow.
- **Template quality ceiling.** Composed specs can't restate the request as specific acceptance criteria. That is the main risk to the quality bar, and it is exactly what the pairwise judge measures.
- **Calibration.** Thresholds are based on vendor examples (0.5 floor, 0.6–0.8 working range) and must be tuned on the corpus. Jev's `confidence` is how concentrated the distribution is, not a probability of being correct.
- **Languages other than English.** The vendor says these are supported "not equally well". The corpus includes Spanish and Japanese requests. If Jev misroutes them, add a language gate.
- **Negation.** Questions are phrased positively on purpose. Keep them that way when editing `questions.json`.
- **Vendor maturity.** Jev launched 2026-09-15 and all benchmarks so far are vendor-run. The API shape conflicts between TypeSafe's docs and one community site; the prototype follows the official `/v1/systemone`. The fail-open design limits the blast radius.
- **Cost.** A decide call plus a judge call is about 2–3k input tokens, roughly $0.0001, which is negligible next to one LLM generation.

## Recommendation (provisional, pending live numbers)

1. Ship **`auto` as an opt-in** once the benchmark clears the bar, with the thresholds the corpus supports. Keep **`off` as the default**, because of the third-party data flow.
2. Ship **S2 route** first if compose misses the bar. It is the lowest-risk quality/latency trade, since the LLM still writes every spec.
3. Independently, batch the `jq` reads in `load_settings` and the assembler. It saves ~0.5 s on every path.
4. Revisit the semantic cache (S5) once real usage builds a corpus of accepted specs per repo.
