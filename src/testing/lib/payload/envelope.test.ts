/**
 * Unit tests for the envelope shape, freshness and AAD builders: part of the payload contract (.claude/PAYLOAD-CONTRACT.md).
 * @vitest-environment node
 */
import { describe, expect, test } from 'vitest';
import { utf8String } from '@/lib/payload/base64url';
import {
  isFresh,
  isPayloadEnvelope,
  MAX_CLOCK_SKEW_MS,
  requestAad,
  responseAad,
} from '@/lib/payload/envelope';

const valid = { v: 1, alg: 'A256GCM', kid: 'k1', iv: 'aa', ct: 'bb', ts: 1_700_000_000_000 };

describe('isPayloadEnvelope', () => {
  test('accepts a well-formed version 1 envelope', () => {
    expect(isPayloadEnvelope(valid)).toBe(true);
  });

  test.each([
    ['null', null],
    ['a string', 'envelope'],
    ['another version', { ...valid, v: 2 }],
    ['another algorithm', { ...valid, alg: 'A128GCM' }],
    ['a missing kid', { ...valid, kid: undefined }],
    ['a numeric nonce', { ...valid, iv: 12 }],
    ['a numeric ciphertext', { ...valid, ct: 12 }],
    ['a fractional timestamp', { ...valid, ts: 1.5 }],
    ['a string timestamp', { ...valid, ts: '1' }],
  ])('refuses %s', (_name, value) => {
    expect(isPayloadEnvelope(value)).toBe(false);
  });
});

describe('isFresh', () => {
  const now = 1_700_000_000_000;

  test('accepts a timestamp inside the window, either side', () => {
    expect(isFresh(now - MAX_CLOCK_SKEW_MS, now)).toBe(true);
    expect(isFresh(now + MAX_CLOCK_SKEW_MS, now)).toBe(true);
  });

  test('refuses one outside it, in the past or the future', () => {
    expect(isFresh(now - MAX_CLOCK_SKEW_MS - 1, now)).toBe(false);
    expect(isFresh(now + MAX_CLOCK_SKEW_MS + 1, now)).toBe(false);
  });

  test('reads the clock when no time is given', () => {
    expect(isFresh(Date.now() - 1000)).toBe(true);
  });
});

describe('AAD builders', () => {
  test('bind the version, method, pattern, key id and time', () => {
    expect(utf8String(requestAad('post', '/api/notes/:id', 'k1', 5))).toBe(
      '1.POST./api/notes/:id.k1.5',
    );
    expect(utf8String(responseAad(201, '/api/notes', 'ecdh', 5))).toBe('1.201./api/notes.ecdh.5');
  });
});
