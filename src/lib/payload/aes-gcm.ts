/**
 * The one cipher on the wire: AES-256-GCM through WebCrypto.
 *
 * GCM authenticates as well as encrypts. The additional authenticated data is never sent; it is
 * mixed into the tag, so a ciphertext lifted from one route and replayed on another fails to open
 * instead of decrypting into a plausible body.
 */

import type { Bytes } from './base64url';
import { PayloadError } from './errors';

/* 96 bits: the nonce length GCM is specified for. Any other length takes WebCrypto through an
   extra derivation another implementation would not reproduce. */
const IV_BYTES = 12;

/* Stated rather than left to defaults: WebCrypto defaults to 128, Python's `cryptography` has no
   default to lean on, and the test vectors would be the first to notice a disagreement. */
const TAG_BITS = 128;

const KEY_BYTES = 32;

/** Lib: randomIv
 * A fresh nonce. One per encryption and never reused under a key: reuse breaks GCM outright.
 */
export function randomIv(): Bytes {
  return crypto.getRandomValues(new Uint8Array(IV_BYTES));
}

/** Lib: seal
 * Encrypts bytes under a key, bound to the AAD; returns the ciphertext with the tag appended.
 */
export async function seal(
  key: CryptoKey,
  iv: Bytes,
  plaintext: Bytes,
  aad: Bytes,
): Promise<Bytes> {
  const sealed = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv, additionalData: aad, tagLength: TAG_BITS },
    key,
    plaintext,
  );
  return new Uint8Array(sealed);
}

/** Lib: open
 * Verifies and decrypts. One error for a wrong key, a tampered body and a foreign AAD alike:
 * saying which one failed tells a prober which half of the guess was right.
 */
export async function open(key: CryptoKey, iv: Bytes, sealed: Bytes, aad: Bytes): Promise<Bytes> {
  if (iv.length !== IV_BYTES) {
    throw new PayloadError('ENVELOPE_REJECTED', 'Payload authentication failed');
  }
  try {
    const plaintext = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv, additionalData: aad, tagLength: TAG_BITS },
      key,
      sealed,
    );
    return new Uint8Array(plaintext);
  } catch {
    /* WebCrypto throws an `OperationError` with an empty message. */
    throw new PayloadError('ENVELOPE_REJECTED', 'Payload authentication failed');
  }
}

/** Lib: importAesKey
 * Turns exactly 32 bytes into a non-extractable AES-256-GCM key. A truncated secret is refused
 * here, at startup, instead of failing at the first decrypt on the other side of the wire.
 */
export async function importAesKey(raw: Bytes): Promise<CryptoKey> {
  if (raw.length !== KEY_BYTES) {
    throw new Error(`AES-256-GCM needs ${KEY_BYTES} bytes of key material, received ${raw.length}`);
  }
  return crypto.subtle.importKey('raw', raw, { name: 'AES-GCM', length: 256 }, false, [
    'encrypt',
    'decrypt',
  ]);
}
