// The improve → validate loop is stateless: the server mints a handle, the
// agent passes it back to validate_prompt, and each validation returns the next
// one. It is not a security boundary (the caller could equally pick a mode or
// skip validation), so it is plain base64url JSON, checked for shape only.

export type Mode = 'plan' | 'execute';

export interface Handle {
  v: 1;
  mode: Mode;
  /** First 16 hex chars of sha256(request), to tie a validation to its request in logs. */
  req: string;
  /** Validations already made with this loop. */
  attempt: number;
}

export const MAX_ATTEMPTS = 3;

function b64urlEncode(text: string): string {
  const bytes = new TextEncoder().encode(text);
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function b64urlDecode(text: string): string {
  const b64 = text.replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4));
  return new TextDecoder().decode(Uint8Array.from(bin, (c) => c.charCodeAt(0)));
}

export async function requestDigest(request: string): Promise<string> {
  const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(request));
  return [...new Uint8Array(hash)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
    .slice(0, 16);
}

export function encodeHandle(h: Handle): string {
  return b64urlEncode(JSON.stringify(h));
}

/** Returns the handle, or an error message naming what is wrong with it. */
export function decodeHandle(raw: string): Handle | string {
  if (raw.length > 512 || !/^[A-Za-z0-9_-]+$/.test(raw)) return 'handle is not a prompt-improver handle';
  let data: unknown;
  try {
    data = JSON.parse(b64urlDecode(raw));
  } catch {
    return 'handle is not a prompt-improver handle';
  }
  const h = data as Partial<Handle> | null;
  if (
    !h ||
    h.v !== 1 ||
    (h.mode !== 'plan' && h.mode !== 'execute') ||
    typeof h.req !== 'string' ||
    !/^[0-9a-f]{16}$/.test(h.req) ||
    typeof h.attempt !== 'number' ||
    !Number.isInteger(h.attempt) ||
    h.attempt < 0 ||
    h.attempt > 100
  ) {
    return 'handle is malformed; call improve_prompt again to get a new one';
  }
  return { v: 1, mode: h.mode, req: h.req, attempt: h.attempt };
}
