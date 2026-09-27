/**
 * Unit tests for the browser transport calls: part of the payload contract (.claude/PAYLOAD-CONTRACT.md).
 * @vitest-environment node
 */
import { afterEach, describe, expect, test, vi } from 'vitest';
import { createBrowserPayload } from '@/lib/payload/client';
import { openJson, parseEnvelope, sealJson } from '@/lib/payload/codec';
import { deriveSessionKey, generateServerKeyJwk, importServerKeyPair } from '@/lib/payload/ecdh';
import { ENCRYPTED_MEDIA_TYPE, EPK_HEADER, requestAad, responseAad } from '@/lib/payload/envelope';
import type { EndpointMatch } from '@/lib/payload/policy';

const server = await importServerKeyPair(await generateServerKeyJwk());
const strict: EndpointMatch = {
  method: 'POST',
  pattern: '/api/notes',
  encryption: 'strict',
  viaPrefix: false,
};
const none: EndpointMatch = { ...strict, encryption: 'none' };
const requestOnly: EndpointMatch = { ...strict, encryption: 'request-only' };
const responseOnly: EndpointMatch = { ...strict, encryption: 'response-only' };

/* A handshake route answering with `answer`, counting how often it is asked. */
function handshake(answer: unknown, status = 200) {
  const calls = { count: 0 };
  const fetch = vi.fn(async () => {
    calls.count += 1;
    return new Response(JSON.stringify(answer), { status });
  });
  return { calls, fetch };
}

function browser(answer: unknown = { publicKey: server.publicKey, mode: 'strict' }, status = 200) {
  const hs = handshake(answer, status);
  return {
    payload: createBrowserPayload({ handshakeUrl: '/api/payload/handshake', fetch: hs.fetch }),
    calls: hs.calls,
  };
}

/* What the server does with a sealed request: derive the key from the header and open it. */
async function serverOpens(body: string, epk: string): Promise<unknown> {
  const key = await deriveSessionKey(server.privateKey, epk);
  return openJson(parseEnvelope(body), {
    key,
    aadFor: (kid, ts) => requestAad('POST', '/api/notes', kid, ts),
  });
}

async function serverSeals(value: unknown, epk: string, status: number): Promise<string> {
  const key = await deriveSessionKey(server.privateKey, epk);
  const envelope = await sealJson(value, {
    key,
    kid: 'ecdh',
    aadFor: (kid, ts) => responseAad(status, '/api/notes', kid, ts),
  });
  return JSON.stringify(envelope);
}

afterEach(() => vi.unstubAllGlobals());

describe('seal', () => {
  test('seals a JSON body and sends the ephemeral key, which the server can open', async () => {
    const { payload } = browser();
    const out = await payload.seal(strict, '{"title":"x"}');
    expect(out.active).toBe(true);
    expect(out.headers['content-type']).toBe(ENCRYPTED_MEDIA_TYPE);
    expect(await serverOpens(out.body ?? '', out.headers[EPK_HEADER] ?? '')).toEqual({
      title: 'x',
    });
  });

  test('never seals FormData, and seals nothing on a response-only route, but still sends the key', async () => {
    const { payload } = browser();
    const form = await payload.seal(strict, 'multipart', true);
    expect(form).toMatchObject({ body: 'multipart', active: true });
    expect(form.headers['content-type']).toBeUndefined();
    expect((await payload.seal(responseOnly, '{}')).body).toBe('{}');
    expect((await payload.seal(strict, null)).headers[EPK_HEADER]).toBeDefined();
    expect((await payload.seal(requestOnly, '{"a":1}')).body).toContain('"ct"');
  });

  test('asks nothing of the server on a none route, and follows it when it says off', async () => {
    const { payload, calls } = browser();
    expect(await payload.seal(none, '{}')).toEqual({ body: '{}', headers: {}, active: false });
    expect(calls.count).toBe(0);
    const off = browser({ publicKey: server.publicKey, mode: 'off' }).payload;
    expect(await off.seal(strict, '{}')).toEqual({ body: '{}', headers: {}, active: false });
  });

  test('runs one handshake for requests that race for it', async () => {
    const { payload, calls } = browser();
    await Promise.all([payload.seal(strict, null), payload.seal(strict, null)]);
    expect(calls.count).toBe(1);
  });

  test('forgets a failed handshake so the next request tries again', async () => {
    const { payload, calls } = browser({}, 503);
    await expect(payload.seal(strict, null)).rejects.toMatchObject({
      code: 'ENVELOPE_KEY_UNKNOWN',
    });
    await expect(payload.seal(strict, null)).rejects.toThrow('answered 503');
    expect(calls.count).toBe(2);
    await expect(browser(null).payload.seal(strict, null)).rejects.toThrow('no public key');
    await expect(browser({ publicKey: '' }).payload.seal(strict, null)).rejects.toThrow(
      'no public',
    );
  });

  test('uses the global fetch when none is given', async () => {
    const hs = handshake({ publicKey: server.publicKey });
    vi.stubGlobal('fetch', hs.fetch);
    const payload = createBrowserPayload({ handshakeUrl: '/api/payload/handshake' });
    expect((await payload.seal(strict, null)).active).toBe(true);
    expect(hs.calls.count).toBe(1);
  });
});

describe('read', () => {
  test('opens a sealed answer', async () => {
    const { payload } = browser();
    const out = await payload.seal(strict, '{}');
    const body = await serverSeals({ id: 1 }, out.headers[EPK_HEADER] ?? '', 201);
    const read = await payload.read(
      strict,
      { status: 201, contentType: ENCRYPTED_MEDIA_TYPE, body },
      true,
    );
    expect(read).toEqual({ id: 1 });
  });

  test('reads plaintext where nothing was sealed', async () => {
    const { payload } = browser();
    const plain = { status: 200, contentType: 'application/json', body: '{"a":1}' };
    expect(await payload.read(strict, plain, false)).toEqual({ a: 1 });
    expect(await payload.read(requestOnly, plain, true)).toEqual({ a: 1 });
    expect(await payload.read(none, { ...plain, body: 'text' }, false)).toBe('text');
  });

  test('accepts a plaintext refusal or an empty body, and refuses a plaintext success', async () => {
    const { payload } = browser();
    const problem = { status: 400, contentType: 'application/problem+json', body: '{"code":"X"}' };
    expect(await payload.read(strict, problem, true)).toEqual({ code: 'X' });
    expect(await payload.read(strict, { status: 200, contentType: '', body: '' }, true)).toBeNull();
    await expect(
      payload.read(strict, { status: 200, contentType: 'application/json', body: '{}' }, true),
    ).rejects.toMatchObject({ code: 'ENVELOPE_REQUIRED' });
  });

  test('renegotiates after an answer its key cannot verify, but not after a malformed one', async () => {
    const { payload, calls } = browser();
    const out = await payload.seal(strict, '{}');
    const body = await serverSeals({ id: 1 }, out.headers[EPK_HEADER] ?? '', 200);
    const sealed = { status: 201, contentType: ENCRYPTED_MEDIA_TYPE, body };
    await expect(payload.read(strict, { ...sealed, body: 'x' }, true)).rejects.toMatchObject({
      code: 'ENVELOPE_REQUIRED',
    });
    await payload.seal(strict, null);
    expect(calls.count).toBe(1);
    await expect(payload.read(strict, sealed, true)).rejects.toMatchObject({
      code: 'ENVELOPE_REJECTED',
    });
    await payload.seal(strict, null);
    expect(calls.count).toBe(2);
  });

  test('reset drops the agreed key', async () => {
    const { payload, calls } = browser();
    await payload.seal(strict, null);
    payload.reset();
    await payload.seal(strict, null);
    expect(calls.count).toBe(2);
  });
});
