// Single source for everything the page says. Components render this; nothing else defines it.

export const ENDPOINT = 'https://prompt-improver.oweninnes.com/mcp';
export const REPO = { href: 'https://github.com/owenob1/prompt-improver', label: 'github.com/owenob1/prompt-improver' };

export const META = {
  title: 'prompt-improver MCP',
  description: 'A remote MCP server that turns rough coding requests into checked XML specs.'
};

export const HERO = {
  title: 'prompt-improver',
  lead: 'Turns a rough coding request into a precise, checkable spec before any work starts.',
  detail: 'A remote MCP server. It never calls a model: the agent you already use writes the spec, and the server supplies the rules and checks the result.',
  meta: ['MCP 2026-07-28', 'Stateless', 'No sign-in']
};

export const SETUP = {
  claudeCode: `claude mcp add --transport http prompt-improver ${ENDPOINT}`,
  // Five lines: the nesting stays readable and the panel stays close to the others in height
  // (the tab area reserves the tallest one).
  json: `{
  "mcpServers": {
    "prompt-improver": { "type": "http", "url": "${ENDPOINT}" }
  }
}`,
  chatSteps: [
    'In Claude, ChatGPT or Grok, open the connector settings and add a custom (remote) MCP server.',
    'Paste the endpoint URL.',
    'Leave authentication off. The server keeps no data and calls no paid APIs.'
  ]
};

export const STEPS = [
  { title: 'improve_prompt', body: 'Send the request as written. You get the rules a spec must follow, and a handle.' },
  { title: 'Write the spec', body: 'Your agent writes the XML spec from those rules, without starting the work.' },
  { title: 'validate_prompt', body: 'The server checks it and says what next: fix it, show it to you, or carry it out.' }
];

export const SURFACES = [
  { name: 'improve_prompt', kind: 'Tool', text: 'Returns the generation instructions and a handle for the request.' },
  { name: 'validate_prompt', kind: 'Tool', text: 'Checks a spec and returns the next step.' },
  { name: 'improve', kind: 'Prompt', text: 'A slash command that starts the loop.' },
  { name: 'skill://prompt-improver/SKILL.md', kind: 'Skill', text: 'The same workflow and its references, for clients that load skills over MCP.' }
];

// Request and response shapes: the JSON-RPC messages as they go over the wire, taken from the live
// server's output (long values shortened with …). JSONC, so an elided run can say what it stands for.
const HANDLE = 'eyJ2IjoxLCJtb2RlIjoicGxhbiIs…';
const json = (value: unknown) => JSON.stringify(value, null, 2);
const call = (id: number, name: string, args: object) =>
  json({ jsonrpc: '2.0', id, method: 'tools/call', params: { name, arguments: args } });
const MORE = '"__more__"';

export const API = [
  {
    name: 'improve_prompt',
    summary:
      'Send the request exactly as the user wrote it. Leave mode out and the server asks the user, or defaults to plan when the client cannot ask.',
    request: call(1, 'improve_prompt', {
      request: 'Add a dark mode toggle to the settings page',
      mode: 'plan',
      context: 'Optional. Facts from package.json, CLAUDE.md, recent git log.'
    }),
    responseNote: 'Text only: a short header, then the generation instructions (about 75 KB), then links to the references.',
    response: json({
      jsonrpc: '2.0',
      id: 1,
      result: {
        content: [
          {
            type: 'text',
            text: `handle: ${HANDLE}\nmode: plan\nnext_step: Write the XML spec by following these instructions, then call validate_prompt …`
          },
          { type: 'text', text: '<the generation instructions: rules, template, worked examples, your request as data>' },
          {
            type: 'resource_link',
            uri: 'skill://prompt-improver/references/xml-template.md',
            name: 'references/xml-template.md',
            mimeType: 'text/markdown'
          },
          '__more__'
        ]
      }
    }).replace(MORE, '// … 4 more resource_link items, one per reference file')
  },
  {
    name: 'validate_prompt',
    summary:
      'Send the spec your agent wrote, without code fences, and the handle from the previous call. Every call returns a new handle; after three failed attempts the server says to stop.',
    request: call(2, 'validate_prompt', { xml: '<context>…</context> … <check>…</check>', handle: HANDLE }),
    responseNote: 'Structured JSON, with the validator report as text alongside.',
    response: json({
      jsonrpc: '2.0',
      id: 2,
      result: {
        content: [{ type: 'text', text: 'VALIDATION: FAIL (1 error(s), 1 warning(s))\n…' }],
        structuredContent: {
          passed: false,
          errors: ['no check block found'],
          warnings: ['no escape clause found — name a contradiction once and continue'],
          attempt: 1,
          mode: 'plan',
          handle: HANDLE,
          next_step: 'Fix exactly the errors above, change nothing else, and call validate_prompt again with the new handle.'
        }
      }
    })
  }
];

export const NEXT_STEPS = [
  { when: 'Errors', then: 'Fix only the listed errors and validate again with the new handle.' },
  { when: 'Third failure', then: 'Stop and show the spec and its errors to the user.' },
  { when: 'Passed, plan', then: 'Show the spec to the user and stop.' },
  { when: 'Passed, execute', then: 'Carry out the spec, then run its check block.' }
];
