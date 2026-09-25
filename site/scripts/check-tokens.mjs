#!/usr/bin/env node
// Enforces the token-only rule for the page's own code (src/ outside components/ui, which is
// shadcn's generated source). Spacing and type come from the @theme tokens in global.css; colour
// from the shadcn colour tokens. Anything else is a violation.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../src', import.meta.url));
const SKIP = [join(ROOT, 'components/ui'), join(ROOT, 'styles/global.css')];
const EXT = /\.(astro|tsx|ts|jsx|js|css)$/;

// Utilities are matched only where a class name can start: after whitespace, a quote, a backtick or a variant colon.
const START = String.raw`(?<=[\s"'\`:])`;
const RULES = [
  { name: 'arbitrary value', re: /-\[[^\]]*\]/ },
  { name: 'hex colour', re: /#[0-9a-fA-F]{3,8}\b/ },
  { name: 'raw colour function', re: /\b(?:rgb|rgba|hsl|hsla|oklch|oklab|lab|lch)\(/ },
  { name: 'inline style', re: /\sstyle=/ },
  {
    name: 'numeric spacing (use a spacing token)',
    re: new RegExp(
      `${START}-?(?:p|px|py|pt|pb|pl|pr|ps|pe|m|mx|my|mt|mb|ml|mr|ms|me|gap|gap-x|gap-y|space-x|space-y)-(?:\\d|px\\b)`
    )
  },
  { name: 'default type size (use a type token)', re: new RegExp(`${START}text-(?:xs|sm|base|lg|\\d?xl)\\b`) }
];

function files(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (SKIP.some((s) => path === s || path.startsWith(s + '/'))) return [];
    return statSync(path).isDirectory() ? files(path) : EXT.test(name) ? [path] : [];
  });
}

const violations = [];
for (const file of files(ROOT)) {
  readFileSync(file, 'utf8')
    .split('\n')
    .forEach((line, i) => {
      for (const rule of RULES) {
        const m = line.match(rule.re);
        if (m) violations.push(`${relative(process.cwd(), file)}:${i + 1}  ${rule.name}: ${m[0].trim()}`);
      }
    });
}

if (violations.length) {
  console.error(`check:tokens found ${violations.length} violation(s):\n${violations.join('\n')}`);
  process.exit(1);
}
console.log('check:tokens: page code uses tokens only');
