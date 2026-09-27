/**
 * The wire format: what an envelope is, and what its ciphertext is bound to.
 *
 * One shape for requests and responses and for every hop. Two envelopes that drifted apart are
 * two services that can no longer talk, failing with an authentication error that says nothing
 * about why, so every constant here has a twin in each other implementation of the contract
 * (.claude/PAYLOAD-CONTRACT.md § Wire format) and the shared test vectors compare them.
 */

import { utf8Bytes, type Bytes } from './base64url';

/** The media type of a sealed body. Not `application/json`, so a proxy, a log filter or a
 * middleware can tell an envelope from plaintext without parsing it. */
export const ENCRYPTED_MEDIA_TYPE = 'application/vnd.payload-envelope+json';

/** Bumped only for a breaking change. An unknown version is refused, never guessed at. */
export const ENVELOPE_VERSION = 1;

/** The one algorithm version 1 defines. */
export const ENVELOPE_ALG = 'A256GCM';

/** Browser hops only: the caller's ephemeral P-256 public key, on every request with or without a
 * body. A GET has no envelope, and the server still needs the key to seal the response. */
export const EPK_HEADER = 'x-payload-epk';

/** Server-to-server hops: which pre-shared key the caller holds, so a bodiless request can still
 * be answered under the right key. A key id is public; it selects a key and is not one. */
export const KID_HEADER = 'x-payload-kid';

/** How far apart two clocks may be, either way, before an envelope is refused. Short enough that
 * a captured envelope stops being useful quickly, long enough for a container's clock drift. It
 * is not replay protection on its own: that would need a nonce store and shared state. */
export const MAX_CLOCK_SKEW_MS = 120_000;

/** A sealed body as it travels. */
export interface PayloadEnvelope {
  /** Format version; equals `ENVELOPE_VERSION`. */
  v: number;
  /** Always `A256GCM` in version 1. */
  alg: typeof ENVELOPE_ALG;
  /** Which key sealed it: a pre-shared key's id, or `ecdh` for a key agreed with a browser. */
  kid: string;
  /** Base64url 96-bit nonce, fresh for every encryption. */
  iv: string;
  /** Base64url ciphertext with the 16-byte tag appended (the WebCrypto and `cryptography` layout). */
  ct: string;
  /** Epoch milliseconds when it was sealed. Milliseconds, not seconds. */
  ts: number;
}

/** Lib: isPayloadEnvelope
 * Whether a parsed value is a well-formed envelope of a version this build reads. Shape only.
 */
export function isPayloadEnvelope(value: unknown): value is PayloadEnvelope {
  if (typeof value !== 'object' || value === null) return false;
  return (
    'v' in value &&
    value.v === ENVELOPE_VERSION &&
    'alg' in value &&
    value.alg === ENVELOPE_ALG &&
    'kid' in value &&
    typeof value.kid === 'string' &&
    'iv' in value &&
    typeof value.iv === 'string' &&
    'ct' in value &&
    typeof value.ct === 'string' &&
    'ts' in value &&
    typeof value.ts === 'number' &&
    Number.isSafeInteger(value.ts)
  );
}

/** Lib: isFresh
 * Whether a timestamp sits inside the window. A future timestamp is refused too: accepting it
 * would let an attacker post-date an envelope for as long as they liked.
 */
export function isFresh(ts: number, now: number = Date.now()): boolean {
  return Math.abs(now - ts) <= MAX_CLOCK_SKEW_MS;
}

/** Lib: requestAad
 * The authenticated data that binds a request envelope to its method and registry pattern.
 * The pattern (`/api/items/:id`), not the concrete URL, so both sides agree without sharing a URL
 * normaliser; the cost, an envelope replayable across ids of one route inside the window, is
 * accepted and written down in the contract.
 */
export function requestAad(method: string, pattern: string, kid: string, ts: number): Bytes {
  return utf8Bytes(`${ENVELOPE_VERSION}.${method.toUpperCase()}.${pattern}.${kid}.${ts}`);
}

/** Lib: responseAad
 * The authenticated data that binds a response envelope to its status and pattern, so a 200 body
 * cannot be replayed as the body of a 403. The status itself stays on the status line, in clear.
 */
export function responseAad(status: number, pattern: string, kid: string, ts: number): Bytes {
  return utf8Bytes(`${ENVELOPE_VERSION}.${status}.${pattern}.${kid}.${ts}`);
}
