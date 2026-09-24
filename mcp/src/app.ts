import { createMcpHandler } from '@modelcontextprotocol/server';
import { PACK } from './generated/pack.js';
import { createServer, SERVER_NAME, SERVER_VERSION } from './server.js';

export interface Env {
  /** When set, /mcp requires `Authorization: Bearer <AUTH_TOKEN>` (same as the previous worker). */
  AUTH_TOKEN?: string;
}

export const PUBLIC_URL = 'https://prompt-improver.oweninnes.com/mcp';

// One handler per isolate; it builds a fresh McpServer for every request.
const mcp = createMcpHandler(() => createServer(), {
  onerror: (error) => console.error('mcp:', error.message)
});

// Browser-based MCP clients need CORS. The server holds no user data, so any origin may call it;
// AUTH_TOKEN, when set, still gates every non-preflight request.
const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Expose-Headers': 'mcp-session-id, mcp-protocol-version'
};

const PREFLIGHT_HEADERS: Record<string, string> = {
  ...CORS_HEADERS,
  'Access-Control-Allow-Methods': 'POST, GET, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
    'content-type, accept, authorization, mcp-protocol-version, mcp-session-id, mcp-method, mcp-name, last-event-id',
  'Access-Control-Max-Age': '86400'
};

function withCors(response: Response): Response {
  const headers = new Headers(response.headers);
  for (const [k, v] of Object.entries(CORS_HEADERS)) headers.set(k, v);
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

function timingSafeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

async function route(request: Request, env: Env, url: URL): Promise<Response> {
  if (url.pathname === '/' || url.pathname === '/health') {
    return Response.json({
      ok: true,
      name: `${SERVER_NAME}-mcp`,
      version: SERVER_VERSION,
      skill_version: PACK.skillVersion,
      endpoint: '/mcp',
      tools: ['improve_prompt', 'validate_prompt']
    });
  }
  // The deprecated HTTP+SSE transport lived at /sse and /messages; say where to go instead of a bare 404.
  if (url.pathname === '/sse' || url.pathname === '/messages') {
    return Response.json(
      {
        error: 'The HTTP+SSE transport is not supported. Connect with the Streamable HTTP transport instead.',
        endpoint: PUBLIC_URL,
        transport: 'streamable-http'
      },
      { status: 410 }
    );
  }
  if (url.pathname !== '/mcp') return new Response('Not found', { status: 404 });
  if (env.AUTH_TOKEN) {
    const auth = request.headers.get('authorization') ?? '';
    if (!timingSafeEqual(auth, `Bearer ${env.AUTH_TOKEN}`)) {
      return new Response('Unauthorized', { status: 401, headers: { 'WWW-Authenticate': 'Bearer' } });
    }
  }
  return mcp.fetch(request);
}

export async function handleRequest(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  // Preflight is answered before the auth check: browsers never send credentials on it.
  if (request.method === 'OPTIONS') {
    const known = ['/', '/health', '/mcp'].includes(url.pathname);
    return new Response(null, { status: known ? 204 : 404, headers: known ? PREFLIGHT_HEADERS : CORS_HEADERS });
  }
  return withCors(await route(request, env, url));
}
