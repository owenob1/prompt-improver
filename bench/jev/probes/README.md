# Jev probes

Small, reproducible experiments behind `docs/investigations/jev-v2-architecture.md`. Each probe makes live calls to Jev, so it needs `TYPESAFE_API_KEY` or `OPENROUTER_API_KEY`, plus `jq` and `curl`.

| Script | What it measures |
|---|---|
| `scale.sh` | Latency vs questions per call (`SIZES="10 800 2500"`) |
| `determinism.sh` | Discrete choices and score jitter across identical calls (`RUNS=6`) |
| `cards.sh` | Deterministic file cards (path + description from the file's own header) |
| `retrieval.sh "<request>"` | Card-in-question file retrieval (state = request only) |
| `extract.sh "<request>"` | Role extraction by choice over enumerated word spans |
| `bank.sh "<request>"` | Relevance of the curated items in `lib/bank.tsv` |
| `guards.sh "<request>" <usage.txt>` | Item-specific premised guards |
| `slots.sh "<request>" <outdir>` | The wide L1 call. Writes `slots.tsv` and the selected CLAUDE.md rules |
| `compile.sh <cell.tsv> <slots.tsv> <rules.txt> "<request>"` | Mechanical compile of a spec from one library cell |
| `pairwise.sh "<request>" <specA> <specB>` | Blind opus judgement. Run both orders to cancel position bias |
| `rule_sentences.py CLAUDE.md` | Sentence-level rule units |

The whole pipeline for one request:

```bash
export TYPESAFE_API_KEY=…
R="add a --verbose flag to gather-context.sh that prints which probes ran"
O=$(mktemp -d)
bash slots.sh "$R" "$O"
bash compile.sh lib/cli-flag.diagnostic.tsv "$O/slots.tsv" "$O/rules.txt" "$R" > "$O/spec.xml"
bash ../../../skills/prompt-improver/scripts/validate-prompt.sh "$O/spec.xml"
```

`lib/cli-flag.diagnostic.tsv` is a single hand-written library cell, used as an experiment. It is not the product library. It ties opus on the request it was written against. On an unseen request of the same kind it loses, and the item guards are how v2 detects that (see the report).
