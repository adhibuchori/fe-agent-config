/**
 * Unit tests for browser key agreement: part of the payload contract (.claude/PAYLOAD-CONTRACT.md).
 * @vitest-environment node
 */
import { describe, expect, test } from 'vitest';
import { open, randomIv, seal } from '@/lib/payload/aes-gcm';
import { fromBase64Url, toBase64Url, utf8Bytes, utf8String } from '@/lib/payload/base64url';
import {
  deriveSessionKey,
  generateEphemeralKeyPair,
  generateServerKeyJwk,
  importServerKeyPair,
} from '@/lib/payload/ecdh';

const aad = utf8Bytes('aad');
const encode = (value: unknown) => toBase64Url(utf8Bytes(JSON.stringify(value)));

describe('key agreement', () => {
  test('two sides derive the same key without sending it', async () => {
    const browser = await generateEphemeralKeyPair();
    const server = await importServerKeyPair(await generateServerKeyJwk());
    const browserKey = await deriveSessionKey(browser.privateKey, server.publicKey);
    const serverKey = await deriveSessionKey(server.privateKey, browser.publicKey);
    const iv = randomIv();
    const sealed = await seal(browserKey, iv, utf8Bytes('hi'), aad);
    expect(utf8String(await open(serverKey, iv, sealed, aad))).toBe('hi');
  });

  test('refuses a peer key that is not a P-256 point', async () => {
    const browser = await generateEphemeralKeyPair();
    await expect(
      deriveSessionKey(browser.privateKey, toBase64Url(new Uint8Array(65))),
    ).rejects.toMatchObject({
      code: 'ENVELOPE_MALFORMED',
    });
  });
});

describe('importServerKeyPair', () => {
  test('refuses text that is not base64url JSON', async () => {
    await expect(importServerKeyPair('***')).rejects.toThrow('not base64url JWK text');
    await expect(importServerKeyPair(toBase64Url(utf8Bytes('{')))).rejects.toThrow(
      'not base64url JWK text',
    );
  });

  test('refuses JSON that is not a JWK object', async () => {
    await expect(importServerKeyPair(encode(null))).rejects.toThrow('not a JWK object');
  });

  test('names the field a JWK is missing', async () => {
    const text = utf8String(fromBase64Url(await generateServerKeyJwk()));
    const partial = { ...(JSON.parse(text) as Record<string, string>), d: '' };
    await expect(importServerKeyPair(encode(partial))).rejects.toThrow('with "d"');
  });
});
