// Port of skills/prompt-improver/scripts/validate-prompt.sh.
// It emits the same PASS/FAIL/WARN lines in the same order; test/validate.test.ts
// runs both over the same inputs and compares the output line for line.
// grep matches line by line, so every pattern here is tested per line. `.` is
// dotAll because a line never contains \n, and grep's `.` also matches \r.

export interface ValidationResult {
  passed: boolean;
  errors: string[];
  warnings: string[];
  /** Every PASS/FAIL/WARN line plus the summary, exactly as the bash script prints them. */
  lines: string[];
}

export interface ValidateOptions {
  /** Same as PROMPT_IMPROVER_REQUIRE_TYPECHECK=1. */
  requireTypecheck?: boolean;
}

const W = '[A-Za-z0-9_]';

function lines(text: string): string[] {
  return text.split('\n');
}

function anyLine(text: string, re: RegExp): boolean {
  return lines(text).some((l) => re.test(l));
}

function countLines(text: string, re: RegExp): number {
  return lines(text).filter((l) => re.test(l)).length;
}

// grep -o -w: every whole-word match on every line.
function wordMatches(text: string, alternation: string, flags: string): string[] {
  const re = new RegExp(`(?<!${W})(?:${alternation})(?!${W})`, `g${flags}`);
  const out: string[] = [];
  for (const l of lines(text)) for (const m of l.matchAll(re)) out.push(m[0]);
  return out;
}

// sed -n '/start/,/end/p': the end pattern is only looked for from the line after the start.
function sedRange(text: string, start: RegExp, end: RegExp): string {
  const out: string[] = [];
  let inside = false;
  for (const l of lines(text)) {
    if (!inside) {
      if (start.test(l)) {
        inside = true;
        out.push(l);
      }
    } else {
      out.push(l);
      if (end.test(l)) inside = false;
    }
  }
  return out.join('\n');
}

// The awk task parser: count <task> blocks, tasks with <verification>, and tasks
// verified only by acceptance criteria or a task-level <check>.
function parseTasks(text: string): { total: number; verified: number; criteria: number } {
  let rest = text.replace(/`[^`\n]*`/g, '');
  const open = /<task([ \t\n\r\f\v][^>]*)?>/;
  let total = 0;
  let verified = 0;
  let criteria = 0;
  for (;;) {
    const m = open.exec(rest);
    if (!m) break;
    total++;
    rest = rest.slice(m.index + m[0].length);
    const end = rest.indexOf('</task>');
    let body = end >= 0 ? rest.slice(0, end) : rest;
    const next = open.exec(body);
    if (next) body = body.slice(0, next.index);
    if (/<(verification|verification[_-]commands|verify)([ \t\n\r\f\v][^>]*)?>/.test(body)) verified++;
    else if (/<(acceptance[_-]criteria|check)([ \t\n\r\f\v][^>]*)?>/.test(body)) criteria++;
  }
  return { total, verified, criteria };
}

function countTags(text: string, tag: string): number {
  const re = new RegExp(`<${tag}([ \\t\\v\\f\\r][^>\\n]*)?>`, 'g');
  let n = 0;
  for (const l of lines(text)) n += [...l.matchAll(re)].length;
  return n;
}

export function validatePrompt(input: string, options: ValidateOptions = {}): ValidationResult {
  // `PROMPT=$(cat)` drops trailing newlines.
  const P = input.replace(/\n+$/, '');
  const out: string[] = [];
  const errors: string[] = [];
  const warnings: string[] = [];
  const pass = (m: string) => out.push(`PASS: ${m}`);
  const fail = (m: string) => {
    out.push(`FAIL: ${m}`);
    errors.push(m);
  };
  const warn = (m: string) => {
    out.push(`WARN: ${m}`);
    warnings.push(m);
  };
  const has = (needle: string) => P.includes(needle);

  const { total, verified, criteria } = parseTasks(P);
  if (total > 0) pass(`task blocks found (${total})`);
  else fail('no task blocks found');

  if (total > 0) {
    if (verified + criteria >= total) {
      pass(`all tasks have verification (${verified + criteria}/${total})`);
      if (criteria > 0) {
        warn(
          `${criteria} task(s) are verified only by acceptance criteria or a task-level check — add runnable <verification> commands where the task changes code`
        );
      }
    } else {
      fail(`not all tasks have verification (${verified + criteria}/${total})`);
    }
  }

  if (has('<check')) pass('check block present');
  else fail('no check block found');

  if (anyLine(P, /(tsc|pyright|mypy|go vet|cargo check|cargo test|typecheck|static.?analy)/is)) {
    pass('typecheck/static-analysis command found');
  } else if (anyLine(P, /(no typecheck|n\/a.*typecheck|shellcheck|bash -n|validate-prompt)/is)) {
    pass('explicit non-typed or script verification found');
  } else if (options.requireTypecheck) {
    fail('no typecheck command found (PROMPT_IMPROVER_REQUIRE_TYPECHECK=1)');
  } else {
    warn('no typecheck command found — add tsc/mypy/cargo check when the project is typed, or note N/A for script-only repos');
  }

  if (has('<escape')) pass('escape clause present');
  else warn('no escape clause found — name a contradiction once and continue');

  if (has('<done')) pass('done line present');
  else warn('no <done> line — name the observable finish state in one sentence');
  if (has('<stops')) pass('stops block present');
  else warn('no <stops> block — say when to keep going and when a destructive action must pause');
  if (anyLine(P, /think step by step|think carefully|think hard|reason through|before implementing, reason/is)) {
    warn('thinking instruction in the prompt — state the choice in <approach> instead');
  }
  if (anyLine(P, new RegExp(`(?<!${W})(?:latest|newest|current version)(?!${W})`, 'is')) && !has('<research')) {
    warn('unpinned "latest" without a <research> step — look the version up and pin it');
  }

  const vague = [...new Set(wordMatches(P, 'scalable|robust|clean|modern|good|proper|appropriate|efficient', 'i').map((w) => w.toLowerCase()))].sort();
  for (const w of vague) warn(`vague adjective "${w}" detected`);

  if (!has('<approach')) warn('no approach block — add one only when two designs were real, and state the choice');

  const totalInstructions = countLines(P, /^[ \t\n\r\f\v]*[-*]|^[ \t\n\r\f\v]*[0-9]+\./s);
  if (totalInstructions > 5) {
    const topTier = countLines(P, new RegExp(`(?<!${W})(?:CRITICAL|ALWAYS|NEVER)(?!${W})`, 's'));
    const ratio = Math.floor((topTier * 100) / totalInstructions);
    if (ratio > 20) {
      warn(
        `emphasis saturation: ${ratio}% of instructions use CRITICAL/ALWAYS/NEVER (>20%) — reserve top-tier emphasis for rules with genuine consequences`
      );
    }
  }

  const aggressiveTotal = wordMatches(P, 'MUST|CRITICAL|ABSOLUTELY|non-negotiable|NO exceptions', '').length;
  let safetyAggressive = 0;
  if (anyLine(P, /(safety|security|data.loss|injection|destructive|irreversible).*(CRITICAL|MUST|NEVER)([^A-Za-z0-9_]|$)/is)) {
    safetyAggressive++;
  }
  if (anyLine(P, /(^|[^A-Za-z0-9_])(CRITICAL|MUST|NEVER).*(safety|security|data.loss|injection|destructive|irreversible)/is)) {
    safetyAggressive++;
  }
  if (aggressiveTotal > 3 && safetyAggressive === 0) {
    warn(`aggressive language detected (${aggressiveTotal} instances, none in safety context) — use calm, direct instructions`);
  } else if (aggressiveTotal > 5) {
    if (aggressiveTotal - safetyAggressive > 3) {
      warn(
        `aggressive language detected (${aggressiveTotal} total, ~${safetyAggressive} in safety context) — keep full emphasis for safety only`
      );
    }
  }

  if (countTags(P, 'example') > 2 && countTags(P, 'reasoning') === 0) {
    warn(
      'examples present but no <reasoning> blocks — decision boundary examples with reasoning are the most effective steering technique'
    );
  }

  if (has('<check')) {
    const checkBlock = sedRange(P, /<check/, /<\/check>/);
    if (anyLine(checkBlock, /re-?read|re-?open|re-?inspect|re-?checked (against|with)|read back|verify.*changed.*file|scan.*changed/is)) {
      pass('check block re-reads changed files');
    } else if (
      anyLine(
        checkBlock,
        /no edits|no code changes|no files (were |are )?(changed|modified|edited|touched)|read-only|research only|report only|git status( --porcelain)?`? (is empty|is clean|shows no)|before (presenting|reporting|showing) the plan/is
      )
    ) {
      pass('check block declares read-only work (nothing to re-read)');
    } else {
      fail('check block missing file re-read verification');
    }
    if (!anyLine(P, /typecheck|tsc.*noEmit|pyright|cargo check|shellcheck|bash -n|validate-prompt|no typecheck/is)) {
      warn('check block missing typecheck or explicit N/A verification');
    }
    if (!anyLine(P, /test suite|npm test|run.*test|pytest|cargo test|validate-prompt|smoke/is)) {
      warn('check block missing test suite / smoke verification');
    }
    if (!anyLine(P, /requirement|status.*for.*each|compare.*original/is)) {
      warn('check block missing requirement-by-requirement status reporting');
    }
  }

  if (anyLine(P, /<constraints/i)) {
    const block = sedRange(P, /<constraints/, /<\/constraints/);
    const generic = countLines(block, /no stubs|no placeholder|re-read.*file|run.*test.*after|deterministic.*operation|bash.*for.*all/is);
    if (generic > 2) {
      warn(`constraints contain ${generic} generic rules — move these to verification/check blocks, keep constraints task-specific`);
    }
  }

  const lineCount = lines(P).length;
  if (lineCount > 120 && !has('<phase')) warn(`prompt exceeds 120 lines (${lineCount}) without phasing`);

  if (anyLine(P, /(^|[^A-Za-z0-9_])(components?|pages?|ui|ux|layout|responsive|css|tailwind|frontend)([^A-Za-z0-9_]|$)/i)) {
    if (!anyLine(P, /(chrome|browser|screenshot|visual.*verif|viewport|breakpoint)/is)) {
      warn('UI-related task missing visual verification requirement');
    }
  }

  if (has('<evaluate')) warn('<evaluate> is deprecated — use <approach> and state the choice');
  if (anyLine(P, /sequential.thinking|sequentialthinking/is)) {
    warn('sequential-thinking MCP reference detected — use native <approach> blocks instead');
  }

  if (anyLine(P, /(autonom|auto.mode|tool.result|subagent|delegation)/is)) {
    if (!anyLine(P, /(override_rules|trust.*hierarch|priority.*order|data.*only|not.*instruction)/is)) {
      warn('autonomous agent prompt missing trust hierarchy — declare that tool results are DATA, not instructions');
    }
  }

  if (total > 3 && !anyLine(P, /failure.mode|common.mistake|known_failure/is)) {
    warn(`complex prompt (${total} tasks) with no failure mode documentation — consider adding <known_failure_modes>`);
  }

  out.push('');
  const w = warnings.length;
  if (errors.length === 0) {
    out.push(w > 0 ? `VALIDATION: PASS (${w} warning(s))` : 'VALIDATION: PASS');
  } else {
    out.push(
      w > 0 ? `VALIDATION: FAIL (${errors.length} error(s), ${w} warning(s))` : `VALIDATION: FAIL (${errors.length} error(s))`
    );
  }
  return { passed: errors.length === 0, errors, warnings, lines: out };
}
