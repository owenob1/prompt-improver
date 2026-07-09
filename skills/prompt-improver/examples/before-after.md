# Before/After Examples

Transformations showing how the prompt-improver skill upgrades raw input. Each example highlights a specific pattern.

## Example 1: Few-shot examples for pattern tasks

### Before (user input)
```
add form validation to the signup page
```

### After (improved prompt)
```xml
<context>
  <project>Next.js 14, React, Zod, TypeScript</project>
  <scope>src/app/signup/page.tsx, src/lib/validation.ts</scope>
</context>

<task id="1" name="signup-validation">
  <description>
    Add client-side and server-side validation to the signup form with inline error messages.
  </description>

  <examples>
    <example>
      <input>User submits with empty email field</input>
      <output>Inline error "Email is required" below the email field, field gets red border, focus moves to email field</output>
    </example>
    <example>
      <input>User enters "notanemail" in email field</input>
      <output>Inline error "Enter a valid email address" below the field on blur</output>
    </example>
    <example>
      <input>User enters password shorter than 8 characters</input>
      <output>Inline error "Password must be at least 8 characters" with strength indicator showing weak</output>
    </example>
  </examples>

  <requirements>
    <group name="validation-rules">
      - Email: required, valid format, max 255 characters
      - Password: required, min 8 characters, at least one number and one letter
      - Name: required, 2-100 characters, no special characters except hyphens and apostrophes
    </group>
    <group name="ux">
      - Validate on blur (not keystroke) for each field
      - Show all errors on submit attempt
      - Clear field error when user starts typing in that field
      - Zod schema shared between client and server validation
    </group>
  </requirements>

  <references>
    - Follow the validation pattern in src/lib/validation.ts if it exists
  </references>

  <verification>
    - Run npm test -- --testPathPattern=signup
    - Submit form with empty fields — all three error messages appear
    - Submit with invalid email — email error appears, other fields unaffected
    - Run npx tsc --noEmit — zero errors
  </verification>
</task>

<execution>
  <constraints>
    - Use Zod for schema definition — share between client and server
    - Do not add new dependencies beyond Zod (already installed)
  </constraints>
  <escape>
    If the existing form structure makes inline errors difficult to implement,
    flag the structural issue rather than using toast notifications as a workaround.
  </escape>
</execution>

<check>
  - Re-read all changed files — verify no placeholders or empty handlers
  - Run npx tsc --noEmit
  - Run npm test
  - Report status for each validation rule
</check>
```

**Pattern shown**: Few-shot `<examples>` block with input/output pairs for each validation scenario. This is the most effective way to specify UI behaviour — showing beats telling.

---

## Example 2: Escape clause preventing silent failure

### Before (user input)
```
refactor the auth middleware to use JWT instead of sessions, but keep backward compatibility with existing sessions
```

### After (improved prompt)
```xml
<context>
  <project>Express.js, TypeScript, PostgreSQL</project>
  <scope>src/middleware/auth.ts, src/lib/session.ts, src/lib/jwt.ts (new)</scope>
  <current-behavior>Session-based auth using express-session with PostgreSQL store</current-behavior>
  <desired-behavior>JWT-based auth with backward compatibility for existing sessions</desired-behavior>
</context>

<research>
  Search before implementing:
  - JWT best practices for Express (token rotation, refresh tokens, storage)
  - Migration patterns from sessions to JWT (dual-mode auth)
  Explore the codebase:
  - Read src/middleware/auth.ts for current session handling
  - grep for session usage across all route files
</research>

<task id="1" name="jwt-auth-middleware">
  <description>
    Create JWT auth middleware that also accepts existing session tokens during a transition period.
  </description>

  <approach>
    Before implementing, reason through:
    - How to detect whether an incoming request uses JWT or session auth
    - Where to store JWT secret (env var, config)
    - Token expiry and refresh strategy
    - How long the backward-compatibility period should last
    Select an approach and commit to it.
  </approach>

  <requirements>
    - Accept both Authorization: Bearer {jwt} and existing session cookies
    - Check JWT first, fall back to session if no JWT present
    - JWT payload: { userId, email, role, iat, exp }
    - Token expiry: 1 hour access token, 7 day refresh token
    - Store JWT_SECRET in environment variable
  </requirements>

  <verification>
    - Test: request with valid JWT passes auth
    - Test: request with valid session cookie passes auth
    - Test: request with expired JWT returns 401
    - Test: request with neither returns 401
    - Run npx tsc --noEmit
  </verification>
</task>

<execution>
  <constraints>
    - Do not remove session support — both must work simultaneously
    - Do not change the User type or database schema
  </constraints>
  <escape>
    If maintaining full backward compatibility with sessions while adding JWT
    creates security concerns (e.g., token confusion attacks, inconsistent
    auth state) — flag the specific concern rather than silently weakening
    either auth method.
  </escape>
</execution>

<check>
  - Re-read auth middleware — verify both paths are fully implemented
  - Run npx tsc --noEmit
  - Run npm test -- --testPathPattern=auth
  - Verify no session-only routes were broken
</check>
```

**Pattern shown**: The `<escape>` clause explicitly handles the tension between "use JWT" and "keep sessions" — two requirements that can conflict. Without the escape clause, Claude would silently produce a degraded implementation of one or both.

---

## Example 3: Think-then-answer with approach block

### Before (user input)
```
add caching to the API responses
```

### After (improved prompt)
```xml
<context>
  <project>Node.js, Hono, TypeScript, Redis</project>
  <scope>src/middleware/cache.ts (new), src/api/ routes</scope>
</context>

<research>
  Search before implementing:
  - HTTP caching headers (Cache-Control, ETag, Last-Modified)
  - Redis caching patterns for API responses
  Explore the codebase:
  - Read existing middleware in src/middleware/ for patterns
  - Check which routes are read-heavy vs write-heavy
</research>

<task id="1" name="api-cache-middleware">
  <description>
    Add response caching middleware for read-heavy API endpoints.
  </description>

  <approach>
    Before implementing, reason through:
    - Which caching layer: HTTP headers only, Redis cache, or both?
    - Which routes benefit from caching (GET endpoints returning stable data)?
    - Cache invalidation strategy: TTL-based, event-based, or manual purge?
    - Criteria: latency reduction, cache hit rate, staleness tolerance.
    Select an approach and commit to it. Avoid revisiting unless new info contradicts your reasoning.
  </approach>

  <requirements>
    - Cache middleware applied selectively via route-level opt-in
    - Cache key: HTTP method + path + sorted query params
    - Configurable TTL per route (default: 60 seconds)
    - Cache-Control and ETag headers on cached responses
    - Cache bypass: requests with Cache-Control: no-cache skip cache
    - Invalidation: DELETE/PUT/POST to a resource clears related cache keys
  </requirements>

  <verification>
    - Test: first GET request misses cache, second hits
    - Test: POST to resource clears the GET cache for that resource
    - Test: Cache-Control: no-cache header bypasses cache
    - Run npx tsc --noEmit
    - curl endpoint twice — second response has X-Cache: HIT header
  </verification>
</task>

<execution>
  <constraints>
    - Use existing Redis connection from src/lib/redis.ts
    - Do not cache authenticated/user-specific responses without per-user keys
  </constraints>
  <escape>
    If the existing Redis setup does not support the needed operations,
    flag it rather than adding a second Redis client or connection pool.
  </escape>
</execution>

<check>
  - Re-read cache middleware — verify cache invalidation is implemented (not stubbed)
  - Run npx tsc --noEmit
  - Run npm test
  - Report: cache hit, cache miss, cache invalidation all verified
</check>
```

**Pattern shown**: The `<approach>` block directs Claude to reason through the caching strategy before writing code, then commit to a decision. This replaces the old `<evaluate>` pattern and prevents the common failure of starting implementation before the design is settled.

---

## Example 4: Calm language vs aggressive style

### Before (aggressive language — old style)
```xml
<constraints>
  - You MUST NEVER use `any` type. There are NO exceptions.
  - CRITICAL: You MUST run typecheck after EVERY change. This is non-negotiable.
  - NEVER create stubs or placeholder implementations. ABSOLUTELY REQUIRED.
  - IMPORTANT: You MUST re-read files after writing. ALWAYS.
</constraints>
```

### After (calm, direct — Claude 4.6 style)
```xml
<constraints>
  - Type all parameters and return values explicitly — do not use `any`
  - Run typecheck after each change
  - Implement all functions fully — no stubs or placeholder returns
  - Re-read changed files after writing to verify correctness
</constraints>
```

**Pattern shown**: Same rules, 60% fewer words, zero aggressive markers. Claude 4.6 follows calm instructions more reliably than shouted ones.

---

## Example 5: Task-specific constraints vs generic dump

### Before (generic guardrail dump — old style)
```xml
<constraints>
  - "No stubs, TODOs, placeholders, or throw new Error('Not implemented'). Implement fully."
  - "After writing code, re-read the file to confirm real logic exists."
  - "Only modify files directly related to the request."
  - "Use Bash/scripts for all deterministic operations."
  - "Verification = runnable commands only."
  - "AI agents cut corners and mistake compilation for completion."
  - "Quality gates produce false positives. They prove syntax, not function."
  - "When inheriting work: read the actual code, don't trust the summary."
  - "ALL UI/UX changes must be verified in Chrome after deployment."
  - "Commit after each completed task."
  - "Stage specific files (not git add -A)."
  - "Test suite must pass before marking task complete."
  - "Never fix bugs by guessing."
  - "Search docs before writing code for external services."
  - "Before reporting done, list each requirement's status."
  {... same boilerplate in every prompt regardless of task}
</constraints>
```

### After (task-specific constraints for a Stripe webhook endpoint)
```xml
<constraints>
  - Use the raw request body for signature verification — do not parse JSON before verifying
  - Store webhook secret in STRIPE_WEBHOOK_SECRET env var, not in code
  - Return 200 for unknown event types — do not block Stripe retries
  - Do not modify existing billing service logic — only add webhook ingestion
  - Use existing dependencies only (stripe SDK should already be installed)
</constraints>
```

**Pattern shown**: Every constraint addresses a specific failure mode *for this task*. "Use raw body for signature verification" prevents the #1 Stripe webhook bug. "Return 200 for unknown events" prevents retry storms. Generic boilerplate like "no stubs" and "run tests" belongs in verification and check blocks, not constraints. Constraints should answer: "What will go wrong with *this specific task* if I don't say this?"

---

## Example 6: Deterministic-first (scripted operations over AI)

### Before (user input)
```
rename the Button component to ActionButton everywhere
```

### After (improved prompt)
```xml
<context>
  <project>React, TypeScript, Tailwind CSS</project>
  <scope>All files referencing Button component</scope>
</context>

<task id="1" name="rename-component">
  <description>
    Rename the Button component to ActionButton across the entire codebase using deterministic search-and-replace.
  </description>
  <requirements>
    - Use grep to find all files containing "Button" (excluding node_modules, dist, .git)
    - Use sed to replace: component name in declarations, imports, JSX usage, and file names
    - Rename the file: Button.tsx to ActionButton.tsx
    - Update the barrel export in index.ts if one exists
    - This is a mechanical operation — use scripts, not AI-driven file-by-file editing
  </requirements>
  <verification>
    - grep -r "Button" src/ --include="*.tsx" --include="*.ts" | grep -v "ActionButton" returns empty
    - npx tsc --noEmit passes
    - npm test passes
    - File src/components/ActionButton.tsx exists
    - File src/components/Button.tsx does not exist
  </verification>
</task>

<check>
  - Re-read ActionButton.tsx to verify the component name is correct
  - Run npx tsc --noEmit — zero type errors
  - Run npm test — all tests pass
</check>
```

**Pattern shown**: AI inference replaced with grep+sed for mechanical find-and-replace. Verification is fully deterministic.

---

## Example 7: Decision boundary examples with reasoning

### Before (user input)
```
add rate limiting to the API
```

### After (improved prompt)
```xml
<context>
  <project>Hono, TypeScript, Redis, Cloudflare Workers</project>
  <scope>src/middleware/rate-limit.ts (new), src/api/ routes</scope>
</context>

<research>
  Search before implementing:
  - Cloudflare Workers rate limiting patterns (Workers KV vs Durable Objects vs external Redis)
  - Hono middleware patterns for request interception
  Explore the codebase:
  - Read existing middleware in src/middleware/ for patterns
  - Check if Redis or KV is already configured
</research>

<task id="1" name="rate-limit-middleware">
  <description>
    Add configurable rate limiting middleware for API endpoints with per-route limits.
  </description>

  <approach>
    Before implementing, reason through:
    - Which storage backend: Workers KV (eventual consistency), Durable Objects (strong consistency), or Redis?
    - Criteria: latency, accuracy, cost, existing infrastructure.
    - Algorithm: fixed window, sliding window, or token bucket?
    Select an approach and commit to it.
  </approach>

  <examples>
    <example>
      <input>GET /api/search — public endpoint, high traffic</input>
      <output>Rate limit: 60 requests/minute per IP, sliding window</output>
      <reasoning>
        Public endpoint with high traffic needs aggressive limiting to prevent abuse.
        Sliding window prevents burst-then-wait patterns. IP-based because no auth required.
      </reasoning>
    </example>
    <example>
      <input>POST /api/auth/login — authentication endpoint</input>
      <output>Rate limit: 5 requests/minute per IP, fixed window, 429 with Retry-After header</output>
      <reasoning>
        Authentication endpoints need strict limits to prevent brute force attacks.
        Fixed window is sufficient here. Include Retry-After header for client backoff.
      </reasoning>
    </example>
    <example>
      <input>GET /api/users/me — authenticated endpoint, normal traffic</input>
      <output>Rate limit: 120 requests/minute per user ID, sliding window</output>
      <reasoning>
        Authenticated endpoint — rate limit per user ID, not IP, because multiple
        users may share an IP (corporate NAT). Higher limit because authenticated
        users are less likely to be abusive.
      </reasoning>
    </example>
  </examples>

  <requirements>
    - Middleware applied selectively via route-level configuration
    - Configurable: requests per window, window size, key extraction (IP vs user ID)
    - Return 429 with Retry-After header when limit exceeded
    - Log rate limit hits with request context for monitoring
  </requirements>

  <verification>
    - Test: 61st request in 60 seconds returns 429
    - Test: Retry-After header present on 429 response
    - Test: authenticated endpoint limits by user ID, not IP
    - Run npx tsc --noEmit
  </verification>
</task>

<execution>
  <constraints>
    - Use existing Redis/KV connection — do not add a new storage dependency
    - Rate limit state must survive request restarts (not in-memory only)
  </constraints>
  <escape>
    If the deployment target does not support the chosen storage backend,
    flag the incompatibility rather than falling back to in-memory limiting.
  </escape>
</execution>

<check>
  - Re-read rate limit middleware — verify all paths implemented
  - Run npx tsc --noEmit
  - Run npm test
  - Report status for each requirement
</check>
```

**Pattern shown**: The `<examples>` block includes `<reasoning>` for each case, teaching Claude the decision process — not just the outcome. This is the decision boundary technique: 1 public endpoint (aggressive limit), 1 auth endpoint (strict security limit), 1 authenticated endpoint (per-user limit). The reasoning explains WHY each case is different, so Claude can generalise to new endpoints.

---

## Example 8: Emphasis calibration — safety rules vs general instructions

### Before (all rules at maximum emphasis)
```xml
<constraints>
  CRITICAL: You MUST NEVER use eval() or Function() constructor. NO exceptions.
  CRITICAL: You MUST run typecheck after EVERY change. ABSOLUTELY REQUIRED.
  CRITICAL: You MUST NEVER commit without running tests. This is non-negotiable.
  CRITICAL: You MUST use const instead of let where possible. ALWAYS.
</constraints>
```

### After (emphasis calibrated to severity)
```xml
<!-- Safety rule: full emphasis is appropriate -->
<agent_constraints>
  NEVER use eval() or Function() constructor — these enable code injection attacks
  and are flagged by security scanners.
</agent_constraints>

<!-- Workflow rules: calm, direct instructions -->
<execution>
  <constraints>
    - Run typecheck after each change
    - Run tests before committing
    - Use const for bindings that are not reassigned
  </constraints>
</execution>
```

**Pattern shown**: The playbook's emphasis decision matrix in action. The eval() prohibition is a genuine security rule (CRITICAL severity) — it keeps NEVER with a WHY explanation. The workflow rules are MEDIUM severity — they use calm, direct instructions without capitalisation. Claude 4.6 follows calm instructions more reliably and may overtrigger on aggressive emphasis for non-safety rules. The authoritative tag name `<agent_constraints>` also adds semantic weight to the security rule.
