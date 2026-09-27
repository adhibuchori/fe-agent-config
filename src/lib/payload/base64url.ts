/**
 * Bytes on the wire: base64url and UTF-8, the same way in the browser, on Node and on Bun.
 *
 * Every binary field of an envelope (nonce, ciphertext, a public key) travels inside JSON or a
 * header, so it is encoded as unpadded base64url: `+`, `/` and `=` are the characters a URL, a
 * header parser or a log pipeline mangles first. Built on `btoa`/`atob` rather than `Buffer`,
 * which does not exist in a browser.
 *
 * Part of the payload contract (.claude/PAYLOAD-CONTRACT.md). The frontend and the backend carry
 * the same copy of this folder; scripts/check/crypto-interop.ts proves they still agree.
 */

/* `String.fromCharCode(...bytes)` on a large body overflows the call stack, and the overflow
   would surface as a decryption failure with no useful message. Chunked instead. */
const CHUNK = 0x8000;

/**
 * Bytes backed by a plain `ArrayBuffer`, the only kind WebCrypto's `BufferSource` accepts once
 * `Uint8Array` is generic over its buffer. Narrowed once here instead of cast at every call.
 */
export type Bytes = Uint8Array<ArrayBuffer>;

/** Lib: toBase64Url
 * Encodes bytes as unpadded base64url.
 */
export function toBase64Url(bytes: Bytes): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** Lib: fromBase64Url
 * Decodes base64url, and standard base64 as a person pastes it, back to bytes.
 */
export function fromBase64Url(value: string): Bytes {
  const standard = value.trim().replace(/-/g, '+').replace(/_/g, '/');
  let binary: string;
  try {
    binary = atob(standard);
  } catch {
    /* `atob` names neither the field nor the envelope; a caller must be able to tell a malformed
       field from an empty one. */
    throw new Error('Malformed base64url value');
  }
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/** Lib: utf8Bytes
 * Encodes a string as UTF-8 bytes in a fresh, ArrayBuffer-backed array.
 */
export function utf8Bytes(value: string): Bytes {
  const encoded = new TextEncoder().encode(value);
  const bytes = new Uint8Array(encoded.length);
  bytes.set(encoded);
  return bytes;
}

/** Lib: utf8String
 * Decodes UTF-8 bytes back to a string.
 */
export function utf8String(bytes: Bytes): string {
  return new TextDecoder().decode(bytes);
}
