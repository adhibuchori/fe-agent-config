/**
 * Unit tests for the frontend server bridge between hops: part of the payload contract (.claude/PAYLOAD-CONTRACT.md).
 * @vitest-environment node
 */
import { describe, expect, test } from 'vitest';
import { toBase64Url } from '@/lib/payload/base64url';
import {
  openFromBrowser,
  openFromUpstream,
  sealForBrowser,
  sealForUpstream,
} from '@/lib/payload/bridge';
import { openJson, parseEnvelope, sealJson } from '@/lib/payload/codec';
import {
  deriveSessionKey,
  generateEphemeralKeyPair,
  generateServerKeyJwk,
  importServerKeyPair,
} from '@/lib/payload/ecdh';
import { requestAad, responseAad } from '@/lib/payload/envelope';
import { createKeyRing } from '@/lib/payload/key-ring';
import type { EndpointMatch } from '@/lib/payload/policy';

const match: EndpointMatch = {
  method: 'POST',
  pattern: '/api/notes',
  encryption: 'strict',
  viaPrefix: false,
};
const server = await importServerKeyPair(await generateServerKeyJwk());
/* Test-only key material: 32 bytes of one value, never a real key. */
const ring = await createKeyRing([
  { value: `k1:${toBase64Url(new Uint8Array(32).fill(4))}`, name: 'TEST_KEY' },
]);

describe('the browser hop', () => {
  test('opens what a browser sealed, and seals an answer only that browser opens', async () => {
    const tab = await generateEphemeralKeyPair();
    const key = await deriveSessionKey(tab.privateKey, server.publicKey);
    const request = await sealJson(
      { title: 'x' },
      {
        key,
        kid: 'ecdh',
        aadFor: (kid, ts) => requestAad('POST', '/api/notes', kid, ts),
      },
    );
    const plain = await openFromBrowser(
      JSON.stringify(request),
      tab.publicKey,
      match,
      server.privateKey,
    );
    expect(JSON.parse(plain)).toEqual({ title: 'x' });

    const answer = await sealForBrowser('{"id":1}', tab.publicKey, match, 201, server.privateKey);
    const opened = await openJson(parseEnvelope(answer), {
      key,
      aadFor: (kid, ts) => responseAad(201, '/api/notes', kid, ts),
    });
    expect(opened).toEqual({ id: 1 });
  });

  test('refuses a sealed request that carried no ephemeral key', async () => {
    await expect(openFromBrowser('{}', null, match, server.privateKey)).rejects.toMatchObject({
      code: 'ENVELOPE_REQUIRED',
    });
  });
});

describe('the backend hop', () => {
  test('seals for the backend and opens its answer with the shared ring', async () => {
    const outbound = parseEnvelope(await sealForUpstream('{"q":1}', match, ring));
    expect(outbound.kid).toBe('k1');
    const received = await openJson(outbound, {
      key: ring.resolve(outbound.kid),
      aadFor: (kid, ts) => requestAad('POST', '/api/notes', kid, ts),
    });
    expect(received).toEqual({ q: 1 });

    const answer = await sealJson(
      { ok: true },
      {
        key: ring.primary.key,
        kid: 'k1',
        aadFor: (kid, ts) => responseAad(200, '/api/notes', kid, ts),
      },
    );
    expect(JSON.parse(await openFromUpstream(JSON.stringify(answer), match, 200, ring))).toEqual({
      ok: true,
    });
  });
});
