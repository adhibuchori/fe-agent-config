/**
 * Key agreement for the browser hop, where there is no secret the browser could hold.
 *
 * A static key in the bundle would be one key for every visitor, readable in the sources tab. The
 * server keeps a long-lived P-256 keypair instead, the browser mints an ephemeral one per tab, and
 * both derive the same AES key without it ever being sent. The browser's public key rides in the
 * `x-payload-epk` header of every request, so the server re-derives the key each time and stores
 * nothing: no session table, nothing to share behind a load balancer.
 *
 * This hides nothing from the person operating the browser, who holds the private key in a process
 * they control. It buys integrity and resistance to passive capture, not confidentiality from the
 * user: see .claude/PAYLOAD-CONTRACT.md § Threat model before describing it to anyone.
 */

import { fromBase64Url, toBase64Url, utf8Bytes } from './base64url';
import { PayloadError } from './errors';

const CURVE: EcKeyImportParams = { name: 'ECDH', namedCurve: 'P-256' };

/* Domain separation: a second protocol deriving keys from the same secret with another label can
   never produce this key. The version is in the label so a v2 schedule cannot collide with it. */
const HKDF_INFO = 'payload-envelope/v1/browser';

/** The `kid` of an envelope sealed under an agreed key; reserved, never a pre-shared key's id. */
export const ECDH_KID = 'ecdh';

/** A keypair: the public half as base64url raw point, the private half non-extractable. */
export interface EcdhKeyPair {
  publicKey: string;
  privateKey: CryptoKey;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function field(source: Record<string, unknown>, name: string): string {
  const value = source[name];
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`The server's payload key must be a P-256 private JWK with "${name}"`);
  }
  return value;
}

/** Lib: generateEphemeralKeyPair
 * Mints a P-256 keypair for one browser tab. The private half is not extractable, which does not
 * stop a debugger but does stop a log line or an error reporter from serialising it.
 */
export async function generateEphemeralKeyPair(): Promise<EcdhKeyPair> {
  const pair = await crypto.subtle.generateKey(CURVE, false, ['deriveBits']);
  const raw = await crypto.subtle.exportKey('raw', pair.publicKey);
  return { publicKey: toBase64Url(new Uint8Array(raw)), privateKey: pair.privateKey };
}

/** Lib: deriveSessionKey
 * Agrees the AES-256-GCM key from one side's private key and the other's public key. The raw
 * ECDH output is a curve coordinate, not uniformly random, so it goes through HKDF first.
 */
export async function deriveSessionKey(
  privateKey: CryptoKey,
  peerPublicKey: string,
): Promise<CryptoKey> {
  let peer: CryptoKey;
  try {
    peer = await crypto.subtle.importKey('raw', fromBase64Url(peerPublicKey), CURVE, false, []);
  } catch {
    /* WebCrypto validates the point, which is what makes an invalid-curve attack fail here. */
    throw new PayloadError('ENVELOPE_MALFORMED', 'The peer public key is not a P-256 point');
  }
  const secret = await crypto.subtle.deriveBits({ name: 'ECDH', public: peer }, privateKey, 256);
  const material = await crypto.subtle.importKey('raw', secret, 'HKDF', false, ['deriveKey']);
  return crypto.subtle.deriveKey(
    /* A zero-length salt, as RFC 5869 § 3.1 says when no shared random value exists; the label in
       `info` carries the domain separation. */
    { name: 'HKDF', hash: 'SHA-256', salt: new Uint8Array(0), info: utf8Bytes(HKDF_INFO) },
    material,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  );
}

/** Lib: generateServerKeyJwk
 * A new server keypair as base64url JWK text, the value `PAYLOAD_SERVER_JWK` holds. Run it
 * on your own machine and pipe it straight into the env file; never print it into a transcript.
 */
export async function generateServerKeyJwk(): Promise<string> {
  const pair = await crypto.subtle.generateKey(CURVE, true, ['deriveBits']);
  const jwk = await crypto.subtle.exportKey('jwk', pair.privateKey);
  return toBase64Url(
    utf8Bytes(JSON.stringify({ kty: jwk.kty, crv: jwk.crv, d: jwk.d, x: jwk.x, y: jwk.y })),
  );
}

/** Lib: importServerKeyPair
 * Loads the server's long-lived keypair from base64url JWK text. A JWK because the public half is
 * served to browsers and WebCrypto cannot recover it from a PKCS#8 private key; the public key is
 * rebuilt from the same fields, so it cannot drift from the private one.
 */
export async function importServerKeyPair(encodedJwk: string): Promise<EcdhKeyPair> {
  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder().decode(fromBase64Url(encodedJwk)));
  } catch {
    throw new Error("The server's payload key is not base64url JWK text");
  }
  if (!isRecord(parsed)) throw new Error("The server's payload key is not a JWK object");
  const jwk = parsed;
  const kty = field(jwk, 'kty');
  const crv = field(jwk, 'crv');
  const d = field(jwk, 'd');
  const x = field(jwk, 'x');
  const y = field(jwk, 'y');
  const privateKey = await crypto.subtle.importKey(
    'jwk',
    { kty, crv, d, x, y, ext: false, key_ops: ['deriveBits'] },
    CURVE,
    false,
    ['deriveBits'],
  );
  const publicKey = await crypto.subtle.importKey(
    'jwk',
    { kty, crv, x, y, key_ops: [] },
    CURVE,
    true,
    [],
  );
  const raw = await crypto.subtle.exportKey('raw', publicKey);
  return { privateKey, publicKey: toBase64Url(new Uint8Array(raw)) };
}
