/**
 * Unit tests for the strict/off switch: part of the payload contract (.claude/PAYLOAD-CONTRACT.md).
 * @vitest-environment node
 */
import { describe, expect, test } from 'vitest';
import { resolveEncryptionMode } from '@/lib/payload/mode';

describe('resolveEncryptionMode', () => {
  test('the variable wins over the committed file', () => {
    expect(resolveEncryptionMode('strict', 'off', false)).toBe('strict');
    expect(resolveEncryptionMode(' OFF ', 'strict', false)).toBe('off');
  });

  test('the file decides when the variable is unset or blank', () => {
    expect(resolveEncryptionMode(undefined, 'off', false)).toBe('off');
    expect(resolveEncryptionMode('  ', 'off', false)).toBe('off');
  });

  test('strict when neither source says anything', () => {
    expect(resolveEncryptionMode(undefined, undefined, true)).toBe('strict');
  });

  test('refuses a value that is not a mode, naming its source', () => {
    expect(() => resolveEncryptionMode('none', undefined, false)).toThrow('PAYLOAD_MODE');
    expect(() => resolveEncryptionMode(undefined, 'lax', false)).toThrow('payload.config.json');
  });

  test('refuses off in production', () => {
    expect(() => resolveEncryptionMode('off', undefined, true)).toThrow('refused in production');
    expect(() => resolveEncryptionMode(undefined, 'off', true)).toThrow('refused in production');
  });
});
