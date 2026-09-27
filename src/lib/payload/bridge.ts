/**
 * The frontend server's crypto boundary, where the browser hop meets the backend hop.
 *
 * The browser seals to a key agreed with this server; the backend seals to a key this server
 * shares with it. Neither side knows about the other: the browser never holds a server secret, and
 * the backend never learns a browser was involved. Pure functions: the route handler that proxies
 * requests passes the keys in, and that handler (marked `server-only`) is the one place a secret
 * enters this process.
 */

import { openJson, parseEnvelope, sealJson } from './codec';
import { deriveSessionKey, ECDH_KID } from './ecdh';
import { requestAad, responseAad } from './envelope';
import { PayloadError } from './errors';
import type { KeyRing } from './key-ring';
import type { EndpointMatch } from './policy';

/** Lib: openFromBrowser
 * Opens a browser's sealed request body with the key agreed from its `x-payload-epk` header.
 */
export async function openFromBrowser(
  raw: string,
  epk: string | null,
  match: EndpointMatch,
  serverPrivateKey: CryptoKey,
): Promise<string> {
  if (!epk) {
    throw new PayloadError('ENVELOPE_REQUIRED', 'The request carried no ephemeral public key');
  }
  const key = await deriveSessionKey(serverPrivateKey, epk);
  const body = await openJson(parseEnvelope(raw), {
    key,
    aadFor: (kid, ts) => requestAad(match.method, match.pattern, kid, ts),
  });
  return JSON.stringify(body);
}

/** Lib: sealForBrowser
 * Seals a plaintext JSON body for the browser that sent `epk`, bound to the status it goes with.
 */
export async function sealForBrowser(
  body: string,
  epk: string,
  match: EndpointMatch,
  status: number,
  serverPrivateKey: CryptoKey,
): Promise<string> {
  const key = await deriveSessionKey(serverPrivateKey, epk);
  const envelope = await sealJson(JSON.parse(body), {
    key,
    kid: ECDH_KID,
    aadFor: (kid, ts) => responseAad(status, match.pattern, kid, ts),
  });
  return JSON.stringify(envelope);
}

/** Lib: sealForUpstream
 * Seals a plaintext JSON body under the primary key this server shares with the backend.
 */
export async function sealForUpstream(
  body: string,
  match: EndpointMatch,
  ring: KeyRing,
): Promise<string> {
  const envelope = await sealJson(JSON.parse(body), {
    key: ring.primary.key,
    kid: ring.primary.kid,
    aadFor: (kid, ts) => requestAad(match.method, match.pattern, kid, ts),
  });
  return JSON.stringify(envelope);
}

/** Lib: openFromUpstream
 * Opens the backend's sealed response. Between two servers holding a shared key, a failure here
 * means a key mismatch far more often than an attack: check both sides' key ids first.
 */
export async function openFromUpstream(
  raw: string,
  match: EndpointMatch,
  status: number,
  ring: KeyRing,
): Promise<string> {
  const envelope = parseEnvelope(raw);
  const body = await openJson(envelope, {
    key: ring.resolve(envelope.kid),
    aadFor: (kid, ts) => responseAad(status, match.pattern, kid, ts),
  });
  return JSON.stringify(body);
}
