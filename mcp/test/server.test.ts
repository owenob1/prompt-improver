// End-to-end over the Worker's fetch entry, speaking 2026-07-28 JSON-RPC.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { describe, expect, test } from 'vitest';
import { handleRequest, type Env } from '../src/app.js';
import { decodeHandle, encodeHandle } from '../src/handle.js';

const SKILL = resolve(__dirname, '../../skills/prompt-improver');
const VALID = readFileSync(join(SKILL, 'examples/fixtures/valid-prompt.xml'), 'utf8');
const INVALID = readFileSync(join(SKILL, 'examples/fixtures/invalid-prompt.xml'), 'utf8');

type Json = Record<string, any>;

function meta(elicitation: boolean): Json {
  return {
    'io.modelcontextprotocol/protocolVersion': '2026-07-28',
    'io.modelcontextprotocol/clientInfo': { name: 'test', version: '1.0.0' },
    'io.modelcontextprotocol/clientCapabilities': elicitation ? { elicitation: { form: {} } } : {}
  };
}

async function rpc(method: string, params: Json = {}, opts: { elicitation?: boolean; env?: Env; auth?: string } = {}): Promise<Json> {
  const headers: Record<string, string> = {
    'content-type': 'application/json',
    accept: 'application/json, text/event-stream',
    'mcp-method': method,
    'mcp-protocol-version': '2026-07-28'
  };
  const name = params.name ?? params.uri;
  if (typeof name === 'string') headers['mcp-name'] = name;
  if (opts.auth) headers.authorization = opts.auth;
  const res = await handleRequest(
    new Request('https://example.test/mcp', {
      method: 'POST',
      headers,
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params: { ...params, _meta: meta(opts.elicitation ?? false) } })
    }),
    opts.env ?? {}
  );
  expect(res.status).toBe(200);
  return (await res.json()) as Json;
}

const call = (name: string, args: Json, opts: { elicitation?: boolean } = {}) => rpc('tools/call', { name, arguments: args }, opts);

describe('discovery', () => {
  test('server/discover advertises tools, prompts, resources and the skills extension', async () => {
    const { result } = await rpc('server/discover');
    expect(result.supportedVersions).toContain('2026-07-28');
    expect(result.capabilities.extensions).toEqual({ 'io.modelcontextprotocol/skills': {} });
    expect(result.capabilities.resources).toBeDefined();
    expect(result.instructions).toContain('validate_prompt');
    expect(result.resultType).toBe('complete');
  });

  test('tools/list is ordered, typed and cacheable', async () => {
    const { result } = await rpc('tools/list');
    expect(result.tools.map((t: Json) => t.name)).toEqual(['improve_prompt', 'validate_prompt']);
    for (const t of result.tools) {
      expect(t.outputSchema).toBeDefined();
      expect(t.annotations.readOnlyHint).toBe(true);
      expect(t.icons.length).toBe(1);
    }
    expect(result.ttlMs).toBeGreaterThan(0);
    expect(result.cacheScope).toBe('public');
  });

  test('prompts/get improve names both tools', async () => {
    const { result } = await rpc('prompts/get', { name: 'improve', arguments: { request: 'add a flag', mode: 'execute' } });
    const text = result.messages[0].content.text as string;
    expect(text).toContain('execute mode');
    expect(text).toContain('improve_prompt');
    expect(text).toContain('validate_prompt');
  });
});

describe('improve → validate loop', () => {
  test('without mode, an elicitation-capable client is asked, and the retry completes', async () => {
    const first = await call('improve_prompt', { request: 'add a --json flag' }, { elicitation: true });
    expect(first.result.resultType).toBe('input_required');
    expect(first.result.inputRequests.mode.method).toBe('elicitation/create');

    const retry = await rpc(
      'tools/call',
      {
        name: 'improve_prompt',
        arguments: { request: 'add a --json flag' },
        inputResponses: { mode: { action: 'accept', content: { mode: 'execute' } } }
      },
      { elicitation: true }
    );
    expect(retry.result.resultType).toBe('complete');
    expect(retry.result.structuredContent.mode).toBe('execute');
  });

  test('a declined elicitation falls back to plan', async () => {
    const retry = await rpc(
      'tools/call',
      { name: 'improve_prompt', arguments: { request: 'add a flag' }, inputResponses: { mode: { action: 'decline' } } },
      { elicitation: true }
    );
    expect(retry.result.structuredContent.mode).toBe('plan');
  });

  test('without elicitation support, mode defaults to plan and the instructions are returned', async () => {
    const { result } = await call('improve_prompt', { request: 'add a --json flag to export' });
    expect(result.resultType).toBe('complete');
    const s = result.structuredContent;
    expect(s.mode).toBe('plan');
    expect(s.next_step).toContain('validate_prompt');
    expect(result.content[0].text).toContain('<raw-request-to-improve>\nadd a --json flag to export\n</raw-request-to-improve>');
    expect(result.content[0].text.length).toBe(s.instructions_chars);
    expect(result.content.filter((c: Json) => c.type === 'resource_link').length).toBe(s.references.length);
    const handle = decodeHandle(s.handle);
    expect(handle).toMatchObject({ mode: 'plan', attempt: 0 });
  });

  test('fail → fix → pass, with next_step per mode', async () => {
    const improved = await call('improve_prompt', { request: 'fix settings', mode: 'execute' });
    let handle = improved.result.structuredContent.handle as string;

    const bad = await call('validate_prompt', { handle, xml: INVALID });
    expect(bad.result.structuredContent.passed).toBe(false);
    expect(bad.result.structuredContent.errors.length).toBeGreaterThan(0);
    expect(bad.result.structuredContent.next_step).toContain('Fix exactly the errors');
    expect(bad.result.structuredContent.attempt).toBe(1);
    handle = bad.result.structuredContent.handle;

    const good = await call('validate_prompt', { handle, xml: VALID });
    expect(good.result.structuredContent.passed).toBe(true);
    expect(good.result.structuredContent.attempt).toBe(2);
    expect(good.result.structuredContent.next_step).toContain('Carry it out now');

    const plan = await call('improve_prompt', { request: 'fix settings', mode: 'plan' });
    const planned = await call('validate_prompt', { handle: plan.result.structuredContent.handle, xml: VALID });
    expect(planned.result.structuredContent.next_step).toContain('stop');
  });

  test('stops after three failed validations', async () => {
    const handle = encodeHandle({ v: 1, mode: 'execute', req: '0123456789abcdef', attempt: 2 });
    const { result } = await call('validate_prompt', { handle, xml: INVALID });
    expect(result.structuredContent.attempt).toBe(3);
    expect(result.structuredContent.next_step).toMatch(/^Stop\./);
    expect(result.structuredContent.next_step).toContain('do not carry it out');
  });

  test('validate_prompt works without a handle', async () => {
    const { result } = await call('validate_prompt', { xml: VALID });
    expect(result.structuredContent).toMatchObject({ passed: true, mode: null, handle: null });
  });

  test('a garbage handle is a tool error, not a crash', async () => {
    const { result } = await call('validate_prompt', { handle: 'not!a!handle', xml: VALID });
    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain('not a prompt-improver handle');
    const forged = await call('validate_prompt', { handle: Buffer.from('{"v":1,"mode":"yolo"}').toString('base64url'), xml: VALID });
    expect(forged.result.isError).toBe(true);
  });

  test('an empty request is rejected', async () => {
    const res = await call('improve_prompt', { request: '   ' });
    expect(res.error ?? res.result?.isError).toBeTruthy();
  });
});

describe('skills extension', () => {
  test('skills/list manifest digests match the bytes resources/read serves', async () => {
    const { result } = await rpc('skills/list');
    expect(result.resultType).toBe('complete');
    expect(result.cacheScope).toBe('public');
    const [skill] = result.skills;
    expect(skill.uri).toBe('skill://prompt-improver/SKILL.md');
    expect(skill.frontmatter.name).toBe('prompt-improver');
    for (const file of skill.resources) {
      const read = await rpc('resources/read', { uri: file.uri });
      const text = read.result.contents[0].text as string;
      const bytes = Buffer.from(text, 'utf8');
      expect(bytes.length).toBe(file.size);
      expect(`sha256:${createHash('sha256').update(bytes).digest('hex')}`).toBe(file.digest);
    }
  });

  test('SKILL.md frontmatter matches the listed frontmatter', async () => {
    const read = await rpc('resources/read', { uri: 'skill://prompt-improver/SKILL.md' });
    const text = read.result.contents[0].text as string;
    expect(text.startsWith('---\nname: prompt-improver\n')).toBe(true);
  });

  test('skills/get returns the entry, and an unknown URI is -32602', async () => {
    const ok = await rpc('skills/get', { uri: 'skill://prompt-improver/SKILL.md' });
    expect(ok.result.skill.uri).toBe('skill://prompt-improver/SKILL.md');
    const missing = await rpc('skills/get', { uri: 'skill://other/SKILL.md' });
    expect(missing.error.code).toBe(-32602);
    const file = await rpc('resources/read', { uri: 'skill://prompt-improver/missing.md' });
    expect(file.error.code).toBe(-32602);
  });
});

describe('http surface', () => {
  test('health', async () => {
    const res = await handleRequest(new Request('https://example.test/health'), {});
    const body = (await res.json()) as Json;
    expect(body).toMatchObject({ ok: true, endpoint: '/mcp' });
    expect((await handleRequest(new Request('https://example.test/nope'), {})).status).toBe(404);
  });

  test('AUTH_TOKEN gates /mcp when set', async () => {
    const env = { AUTH_TOKEN: 's3cret' };
    const denied = await handleRequest(new Request('https://example.test/mcp', { method: 'POST', body: '{}' }), env);
    expect(denied.status).toBe(401);
    const wrong = await handleRequest(
      new Request('https://example.test/mcp', { method: 'POST', body: '{}', headers: { authorization: 'Bearer nope' } }),
      env
    );
    expect(wrong.status).toBe(401);
    const ok = await rpc('tools/list', {}, { env, auth: 'Bearer s3cret' });
    expect(ok.result.tools.length).toBe(2);
  });

  test('a 2025-era client is served statelessly', async () => {
    const res = await handleRequest(
      new Request('https://example.test/mcp', {
        method: 'POST',
        headers: { 'content-type': 'application/json', accept: 'application/json, text/event-stream' },
        body: JSON.stringify({
          jsonrpc: '2.0',
          id: 1,
          method: 'initialize',
          params: { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'old', version: '1' } }
        })
      }),
      {}
    );
    expect(res.status).toBe(200);
    const text = await res.text();
    expect(text).toContain('"protocolVersion":"2025-11-25"');
    expect(text).toContain('prompt-improver');
  });
});
