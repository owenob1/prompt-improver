import { DurableObject } from 'cloudflare:workers';
import { handleRequest, type Env } from './app.js';

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, env);
  }
} satisfies ExportedHandler<Env>;

/**
 * Kept only so this deploy replaces the previous prompt-improver-mcp worker,
 * which bound a `PromptSession` Durable Object, without a class-deletion
 * migration. The server is stateless and never uses it. Remove it later with a
 * `deleted_classes: ["PromptSession"]` migration.
 */
export class PromptSession extends DurableObject {
  async fetch(): Promise<Response> {
    return new Response('Gone', { status: 410 });
  }
}
