import { createMcpHandler } from '@modelcontextprotocol/server';
import { PACK } from './generated/pack.js';
import { createServer, SERVER_NAME, SERVER_VERSION } from './server.js';

export interface Env {
  /** When set, /mcp requires `Authorization: Bearer <AUTH_TOKEN>` (same as the previous worker). */
  AUTH_TOKEN?: string;
}

// One handler per isolate; it builds a fresh McpServer for every request.
const mcp = createMcpHandler(() => createServer(), {
  onerror: (error) => console.error('mcp:', error.message)
});

function timingSafeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

export async function handleRequest(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
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
  if (url.pathname !== '/mcp') return new Response('Not found', { status: 404 });
  if (env.AUTH_TOKEN) {
    const auth = request.headers.get('authorization') ?? '';
    if (!timingSafeEqual(auth, `Bearer ${env.AUTH_TOKEN}`)) {
      return new Response('Unauthorized', { status: 401, headers: { 'WWW-Authenticate': 'Bearer' } });
    }
  }
  return mcp.fetch(request);
}
