/**
 * Unit tests for the payload error codes: part of the payload contract (.claude/PAYLOAD-CONTRACT.md).
 * @vitest-environment node
 */
import { describe, expect, test } from 'vitest';
import { isPayloadError, PAYLOAD_CODES, PayloadError } from '@/lib/payload/errors';

describe('PayloadError', () => {
  test('carries its code and name', () => {
    const error = new PayloadError('ENVELOPE_EXPIRED', 'too old');
    expect(error.code).toBe('ENVELOPE_EXPIRED');
    expect(error.name).toBe('PayloadError');
    expect(error.message).toBe('too old');
  });

  test('is told apart from any other thrown value', () => {
    expect(isPayloadError(new PayloadError('ENVELOPE_REJECTED', 'x'))).toBe(true);
    expect(isPayloadError(new Error('x'))).toBe(false);
    expect(isPayloadError('ENVELOPE_REJECTED')).toBe(false);
  });

  test('lists every code once', () => {
    expect(new Set(PAYLOAD_CODES).size).toBe(5);
  });
});
