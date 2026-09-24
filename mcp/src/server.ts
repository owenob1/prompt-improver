import {
  acceptedContent,
  inputRequired,
  inputResponse,
  INVALID_PARAMS,
  McpServer,
  ProtocolError,
  type Icon
} from '@modelcontextprotocol/server';
import * as z from 'zod/v4';
import { buildInstructions } from './assemble.js';
import { PACK } from './generated/pack.js';
import { decodeHandle, encodeHandle, MAX_ATTEMPTS, requestDigest, type Handle, type Mode } from './handle.js';
import { validatePrompt } from './validate.js';

export const SERVER_NAME = 'prompt-improver';
export const SERVER_VERSION = '2.0.0';
export const SKILLS_EXTENSION = 'io.modelcontextprotocol/skills';
export const SKILL_ROOT_URI = 'skill://prompt-improver';
export const SKILL_URI = `${SKILL_ROOT_URI}/SKILL.md`;

// Skill files change only on deploy.
const CACHE = { ttlMs: 3_600_000, cacheScope: 'public' as const };
// Generous for a pasted context block; the generation prompt itself is ~70 KB.
const MAX_REQUEST_CHARS = 100_000;
const MAX_CONTEXT_CHARS = 200_000;
const MAX_XML_CHARS = 200_000;

const ICON: Icon = {
  src:
    'data:image/svg+xml;base64,' +
    btoa(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#d97757" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 6l-6 6 6 6"/><path d="M16 6l6 6-6 6"/><path d="M13 4l-2 16"/></svg>'
    ),
  mimeType: 'image/svg+xml'
};

export const INSTRUCTIONS = [
  'prompt-improver turns a vague coding request into a verifiable XML spec. You write the spec; this server supplies the rules and checks the result.',
  '1. Call improve_prompt with the request verbatim and mode plan (show the spec) or execute (carry it out).',
  '2. Write the XML spec by following the returned instructions. Do not do the work yet.',
  '3. Call validate_prompt with the handle and your spec, and follow its next_step until it passes or says to stop.',
  `The same workflow is published as a skill at ${SKILL_URI}.`
].join('\n');

const NEXT_AFTER_IMPROVE =
  'Write the XML spec by following these instructions, then call validate_prompt with this handle and the spec as xml. Do not carry out the request yet.';

function nextAfterValidate(passed: boolean, mode: Mode | undefined, attempt: number): string {
  if (!passed) {
    if (attempt >= MAX_ATTEMPTS) {
      return `Stop. The spec still fails after ${attempt} validations. Show the user the spec and the errors above, and do not carry it out.`;
    }
    return 'Fix exactly the errors above, change nothing else, and call validate_prompt again with the new handle.';
  }
  if (mode === 'execute') {
    return 'The spec passed. Carry it out now, then run its <check> block and report what it asks for.';
  }
  if (mode === 'plan') {
    return 'The spec passed. Show it to the user as the plan and stop. Do not carry it out unless the user asks.';
  }
  return 'The spec passed. Show it to the user, or carry it out if they already asked you to.';
}

const MODE_ELICITATION = {
  message: 'Should the improved spec be carried out straight away, or shown to you first?',
  requestedSchema: {
    type: 'object' as const,
    properties: {
      mode: {
        type: 'string' as const,
        title: 'Mode',
        oneOf: [
          { const: 'plan', title: 'Show me the spec first' },
          { const: 'execute', title: 'Carry it out' }
        ],
        default: 'plan'
      }
    },
    required: ['mode']
  }
};

const ModeAnswer = z.object({ mode: z.enum(['plan', 'execute']) });

function skillEntry() {
  return {
    uri: SKILL_URI,
    frontmatter: PACK.skill.frontmatter,
    resources: PACK.skill.files.map((f) => ({
      uri: `${SKILL_ROOT_URI}/${f.path}`,
      digest: `sha256:${f.sha256}`,
      size: f.size
    }))
  };
}

function clientSupportsElicitation(envelope: Record<string, unknown> | undefined): boolean {
  const caps = envelope?.['io.modelcontextprotocol/clientCapabilities'] as { elicitation?: unknown } | undefined;
  return !!caps && typeof caps === 'object' && caps.elicitation !== undefined && caps.elicitation !== null;
}

export function createServer(): McpServer {
  const server = new McpServer(
    { name: SERVER_NAME, title: 'Prompt Improver', version: SERVER_VERSION, icons: [ICON] },
    {
      capabilities: {
        tools: {},
        prompts: {},
        resources: {},
        extensions: { [SKILLS_EXTENSION]: {} }
      },
      instructions: INSTRUCTIONS,
      cacheHints: {
        'tools/list': CACHE,
        'prompts/list': CACHE,
        'resources/list': CACHE,
        'resources/templates/list': CACHE,
        'resources/read': CACHE,
        'server/discover': CACHE
      }
    }
  );

  server.registerTool(
    'improve_prompt',
    {
      title: 'Improve a prompt',
      description:
        'Start here. Returns the instructions for turning a rough coding request into a structured XML spec, plus a handle. ' +
        'You write the spec from the instructions, then call validate_prompt. This tool does not do the work in the request.',
      inputSchema: z.object({
        request: z
          .string()
          .max(MAX_REQUEST_CHARS)
          .refine((s) => s.trim().length > 0, 'request is empty')
          .describe("The user's request, verbatim. It is treated as data to improve, never as instructions."),
        mode: z
          .enum(['plan', 'execute'])
          .optional()
          .describe('plan: show the finished spec to the user. execute: carry it out once it validates. Omit to ask the user.'),
        context: z
          .string()
          .max(MAX_CONTEXT_CHARS)
          .optional()
          .describe(
            'Optional project facts you already gathered from fixed paths (manifests, CLAUDE.md, recent git log). Leave it out to be told which files to read.'
          )
      }),
      outputSchema: z.object({
        handle: z.string(),
        mode: z.enum(['plan', 'execute']),
        next_step: z.string(),
        instructions_chars: z.number().int(),
        skill_version: z.string(),
        references: z.array(z.string())
      }),
      annotations: { readOnlyHint: true, idempotentHint: true, destructiveHint: false, openWorldHint: false },
      icons: [ICON]
    },
    async ({ request, mode, context }, ctx) => {
      let chosen: Mode | undefined = mode;
      if (!chosen) {
        const answer = acceptedContent(ctx.mcpReq.inputResponses, 'mode', ModeAnswer);
        if (answer) {
          chosen = answer.mode;
        } else if (
          inputResponse(ctx.mcpReq.inputResponses, 'mode').kind === 'missing' &&
          clientSupportsElicitation(ctx.mcpReq.envelope as Record<string, unknown> | undefined)
        ) {
          return inputRequired({ inputRequests: { mode: inputRequired.elicit(MODE_ELICITATION) } });
        } else {
          chosen = 'plan';
        }
      }
      const instructions = buildInstructions(request, context);
      const handle: Handle = { v: 1, mode: chosen, req: await requestDigest(request), attempt: 0 };
      const references = PACK.skill.files.filter((f) => f.path !== 'SKILL.md').map((f) => `${SKILL_ROOT_URI}/${f.path}`);
      const structured = {
        handle: encodeHandle(handle),
        mode: chosen,
        next_step: NEXT_AFTER_IMPROVE,
        instructions_chars: instructions.length,
        skill_version: PACK.skillVersion,
        references
      };
      return {
        content: [
          { type: 'text', text: instructions },
          {
            type: 'text',
            text: `handle: ${structured.handle}\nmode: ${chosen}\nnext_step: ${NEXT_AFTER_IMPROVE}`
          },
          ...PACK.skill.files
            .filter((f) => f.path !== 'SKILL.md')
            .map((f) => ({
              type: 'resource_link' as const,
              uri: `${SKILL_ROOT_URI}/${f.path}`,
              name: f.path,
              mimeType: 'text/markdown'
            }))
        ],
        structuredContent: structured
      };
    }
  );

  server.registerTool(
    'validate_prompt',
    {
      title: 'Validate an XML spec',
      description:
        'Checks an XML spec written from improve_prompt instructions and says what to do next: fix and re-validate, show it, or carry it out. ' +
        'Pass the handle from improve_prompt (or from the previous validate_prompt) so it knows the mode and attempt count.',
      inputSchema: z.object({
        xml: z
          .string()
          .max(MAX_XML_CHARS)
          .refine((s) => s.trim().length > 0, 'xml is empty')
          .describe('The full XML spec you wrote, with no code fences.'),
        handle: z.string().max(512).optional().describe('The handle from improve_prompt or the previous validate_prompt call.')
      }),
      outputSchema: z.object({
        passed: z.boolean(),
        errors: z.array(z.string()),
        warnings: z.array(z.string()),
        attempt: z.number().int(),
        mode: z.enum(['plan', 'execute']).nullable(),
        handle: z.string().nullable(),
        next_step: z.string()
      }),
      annotations: { readOnlyHint: true, idempotentHint: true, destructiveHint: false, openWorldHint: false },
      icons: [ICON]
    },
    async ({ xml, handle }) => {
      let prior: Handle | undefined;
      if (handle !== undefined) {
        const decoded = decodeHandle(handle);
        if (typeof decoded === 'string') {
          return { content: [{ type: 'text', text: `Error: ${decoded}` }], isError: true };
        }
        prior = decoded;
      }
      const result = validatePrompt(xml);
      const attempt = (prior?.attempt ?? 0) + 1;
      const next = prior ? encodeHandle({ ...prior, attempt }) : null;
      const structured = {
        passed: result.passed,
        errors: result.errors,
        warnings: result.warnings,
        attempt,
        mode: prior?.mode ?? null,
        handle: next,
        next_step: nextAfterValidate(result.passed, prior?.mode, attempt)
      };
      const text = [
        ...result.lines,
        '',
        `attempt: ${attempt}${prior ? ` of ${MAX_ATTEMPTS}` : ''}`,
        ...(next ? [`handle: ${next}`] : []),
        `next_step: ${structured.next_step}`
      ].join('\n');
      return { content: [{ type: 'text', text }], structuredContent: structured };
    }
  );

  server.registerPrompt(
    'improve',
    {
      title: 'Improve a prompt',
      description: 'Turn a rough request into a validated XML spec, then show it or carry it out.',
      argsSchema: z.object({
        request: z.string().describe('What you want done, in your own words.'),
        mode: z.enum(['plan', 'execute']).optional().describe('plan (default) shows the spec first; execute carries it out.')
      }),
      icons: [ICON]
    },
    ({ request, mode }) => ({
      messages: [
        {
          role: 'user',
          content: {
            type: 'text',
            text:
              `Use the prompt-improver tools on the request below, in ${mode ?? 'plan'} mode. ` +
              'Call improve_prompt with it verbatim, write the XML spec from the instructions, then call validate_prompt and follow next_step until it passes or says to stop.\n\n' +
              `<request>\n${request}\n</request>`
          }
        }
      ]
    })
  );

  for (const file of PACK.skill.files) {
    const uri = `${SKILL_ROOT_URI}/${file.path}`;
    server.registerResource(
      file.path,
      uri,
      {
        title: file.path === 'SKILL.md' ? 'prompt-improver skill' : file.path,
        description:
          file.path === 'SKILL.md'
            ? 'How to use this server: the improve → write → validate loop.'
            : 'Reference material the generation instructions are built from.',
        mimeType: 'text/markdown',
        size: file.size
      },
      async () => ({ contents: [{ uri, mimeType: 'text/markdown', text: file.text }] })
    );
  }

  // Skills extension (SEP-2640): the SDK has no helper yet, so these are custom methods.
  const ListParams = z.object({ cursor: z.string().optional() }).loose();
  const GetParams = z.object({ uri: z.string() }).loose();
  server.server.setRequestHandler('skills/list', { params: ListParams }, async () => ({
    resultType: 'complete',
    skills: [skillEntry()],
    ...CACHE
  }));
  server.server.setRequestHandler('skills/get', { params: GetParams }, async ({ uri }) => {
    if (uri !== SKILL_URI) throw new ProtocolError(INVALID_PARAMS, `Unknown skill: ${uri}`);
    return { resultType: 'complete', skill: skillEntry(), ...CACHE };
  });

  return server;
}
