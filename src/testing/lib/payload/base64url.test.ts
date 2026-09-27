/**
 * Unit tests for base64url and UTF-8 helpers: part of the payload contract (.claude/PAYLOAD-CONTRACT.md).
 * @vitest-environment node
 */
import { describe, expect, test } from 'vitest';
import { fromBase64Url, toBase64Url, utf8Bytes, utf8String } from '@/lib/payload/base64url';

describe('base64url', () => {
  test('round-trips bytes without padding or URL-unsafe characters', () => {
    const bytes = new Uint8Array([251, 255, 191, 0, 1, 62, 63]);
    const encoded = toBase64Url(bytes);
    expect(encoded).not.toMatch(/[+/=]/);
    expect([...fromBase64Url(encoded)]).toEqual([...bytes]);
  });

  test('encodes a body larger than one chunk', () => {
    const bytes = new Uint8Array(70_000).map((_, i) => i % 256);
    expect(fromBase64Url(toBase64Url(bytes)).length).toBe(70_000);
  });

  test('accepts standard base64 with padding, as a person pastes it', () => {
    expect(utf8String(fromBase64Url(' aGk/Pz4+ \n'))).toBe('hi??>>');
    expect(utf8String(fromBase64Url('aGk='))).toBe('hi');
  });

  test('refuses a value that is not base64 at all', () => {
    expect(() => fromBase64Url('***')).toThrow('Malformed base64url value');
  });

  test('round-trips UTF-8 text', () => {
    expect(utf8String(utf8Bytes('café 東京 ✓'))).toBe('café 東京 ✓');
  });
});
