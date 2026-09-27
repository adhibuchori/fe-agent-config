/**
 * Unit tests for sealing and opening JSON envelopes: part of the payload contract (.claude/PAYLOAD-CONTRACT.md).
 * @vitest-environment node
 */
import { describe, expect, test } from 'vitest';
import { importAesKey, seal } from '@/lib/payload/aes-gcm';
import { toBase64Url, utf8Bytes } from '@/lib/payload/base64url';
import { openJson, parseEnvelope, sealJson } from '@/lib/payload/codec';
import { requestAad } from '@/lib/payload/envelope';

const key = await importAesKey(new Uint8Array(32).fill(3));
const aadFor = (kid: string, ts: number) => requestAad('POST', '/api/notes', kid, ts);

describe('sealJson and openJson', () => {
  test('round-trip a body through a version 1 envelope', async () => {
    const envelope = await sealJson({ title: 'x', n: 1 }, { key, kid: 'k1', aadFor });
    expect(envelope).toMatchObject({ v: 1, alg: 'A256GCM', kid: 'k1' });
    expect(await openJson(envelope, { key, aadFor })).toEqual({ title: 'x', n: 1 });
  });

  test('seal an absent body as null', async () => {
    const envelope = await sealJson(undefined, { key, kid: 'k1', aadFor });
    expect(await openJson(envelope, { key, aadFor })).toBeNull();
  });

  test('refuse a stale envelope before touching the cipher', async () => {
    const envelope = await sealJson({}, { key, kid: 'k1', aadFor });
    const later = envelope.ts + 10 * 60_000;
    await expect(openJson(envelope, { key, aadFor, now: later })).rejects.toMatchObject({
      code: 'ENVELOPE_EXPIRED',
    });
  });

  test('refuse an envelope bound to another route', async () => {
    const envelope = await sealJson({}, { key, kid: 'k1', aadFor });
    const other = (kid: string, ts: number) => requestAad('POST', '/api/other', kid, ts);
    await expect(openJson(envelope, { key, aadFor: other })).rejects.toMatchObject({
      code: 'ENVELOPE_REJECTED',
    });
  });

  test('refuse a field that is not base64 as tampered', async () => {
    const envelope = await sealJson({}, { key, kid: 'k1', aadFor });
    await expect(openJson({ ...envelope, iv: '***' }, { key, aadFor })).rejects.toMatchObject({
      code: 'ENVELOPE_REJECTED',
    });
  });

  test('refuse plaintext that is not JSON as a bad envelope', async () => {
    const iv = new Uint8Array(12).fill(1);
    const ts = Date.now();
    const ct = await seal(key, iv, utf8Bytes('not json'), aadFor('k1', ts));
    const envelope = {
      v: 1,
      alg: 'A256GCM' as const,
      kid: 'k1',
      iv: toBase64Url(iv),
      ct: toBase64Url(ct),
      ts,
    };
    await expect(openJson(envelope, { key, aadFor })).rejects.toMatchObject({
      code: 'ENVELOPE_MALFORMED',
    });
  });
});

describe('parseEnvelope', () => {
  test('reads a sealed body', async () => {
    const envelope = await sealJson({}, { key, kid: 'k1', aadFor });
    expect(parseEnvelope(JSON.stringify(envelope))).toEqual(envelope);
  });

  test('refuses a body that is not JSON, or JSON that is not an envelope', () => {
    expect(() => parseEnvelope('title=x')).toThrow('not a payload envelope');
    expect(() => parseEnvelope('{"title":"x"}')).toThrow('not a payload envelope');
  });
});
