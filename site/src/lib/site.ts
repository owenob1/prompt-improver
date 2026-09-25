// Single source for everything the page says. Components render this; nothing else defines it.

export const ENDPOINT = 'https://prompt-improver.oweninnes.com/mcp';
export const REPO = { href: 'https://github.com/owenob1/prompt-improver', label: 'github.com/owenob1/prompt-improver' };

export const META = {
  title: 'prompt-improver MCP',
  description: 'A remote MCP server that turns rough coding requests into checked XML specs.'
};

export const HERO = {
  badges: ['MCP 2026-07-28', 'No model calls', 'Stateless'],
  title: 'prompt-improver',
  lead: 'A remote MCP server that turns a rough coding request into a precise, checkable XML spec before any work starts. It never calls a model itself: the agent you already use writes the spec, and the server supplies the rules and checks the result.'
};

export const SETUP = {
  claudeCode: `claude mcp add --transport http prompt-improver ${ENDPOINT}`,
  // One spaced line, so the tab panels stay close in height (the tab area reserves the tallest one).
  json: `{ "mcpServers": { "prompt-improver": { "type": "http", "url": "${ENDPOINT}" } } }`,
  chatSteps: [
    'In Claude, ChatGPT or Grok, open the connector settings and add a custom (remote) MCP server.',
    'Paste the endpoint URL.',
    'Leave authentication off. The server keeps no data and calls no paid APIs.'
  ]
};

export const STEPS = [
  {
    title: 'improve_prompt',
    body: 'Send the request as written. The server returns the rules a spec must follow, plus a handle. Plan mode shows you the spec first; execute mode carries it out once it passes.'
  },
  { title: 'Write the spec', body: 'Your own agent writes the XML spec from those rules. It does not start the work yet.' },
  {
    title: 'validate_prompt',
    body: 'The server checks the spec and says what happens next: fix and check again (up to three times), show it to you, or carry it out.'
  }
];

export const SURFACES = [
  { name: 'improve_prompt', kind: 'Tool', text: 'Returns the generation instructions and a handle for the request.' },
  { name: 'validate_prompt', kind: 'Tool', text: 'Checks a spec and returns the next step.' },
  { name: 'improve', kind: 'Prompt', text: 'A slash command that starts the loop.' },
  { name: 'skill://prompt-improver/SKILL.md', kind: 'Skill', text: 'The same workflow and its references, for clients that load skills over MCP.' }
];
