/**
 * A JSON body into an envelope and back: the one place that decides the order of operations.
 *
 * The AAD arrives as a builder because it contains the timestamp, and the timestamp is minted
 * here; a caller that built the AAD itself would also mint the time, and then two places would
 * decide what "now" means.
 */

import { open, randomIv, seal } from './aes-gcm';
import { fromBase64Url, toBase64Url, utf8Bytes, utf8String, type Bytes } from './base64url';
import {
  ENVELOPE_ALG,
  ENVELOPE_VERSION,
  isFresh,
  isPayloadEnvelope,
  type PayloadEnvelope,
} from './envelope';
import { PayloadError } from './errors';

/** Builds the AAD for a key id and the envelope's timestamp. */
export type AadBuilder = (kid: string, ts: number) => Bytes;

/** What sealing needs besides the body. */
export interface SealOptions {
  /** The AES-256-GCM key. */
  key: CryptoKey;
  /** The key id written into the envelope. */
  kid: string;
  /** Binds the ciphertext to its route; called with the kid and the new timestamp. */
  aadFor: AadBuilder;
}

/** What opening needs besides the envelope. */
export interface OpenOptions {
  /** The AES-256-GCM key. */
  key: CryptoKey;
  /** Must build the same AAD the sealing side built. */
  aadFor: AadBuilder;
  /** The current time; injectable for tests. */
  now?: number;
}

function decodeField(value: string): Bytes {
  try {
    return fromBase64Url(value);
  } catch {
    throw new PayloadError('ENVELOPE_REJECTED', 'Payload authentication failed');
  }
}

/** Lib: sealJson
 * Serialises a body and seals it into an envelope.
 */
export async function sealJson(body: unknown, options: SealOptions): Promise<PayloadEnvelope> {
  const ts = Date.now();
  const iv = randomIv();
  const plaintext = utf8Bytes(JSON.stringify(body === undefined ? null : body));
  const sealed = await seal(options.key, iv, plaintext, options.aadFor(options.kid, ts));
  return {
    v: ENVELOPE_VERSION,
    alg: ENVELOPE_ALG,
    kid: options.kid,
    iv: toBase64Url(iv),
    ct: toBase64Url(sealed),
    ts,
  };
}

/** Lib: openJson
 * Checks freshness, verifies, decrypts and parses. Freshness goes first: a replayed envelope then
 * costs a subtraction, not a key import and a GCM pass. Returns `unknown`; the caller that knows
 * the endpoint validates the shape.
 */
export async function openJson(envelope: PayloadEnvelope, options: OpenOptions): Promise<unknown> {
  if (!isFresh(envelope.ts, options.now)) {
    throw new PayloadError('ENVELOPE_EXPIRED', 'Payload envelope is outside the freshness window');
  }
  const plaintext = await open(
    options.key,
    decodeField(envelope.iv),
    decodeField(envelope.ct),
    options.aadFor(envelope.kid, envelope.ts),
  );
  try {
    return JSON.parse(utf8String(plaintext));
  } catch {
    throw new PayloadError('ENVELOPE_MALFORMED', 'Decrypted payload is not JSON');
  }
}

/** Lib: parseEnvelope
 * Reads an envelope out of a raw body, or refuses it as not encrypted.
 */
export function parseEnvelope(raw: string): PayloadEnvelope {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new PayloadError('ENVELOPE_REQUIRED', 'Body is not a payload envelope');
  }
  if (!isPayloadEnvelope(parsed)) {
    throw new PayloadError('ENVELOPE_REQUIRED', 'Body is not a payload envelope');
  }
  return parsed;
}
