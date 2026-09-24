# prompt-improver MCP server

Endpoint: `https://prompt-improver.oweninnes.com/mcp` (health check at `/health`).

```bash
claude mcp add --transport http prompt-improver https://prompt-improver.oweninnes.com/mcp
```

This is a Cloudflare Worker (`prompt-improver-mcp`) serving prompt-improver over MCP, protocol 2026-07-28. It is stateless, with no model calls and no storage. 2025-era clients are served statelessly by the SDK's fallback.

| Surface | What it does |
|---|---|
| `improve_prompt` | Returns the generation prompt and a handle. The prompt is byte-identical to `assemble-generation-prompt.sh` with no user settings. With no `mode` given, it asks the user (MRTR elicitation) or defaults to `plan`. |
| `validate_prompt` | Runs a TypeScript port of `validate-prompt.sh` (same PASS/FAIL/WARN lines) and returns `next_step`: fix and re-validate, stop after 3 failed attempts, show (`plan`), or carry out (`execute`). |
| `improve` prompt | A slash-command entry point to the loop. |
| `skill://prompt-improver/...` | `mcp/skill/SKILL.md`, the skill's references and the examples, served as resources. They are also served through the Skills extension (`skills/list`, `skills/get`, sha256 manifest). |

## Source of truth

Nothing from the skill is copied by hand. `scripts/pack.mjs` builds the gitignored file `src/generated/pack.ts` from `skills/prompt-improver/` at build and test time:

- it runs the real bash assembler and splits its output around the request;
- it reads the fixed-path probe list from `gather-context.sh`;
- it hashes the served files.

A change to the skill's references or rules reaches the server on the next deploy.

The tests hold both ports to the bash originals:

- `test/validate.test.ts` compares the validator's output line for line on about 60 inputs, including every XML example in the references;
- `test/assemble.test.ts` compares the assembled prompt byte for byte;
- `test/server.test.ts` drives the full protocol over the Worker's fetch entry.

## Develop

```bash
cd mcp
npm ci
npm run typecheck
npm test
npm run dev        # wrangler dev on http://localhost:8787 (/health, /mcp)
```

## Deploy

`.github/workflows/mcp-deploy.yml` deploys on pushes to `main` that touch `mcp/**` or `skills/prompt-improver/**`, and can also be run by hand. It needs two repository secrets: `CLOUDFLARE_API_TOKEN` (a token with *Workers Scripts: Edit*) and `CLOUDFLARE_ACCOUNT_ID`.

To deploy by hand, run `cd mcp && npx wrangler deploy`.

To require a bearer token on `/mcp`, run `npx wrangler secret put AUTH_TOKEN`. Clients then send `Authorization: Bearer <token>`. Without the secret, the endpoint is open. It holds no data and calls no paid APIs.

The worker replaces the earlier Workers AI `prompt-improver-mcp`. A `state: "deleted"` exports tombstone in `wrangler.jsonc` retired that worker's `PromptSession` Durable Object, and its AI and D1 bindings are gone. The only URL is the custom domain: `workers_dev` and `preview_urls` are off.
