import { PACK } from './generated/pack.js';

const CLOSE = '</raw-request-to-improve';

/** Trailing newlines dropped and the wrapper's closing tag escaped, as the bash assembler does. */
export function normaliseRequest(request: string): string {
  return request.replace(/\n+$/, '').replaceAll(CLOSE, '<\\/raw-request-to-improve');
}

/**
 * The generation prompt, byte-identical to
 * `assemble-generation-prompt.sh --raw-input-file - [context-file]` run with no
 * user settings. `context` plays the part of the context file's contents.
 */
export function assembleGenerationPrompt(request: string, context?: string): string {
  const t = PACK.template;
  let contextBlock = '';
  if (context !== undefined && context !== '') {
    contextBlock =
      '=== DETERMINISTIC PROJECT CONTEXT (shell-gathered; use only this for repo facts) ===\n\n' +
      context +
      '\n' +
      '=== END DETERMINISTIC PROJECT CONTEXT ===\n\n' +
      'CRITICAL: Do NOT grep, glob, find, search, list, or explore the codebase. Use only the context block above for paths, stack, and commands.\n\n';
  }
  return t.head + contextBlock + t.tailBefore + normaliseRequest(request) + t.tailAfter;
}

/** What the calling agent is told to read when it did not pass context. */
export function probeInstructions(): string {
  return [
    '=== PROJECT CONTEXT (not supplied) ===',
    '',
    'No project context was passed. If you can read files in the project the request is about, read only these fixed paths from its root, skipping any that do not exist, plus `git log --oneline -5` and `git diff --name-only HEAD~5 HEAD`:',
    '',
    PACK.probes.join(' '),
    '',
    'For CLAUDE.md, AGENTS.md and .cursorrules read the first 40 lines. Do not grep, glob, find, list directories or explore beyond these paths. If you cannot read files, write the spec from the request alone and name what you could not confirm.',
    '',
    '=== END PROJECT CONTEXT ===',
    '',
    ''
  ].join('\n');
}

/** The full instructions handed to the calling agent by improve_prompt. */
export function buildInstructions(request: string, context?: string): string {
  if (context !== undefined && context !== '') return assembleGenerationPrompt(request, context);
  const t = PACK.template;
  return t.head + probeInstructions() + t.tailBefore + normaliseRequest(request) + t.tailAfter;
}
