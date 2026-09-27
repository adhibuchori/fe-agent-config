/**
 * Unit tests for pre-shared key rings: part of the payload contract (.claude/PAYLOAD-CONTRACT.md).
 * @vitest-environment node
 */
import { describe, expect, test } from 'vitest';
import { toBase64Url } from '@/lib/payload/base64url';
import { createKeyRing } from '@/lib/payload/key-ring';

/* Placeholder material for tests only: 32 bytes of one value, never a real key. */
const keyOf = (fill: number) => toBase64Url(new Uint8Array(32).fill(fill));

describe('createKeyRing', () => {
  test('seals with the first configured key and accepts every one', async () => {
    const ring = await createKeyRing([
      { value: `k1:${keyOf(1)}`, name: 'PAYLOAD_KEY' },
      { value: `k2:${keyOf(2)}`, name: 'PAYLOAD_KEY_NEXT' },
    ]);
    expect(ring.primary.kid).toBe('k1');
    expect(ring.kids).toEqual(['k1', 'k2']);
    expect(ring.resolve('k2')).toBeDefined();
  });

  test('skips an unset rotation slot, and takes standard base64 with padding', async () => {
    const padded = btoa(String.fromCharCode(...new Uint8Array(32).fill(9)));
    const ring = await createKeyRing([
      { value: `k1:${padded}`, name: 'A' },
      { value: undefined, name: 'A_NEXT' },
      { value: '  ', name: 'A_OTHER' },
    ]);
    expect(ring.kids).toEqual(['k1']);
  });

  test('refuses a kid it does not hold with a named code', async () => {
    const ring = await createKeyRing([{ value: `k1:${keyOf(1)}`, name: 'A' }]);
    expect(() => ring.resolve('k9')).toThrow('No payload key with id "k9"');
  });

  test('refuses to start with no key, naming the first variable', async () => {
    await expect(createKeyRing([{ value: '', name: 'PAYLOAD_KEY' }])).rejects.toThrow(
      'set PAYLOAD_KEY',
    );
    await expect(createKeyRing([])).rejects.toThrow('set a payload key');
  });

  test.each([
    ['no separator', keyOf(1)],
    ['an empty kid', `:${keyOf(1)}`],
    ['a kid with spaces', `my key:${keyOf(1)}`],
    ['the reserved kid', `ecdh:${keyOf(1)}`],
  ])('refuses %s', async (_name, value) => {
    await expect(createKeyRing([{ value, name: 'A' }])).rejects.toThrow(
      'A must be "kid:base64key"',
    );
  });

  test('refuses key material that is not base64, or not 32 bytes', async () => {
    await expect(createKeyRing([{ value: 'k1:***', name: 'A' }])).rejects.toThrow('not base64');
    const short = toBase64Url(new Uint8Array(16));
    await expect(createKeyRing([{ value: `k1:${short}`, name: 'A' }])).rejects.toThrow(
      'A must decode to 32 bytes, received 16',
    );
  });

  test('refuses two keys that share a kid', async () => {
    await expect(
      createKeyRing([
        { value: `k1:${keyOf(1)}`, name: 'A' },
        { value: `k1:${keyOf(2)}`, name: 'B' },
      ]),
    ).rejects.toThrow('share the kid "k1"');
  });
});
