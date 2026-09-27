/**
 * Unit tests for the AES-256-GCM layer: part of the payload contract (.claude/PAYLOAD-CONTRACT.md).
 * @vitest-environment node
 */
import { describe, expect, test } from 'vitest';
import { importAesKey, open, randomIv, seal } from '@/lib/payload/aes-gcm';
import { utf8Bytes, utf8String } from '@/lib/payload/base64url';

const material = new Uint8Array(32).fill(7);

describe('aes-gcm', () => {
  test('seals and opens with the same key, nonce and AAD', async () => {
    const key = await importAesKey(material);
    const iv = randomIv();
    const sealed = await seal(key, iv, utf8Bytes('hello'), utf8Bytes('aad'));
    expect(sealed.length).toBe('hello'.length + 16);
    expect(utf8String(await open(key, iv, sealed, utf8Bytes('aad')))).toBe('hello');
  });

  test('refuses another AAD with the one opaque error', async () => {
    const key = await importAesKey(material);
    const iv = randomIv();
    const sealed = await seal(key, iv, utf8Bytes('hello'), utf8Bytes('aad'));
    await expect(open(key, iv, sealed, utf8Bytes('other'))).rejects.toThrow(
      'Payload authentication failed',
    );
  });

  test('refuses a nonce that is not 96 bits', async () => {
    const key = await importAesKey(material);
    const sealed = await seal(key, randomIv(), utf8Bytes('x'), utf8Bytes('aad'));
    await expect(open(key, new Uint8Array(16), sealed, utf8Bytes('aad'))).rejects.toThrow(
      'authentication',
    );
  });

  test('mints a fresh 12-byte nonce each time', () => {
    expect(randomIv().length).toBe(12);
    expect(randomIv()).not.toEqual(randomIv());
  });

  test('refuses key material that is not 32 bytes', async () => {
    await expect(importAesKey(new Uint8Array(16))).rejects.toThrow('received 16');
  });
});
