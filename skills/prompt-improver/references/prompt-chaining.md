# Prompt Chaining

When a single prompt grows too large (>80 lines, 5+ tasks, or cross-cutting concerns), split it into sequential phases. Each phase is self-contained and builds on the output of the previous phase.

## When to chain

- **>5 tasks** — a single prompt with 5+ task blocks dilutes focus
- **Cross-cutting concerns** — changes that touch multiple layers (API + database + UI + tests)
- **Research-then-build** — when the implementation depends on research findings
- **Large migrations** — framework swaps, major refactors, platform moves
- **Uncertain scope** — when Phase 1 findings determine Phase 2 approach

## Phase structure

The canonical chain is: **Research -> Implement -> Polish**

| Phase | Purpose | Typical tasks |
|-------|---------|---------------|
| Research | Understand scope, audit current state, evaluate options | Audit files, read docs, evaluate libraries, create checklist |
| Implement | Build the core changes | Create/modify files, write logic, add tests |
| Polish | Verify, clean up, document | Run full test suite, fix edge cases, update docs |

Not every chain needs all three phases. Simple features may only need Implement + Polish. Complex migrations may need Research + multiple Implement phases + Polish.

## Phase prompt template

Each phase prompt is self-contained — it includes everything needed to execute without prior context:

```xml
<context>
  <project>{tech stack, framework, key libraries}</project>
  <scope>{what this phase covers}</scope>
  <phase>Phase {N} of {total}: {phase name}</phase>
  <prior-phase-output>
    {Summary of what previous phases produced — files created/modified, decisions made, findings}
    {Only include for Phase 2+. Be specific: list file paths, key decisions, test results.}
  </prior-phase-output>
</context>

<task id="1" name="{task-name}">
  <description>{what this task accomplishes}</description>
  <requirements>
    - {specific requirement}
  </requirements>
  <verification>
    - {how to check it worked}
  </verification>
</task>

<execution>
  <strategy>{how to work through this phase}</strategy>
  <constraints>
    - {phase-specific constraints}
  </constraints>
  <escape>
    If any requirement seems contradictory or infeasible, flag it and ask
    rather than working around it.
  </escape>
  <next-phase>
    Phase {N+1} will cover: {brief description of what comes next}
  </next-phase>
</execution>

<check>
  - Re-read changed files — verify no placeholders or empty functions
  - Run {typecheck command}
  - Run {test command}
  - Report status for each requirement
</check>
```

## Passing context between phases

The `<prior-phase-output>` tag carries forward what matters:

```xml
<prior-phase-output>
  Phase 1 (Research) completed:
  - Audited 12 route files in src/api/
  - Identified 3 Express-specific middleware: cors, helmet, body-parser
  - Hono equivalents: hono/cors (built-in), @hono/helmet (npm), built-in body parsing
  - Decision: migrate routes alphabetically, leaf routes first
  - Created migration checklist at docs/migration-checklist.md
</prior-phase-output>
```

Be specific about:
- Files created or modified
- Decisions made and why
- Test results (what passes, what is currently broken)
- Anything the next phase needs to know

## Example: 3-phase migration (Express to Hono)

### Phase 1: Research and audit

```xml
<context>
  <project>Express.js, TypeScript, PostgreSQL</project>
  <scope>Full framework migration: Express to Hono</scope>
  <phase>Phase 1 of 3: Research and Audit</phase>
</context>

<research>
  Search before starting:
  - Hono routing API, middleware patterns, and Node.js adapter
  - Known Express-to-Hono migration pitfalls
  - Hono equivalent for each Express middleware in use
</research>

<task id="1" name="audit-express-usage">
  <description>Catalog all Express-specific APIs and middleware used across the codebase.</description>
  <requirements>
    - List every route file with HTTP methods and paths
    - List every middleware with its Express-specific signature
    - Map each Express API to its Hono equivalent
    - Identify third-party Express middleware and find Hono alternatives
    - Output: migration checklist document
  </requirements>
  <verification>
    - Every .ts file in src/api/ and src/middleware/ is accounted for
    - Every Express-specific import has a mapped Hono equivalent
    - Checklist document created at docs/migration-checklist.md
  </verification>
</task>

<execution>
  <escape>
    If any Express middleware has no Hono equivalent, flag it rather than
    building a custom replacement without approval.
  </escape>
</execution>

<check>
  - Re-read the migration checklist and verify completeness
  - Run typecheck to confirm no changes broke the build
</check>
```

### Phase 2: Core migration

```xml
<context>
  <project>Express.js to Hono, TypeScript, PostgreSQL</project>
  <scope>Server setup and route migration</scope>
  <phase>Phase 2 of 3: Core Migration</phase>
  <prior-phase-output>
    Phase 1 completed:
    - 12 route files, 4 middleware files identified
    - Migration checklist at docs/migration-checklist.md
    - Hono equivalents confirmed for all middleware
    - Decision: migrate in order — server setup, global middleware, routes (alphabetical)
  </prior-phase-output>
</context>

<task id="1" name="hono-server-setup">
  <description>Replace Express server entry point with Hono.</description>
  <requirements>
    - Install hono and @hono/node-server
    - Replace src/index.ts server setup
    - Migrate global middleware (cors, body parsing, error handler)
  </requirements>
  <verification>
    - Server starts without errors
    - Health check endpoint responds
  </verification>
</task>

<task id="2" name="migrate-routes" depends-on="1">
  <description>Migrate all route handlers from Express to Hono patterns.</description>
  <requirements>
    - Follow docs/migration-checklist.md order
    - Replace req/res patterns with Hono context (c.req, c.json)
    - Run tests after each file
  </requirements>
  <verification>
    - All existing API tests pass
    - No Express imports remain in migrated files
  </verification>
</task>

<check>
  - Re-read all migrated files
  - Run full test suite
  - Run typecheck
</check>
```

## Guidelines

- Each phase should be executable in one session — if too large, split further
- Be explicit about what carries forward — `<prior-phase-output>` is the handoff mechanism
- Present Phase 1 first — let the user review before generating subsequent phases
- Phases can be adjusted — Phase 1 findings may change the Phase 2 plan
- Generate Phase 2 only after Phase 1 is complete, using actual results
