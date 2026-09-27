/**
 * Pre-shared keys for server-to-server hops, which never reach a browser.
 *
 * One variable holds `kid:base64key`, because a key and the id naming it are one fact: split
 * across two variables, one gets rotated without the other and every request fails to decrypt
 * with nothing saying why. This module is pure: it parses what it is handed and never reads the
 * environment, so the file that does read it (the env module) stays the only one that touches a
 * secret.
 */

import { importAesKey } from './aes-gcm';
import { fromBase64Url, type Bytes } from './base64url';
import { ECDH_KID } from './ecdh';
import { PayloadError } from './errors';

/** A key id: short, printable, and never the id reserved for agreed browser keys. */
const KID_PATTERN = /^[A-Za-z0-9._-]{1,32}$/;

/* AES-256: `openssl rand -base64 32` prints exactly this much. */
const KEY_BYTES = 32;

/** One configured key: its raw value, and the variable it came from for error messages. */
export interface KeySource {
  /** `kid:base64key`. An empty or unset value is skipped, so a rotation slot needs no branch. */
  value: string | undefined;
  /** The variable name, so a malformed value names itself. */
  name: string;
}

/** A key and the id that names it on the wire. */
export interface KeyEntry {
  kid: string;
  key: CryptoKey;
}

/** The keys one side seals with and accepts. */
export interface KeyRing {
  /** What an outgoing payload is sealed with when nothing else decides. */
  primary: KeyEntry;
  /** Every id this ring accepts, for logs and checks. */
  kids: readonly string[];
  /** The key an envelope's `kid` names. Throws `ENVELOPE_KEY_UNKNOWN` for an id it does not hold. */
  resolve(kid: string): CryptoKey;
}

async function parseEntry(source: KeySource & { value: string }): Promise<KeyEntry> {
  const at = source.value.indexOf(':');
  const kid = source.value.slice(0, at).trim();
  if (at < 1 || !KID_PATTERN.test(kid) || kid === ECDH_KID) {
    throw new Error(
      `${source.name} must be "kid:base64key" with a short kid other than "${ECDH_KID}"`,
    );
  }
  let material: Bytes;
  try {
    material = fromBase64Url(source.value.slice(at + 1));
  } catch {
    throw new Error(`${source.name} holds a key that is not base64`);
  }
  if (material.length !== KEY_BYTES) {
    throw new Error(
      `${source.name} must decode to ${KEY_BYTES} bytes, received ${material.length}`,
    );
  }
  return { kid, key: await importAesKey(material) };
}

/** Lib: createKeyRing
 * Builds a ring from key sources in priority order: the first configured one is the primary, and
 * every one is accepted for decryption. Rotation is a second source (`<NAME>_NEXT`): deploy both
 * sides with it, then swap the order, and no request falls into the gap. Fails at startup on a
 * malformed value, a duplicate kid, or no key at all.
 */
export async function createKeyRing(sources: readonly KeySource[]): Promise<KeyRing> {
  const configured = sources.filter((s): s is KeySource & { value: string } =>
    Boolean(s.value?.trim()),
  );
  const entries = await Promise.all(configured.map(parseEntry));
  const primary = entries[0];
  if (!primary) {
    throw new Error(`No payload key configured; set ${sources[0]?.name ?? 'a payload key'}`);
  }
  const byKid = new Map<string, CryptoKey>();
  for (const entry of entries) {
    if (byKid.has(entry.kid)) throw new Error(`Two payload keys share the kid "${entry.kid}"`);
    byKid.set(entry.kid, entry.key);
  }
  return {
    primary,
    kids: [...byKid.keys()],
    resolve(kid: string): CryptoKey {
      const key = byKid.get(kid);
      if (!key) throw new PayloadError('ENVELOPE_KEY_UNKNOWN', `No payload key with id "${kid}"`);
      return key;
    },
  };
}
