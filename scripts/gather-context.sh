#!/usr/bin/env bash
# gather-context.sh
# Collects project context for prompt enrichment.
# Output is JSON-ish structured text for Claude to parse.
# Usage: bash gather-context.sh [project-root]

set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

# Source pilot library (graceful fallback)
_PILOT_LIB="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}/scripts/lib/pilot-query.sh"
if [[ -f "$_PILOT_LIB" ]]; then
  source "$_PILOT_LIB"
fi

echo "=== PROJECT CONTEXT ==="

# Tech stack detection
echo ""
echo "--- TECH STACK ---"

# Detect monorepo
echo ""
echo "--- MONOREPO ---"
if [ -f "turbo.json" ]; then
  echo "Monorepo: Turborepo"
elif [ -f "pnpm-workspace.yaml" ]; then
  echo "Monorepo: pnpm workspaces"
elif [ -f "nx.json" ]; then
  echo "Monorepo: Nx"
elif [ -f "lerna.json" ]; then
  echo "Monorepo: Lerna"
else
  echo "Monorepo: no"
fi

# List workspaces if monorepo
if [ -f "pnpm-workspace.yaml" ] && command -v pnpm &>/dev/null; then
  echo "Workspaces:"
  pnpm ls --depth -1 --json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for pkg in data:
        print(f'  - {pkg.get(\"name\", \"unknown\")}')
except: pass
" 2>/dev/null || echo "  (could not list workspaces)"
elif [ -f "package.json" ]; then
  # Check for yarn/npm workspaces in package.json
  python3 -c "
import sys, json
try:
    pkg = json.load(open('package.json'))
    workspaces = pkg.get('workspaces', [])
    if isinstance(workspaces, dict):
        workspaces = workspaces.get('packages', [])
    if workspaces:
        print('Workspaces:')
        for w in workspaces:
            print(f'  - {w}')
except: pass
" 2>/dev/null
fi

if [ -f "package.json" ]; then
  echo "Platform: Node.js"
  echo "Dependencies:"
  if command -v jq &>/dev/null; then
    jq -r '
      (.dependencies // {}) + (.devDependencies // {}) |
      to_entries[] |
      select(.key | test("^(next|react|vue|svelte|angular|astro|express|fastify|hono|remix|nuxt|typescript|tailwindcss|prisma|drizzle-orm|supabase|vitest|jest|playwright|cypress)$")) |
      "  \(.key): \(.value)"
    ' package.json 2>/dev/null || echo "  (could not parse with jq)"
  elif command -v python3 &>/dev/null; then
    cat package.json | python3 -c "
import sys, json
try:
    pkg = json.load(sys.stdin)
    deps = {**pkg.get('dependencies', {}), **pkg.get('devDependencies', {})}
    key_frameworks = ['next', 'react', 'vue', 'svelte', 'angular', 'astro', 'express', 'fastify', 'hono', 'remix', 'nuxt']
    key_tools = ['typescript', 'tailwindcss', 'prisma', 'drizzle-orm', 'supabase', 'vitest', 'jest', 'playwright', 'cypress']
    found = [k for k in deps if k in key_frameworks + key_tools]
    for f in found:
        print(f'  {f}: {deps[f]}')
    if not found:
        for k, v in list(deps.items())[:15]:
            print(f'  {k}: {v}')
except:
    print('  (could not parse package.json)')
" 2>/dev/null
  else
    echo "  (neither jq nor python3 available)"
  fi
fi

if [ -f "tsconfig.json" ]; then
  echo "TypeScript config:"
  if command -v jq &>/dev/null; then
    jq -r '.compilerOptions | "  target: \(.target // "not set"), module: \(.module // "not set"), strict: \(.strict // "not set")"' tsconfig.json 2>/dev/null || echo "  (could not parse tsconfig.json)"
  else
    echo "  (tsconfig.json present, install jq for details)"
  fi
fi

if [ -f "pyproject.toml" ]; then
  echo "Platform: Python"
  head -20 pyproject.toml
fi

if [ -f "Cargo.toml" ]; then
  echo "Platform: Rust"
  head -20 Cargo.toml
fi

if [ -f "go.mod" ]; then
  echo "Platform: Go"
  head -10 go.mod
fi

if [ -f "bun.lockb" ] || [ -f "bunfig.toml" ]; then
  echo "Runtime: Bun"
fi

if [ -f "deno.json" ] || [ -f "deno.lock" ]; then
  echo "Runtime: Deno"
fi

if ls *.csproj &>/dev/null || ls *.sln &>/dev/null; then
  echo "Platform: .NET"
fi

if [ -f "pom.xml" ]; then
  echo "Platform: Java (Maven)"
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  echo "Platform: Java (Gradle)"
fi

# CLAUDE.md
echo ""
echo "--- CLAUDE.MD ---"
if [ -f "CLAUDE.md" ]; then
  head -50 CLAUDE.md
elif [ -f "../CLAUDE.md" ]; then
  head -50 ../CLAUDE.md
else
  echo "(none found)"
fi

# Configuration files
echo ""
echo "--- CONFIGURATION ---"
[ -f ".claude/CLAUDE.md" ] && echo "Claude Code: project CLAUDE.md found"
{ [ -f ".env.example" ] || [ -f ".env.template" ]; } && echo "Environment: .env template found"
{ [ -f ".eslintrc.js" ] || [ -f ".eslintrc.json" ] || [ -f "eslint.config.js" ] || [ -f "eslint.config.mjs" ]; } && echo "Linter: ESLint"
{ [ -f "biome.json" ] || [ -f "biome.jsonc" ]; } && echo "Linter: Biome"
{ [ -f ".prettierrc" ] || [ -f ".prettierrc.json" ] || [ -f "prettier.config.js" ]; } && echo "Formatter: Prettier"
{ [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; } && echo "Container: Docker"
[ -d ".github/workflows" ] && echo "CI/CD: GitHub Actions"
{ [ -f "wrangler.toml" ] || [ -f "wrangler.jsonc" ]; } && echo "Deploy: Cloudflare Workers"
[ -f "vercel.json" ] && echo "Deploy: Vercel"
[ -f "netlify.toml" ] && echo "Deploy: Netlify"

# Claude Code project detection
echo ""
echo "--- CLAUDE CODE ---"
if [ -d ".claude/skills" ]; then
  echo "Project skills:"
  for skill in .claude/skills/*/SKILL.md; do
    [ -f "$skill" ] && echo "  - $(dirname "$skill" | xargs basename)"
  done
fi

if [ -d ".claude/agents" ]; then
  echo "Custom agents:"
  for agent in .claude/agents/*.md; do
    [ -f "$agent" ] && echo "  - $(basename "$agent" .md)"
  done
fi

if [ -d ".claude/commands" ]; then
  echo "Custom commands:"
  for cmd in .claude/commands/*.md; do
    [ -f "$cmd" ] && echo "  - /$(basename "$cmd" .md)"
  done
fi

# Project structure
echo ""
echo "--- STRUCTURE ---"
if command -v tree &>/dev/null; then
  tree -L 2 -I 'node_modules|.git|dist|build|.next|__pycache__|.venv|target' --dirsfirst 2>/dev/null | head -40
else
  find . -maxdepth 2 -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' -not -path '*/.next/*' | sort | head -40
fi

# Recent git activity (what areas are active)
echo ""
echo "--- RECENT CHANGES ---"
if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  git log --oneline -5 2>/dev/null || echo "(no git history)"
  echo ""
  echo "Recently modified files:"
  git diff --name-only HEAD~5 HEAD 2>/dev/null | head -15 || echo "(insufficient history)"
else
  echo "(not a git repository)"
fi

# Test patterns
echo ""
echo "--- TEST PATTERNS ---"
if [ -f "vitest.config.ts" ] || [ -f "vitest.config.js" ]; then
  echo "Test runner: Vitest"
elif [ -f "jest.config.ts" ] || [ -f "jest.config.js" ]; then
  echo "Test runner: Jest"
elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
  echo "Test runner: pytest (likely)"
fi

# Count test files
TEST_COUNT=$(find . -name "*.test.*" -o -name "*.spec.*" -o -name "test_*" 2>/dev/null | wc -l | tr -d ' ')
echo "Test files found: $TEST_COUNT"

# Typecheck command detection
echo ""
echo "--- TYPECHECK COMMAND ---"
if [ -f "tsconfig.json" ]; then
  echo "npx tsc --noEmit"
elif [ -f "pyproject.toml" ]; then
  if grep -q 'mypy' pyproject.toml 2>/dev/null; then
    echo "mypy ."
  elif grep -q 'pyright' pyproject.toml 2>/dev/null; then
    echo "pyright"
  else
    echo "(no typecheck detected)"
  fi
elif [ -f "go.mod" ]; then
  echo "go vet ./..."
elif [ -f "Cargo.toml" ]; then
  echo "cargo check"
else
  echo "(no typecheck detected)"
fi

# Test command detection
echo ""
echo "--- TEST COMMAND ---"
TEST_CMD_FOUND=false
if [ -f "vitest.config.ts" ] || [ -f "vitest.config.js" ]; then
  echo "npx vitest run"
  TEST_CMD_FOUND=true
elif [ -f "jest.config.ts" ] || [ -f "jest.config.js" ]; then
  echo "npx jest"
  TEST_CMD_FOUND=true
elif [ -f "pytest.ini" ]; then
  echo "pytest"
  TEST_CMD_FOUND=true
elif [ -f "pyproject.toml" ] && grep -q 'pytest' pyproject.toml 2>/dev/null; then
  echo "pytest"
  TEST_CMD_FOUND=true
elif [ -f "Cargo.toml" ]; then
  echo "cargo test"
  TEST_CMD_FOUND=true
elif [ -f "go.mod" ]; then
  echo "go test ./..."
  TEST_CMD_FOUND=true
fi
if [ "$TEST_CMD_FOUND" = false ] && [ -f "package.json" ]; then
  TEST_SCRIPT=""
  if command -v jq &>/dev/null; then
    TEST_SCRIPT=$(jq -r '.scripts.test // ""' package.json 2>/dev/null)
  elif command -v python3 &>/dev/null; then
    TEST_SCRIPT=$(python3 -c "import json; pkg=json.load(open('package.json')); print(pkg.get('scripts',{}).get('test',''))" 2>/dev/null)
  fi
  if [ -n "$TEST_SCRIPT" ] && ! echo "$TEST_SCRIPT" | grep -q 'echo.*Error'; then
    echo "$TEST_SCRIPT"
    TEST_CMD_FOUND=true
  fi
fi
if [ "$TEST_CMD_FOUND" = false ]; then
  echo "(no test command detected)"
fi

# Build command detection
echo ""
echo "--- BUILD COMMAND ---"
BUILD_CMD_FOUND=false
if [ -f "package.json" ]; then
  BUILD_SCRIPT=""
  if command -v jq &>/dev/null; then
    BUILD_SCRIPT=$(jq -r '.scripts.build // ""' package.json 2>/dev/null)
  elif command -v python3 &>/dev/null; then
    BUILD_SCRIPT=$(python3 -c "import json; pkg=json.load(open('package.json')); print(pkg.get('scripts',{}).get('build',''))" 2>/dev/null)
  fi
  if [ -n "$BUILD_SCRIPT" ]; then
    echo "$BUILD_SCRIPT"
    BUILD_CMD_FOUND=true
  fi
fi
if [ "$BUILD_CMD_FOUND" = false ] && [ -f "Cargo.toml" ]; then
  echo "cargo build"
  BUILD_CMD_FOUND=true
elif [ "$BUILD_CMD_FOUND" = false ] && [ -f "go.mod" ]; then
  echo "go build ./..."
  BUILD_CMD_FOUND=true
fi
if [ "$BUILD_CMD_FOUND" = false ]; then
  echo "(no build command detected)"
fi

if [[ -f "$_PILOT_LIB" ]] && declare -f pilot_map &>/dev/null; then
  if [[ -f "${ROOT}/.srcpilot/db.sqlite" ]]; then
    echo ""
    echo "=== Project Structure (from index) ==="
    pilot_map 2>/dev/null || true
    echo ""
    echo "=== Most-Referenced Files ==="
    pilot_context_budget 2>/dev/null | head -15 || true
  fi
fi

echo ""
echo "=== END CONTEXT ==="
