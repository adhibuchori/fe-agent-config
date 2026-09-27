/**
 * Unit tests for this copy against the shared test vectors: part of the payload contract (.claude/PAYLOAD-CONTRACT.md).
 * @vitest-environment node
 */
import { describe, expect, test } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { importAesKey, open } from '@/lib/payload/aes-gcm';
import { fromBase64Url, utf8Bytes, utf8String } from '@/lib/payload/base64url';
import { requestAad, responseAad } from '@/lib/payload/envelope';

/**
 * The conformance half of the payload contract: this implementation against the shared test
 * vectors that every other implementation (the frontend's copy, a Python service) also reads.
 * A failure means this copy changed; never regenerate the vectors to make it pass.
 */

interface Vector {
  name: string;
  kind: 'request' | 'response';
  method?: string;
  status?: number;
  pattern: string;
  kid: string;
  ts: number;
  plaintext: unknown;
  aad: string;
  iv: string;
  ct: string;
}

interface Vectors {
  testBytes: string;
  vectors: Vector[];
  rejects: { name: string; vector: string; aad: string }[];
}

const file: Vectors = JSON.parse(
  readFileSync(join(process.cwd(), 'scripts/check/payload-vectors.json'), 'utf8'),
);
const key = await importAesKey(fromBase64Url(file.testBytes));

function aadOf(vector: Vector): string {
  const bytes =
    vector.kind === 'request'
      ? requestAad(vector.method ?? '', vector.pattern, vector.kid, vector.ts)
      : responseAad(vector.status ?? 0, vector.pattern, vector.kid, vector.ts);
  return utf8String(bytes);
}

describe('payload test vectors', () => {
  for (const vector of file.vectors) {
    test(`${vector.name}: builds the same AAD, byte for byte`, () => {
      expect(aadOf(vector)).toBe(vector.aad);
    });

    test(`${vector.name}: opens the committed ciphertext`, async () => {
      const plaintext = await open(
        key,
        fromBase64Url(vector.iv),
        fromBase64Url(vector.ct),
        utf8Bytes(vector.aad),
      );
      expect(JSON.parse(utf8String(plaintext))).toEqual(vector.plaintext);
    });
  }

  for (const reject of file.rejects) {
    test(`refuses ${reject.name}`, async () => {
      const vector = file.vectors.find((candidate) => candidate.name === reject.vector);
      if (!vector) throw new Error(`no vector named ${reject.vector}`);
      await expect(
        open(key, fromBase64Url(vector.iv), fromBase64Url(vector.ct), utf8Bytes(reject.aad)),
      ).rejects.toThrow('Payload authentication failed');
    });
  }
});
