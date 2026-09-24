import { handleRequest, type Env } from './app.js';

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, env);
  }
} satisfies ExportedHandler<Env>;
