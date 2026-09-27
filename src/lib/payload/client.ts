/**
 * The browser's half of the payload contract: one agreed key per tab, and the sealing and opening
 * the API client's transport calls around each request (.claude/PAYLOAD-CONTRACT.md).
 *
 * Nothing here reads an environment variable: all of it ships to the browser. The key lives in a
 * closure for as long as the page does, never in storage, and the promise is what is cached, so a
 * page that fires six queries on mount runs one handshake. Components and hooks never import this
 * module; only the transport does.
 */

import { openJson, parseEnvelope, sealJson } from './codec';
import { deriveSessionKey, ECDH_KID, generateEphemeralKeyPair } from './ecdh';
import { ENCRYPTED_MEDIA_TYPE, EPK_HEADER, requestAad, responseAad } from './envelope';
import { isPayloadError, PayloadError } from './errors';
import type { EncryptionMode } from './mode';
import { sealsRequest, sealsResponse, type EndpointMatch } from './policy';

/** Where the handshake lives, and the fetch to reach it with. */
export interface BrowserPayloadOptions {
  /** A GET route answering `{ publicKey, mode }`; registered with policy `none` and a reason. */
  handshakeUrl: string;
  /** Injectable for tests; the global `fetch` otherwise. */
  fetch?: (input: string, init: RequestInit) => Promise<Response>;
}

/** A request body as it should go out, and the headers that describe it. */
export interface OutgoingRequest {
  body: string | null;
  headers: Record<string, string>;
  /** False when this origin runs with the contract off, or the route seals nothing. */
  active: boolean;
}

/** A response as the transport received it. */
export interface IncomingResponse {
  status: number;
  contentType: string;
  body: string;
}

/** The transport's calls around one request. */
export interface BrowserPayload {
  seal(match: EndpointMatch, body: string | null, isFormData?: boolean): Promise<OutgoingRequest>;
  read(match: EndpointMatch, response: IncomingResponse, active: boolean): Promise<unknown>;
  reset(): void;
}

interface SessionKey {
  key: CryptoKey;
  epk: string;
  mode: EncryptionMode;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function parseBody(body: string): unknown {
  if (body === '') return null;
  try {
    return JSON.parse(body);
  } catch {
    return body;
  }
}

/** Lib: createBrowserPayload
 * The browser transport's payload calls, negotiating the tab's key on first use.
 */
export function createBrowserPayload(options: BrowserPayloadOptions): BrowserPayload {
  const doFetch = options.fetch ?? ((input, init) => fetch(input, init));
  let negotiated: Promise<SessionKey> | null = null;

  async function negotiate(): Promise<SessionKey> {
    const response = await doFetch(options.handshakeUrl, { method: 'GET', cache: 'no-store' });
    if (!response.ok) {
      throw new PayloadError(
        'ENVELOPE_KEY_UNKNOWN',
        `Payload handshake answered ${response.status}`,
      );
    }
    const parsed: unknown = await response.json();
    const answer = isRecord(parsed) ? parsed : {};
    if (typeof answer.publicKey !== 'string' || answer.publicKey === '') {
      throw new PayloadError(
        'ENVELOPE_KEY_UNKNOWN',
        'The payload handshake returned no public key',
      );
    }
    const ephemeral = await generateEphemeralKeyPair();
    return {
      key: await deriveSessionKey(ephemeral.privateKey, answer.publicKey),
      epk: ephemeral.publicKey,
      /* Anything but an explicit "off" is strict, so a server too old to say still gets envelopes. */
      mode: answer.mode === 'off' ? 'off' : 'strict',
    };
  }

  function session(): Promise<SessionKey> {
    /* A failed handshake is forgotten, so a request made offline does not leave every later
       request in this tab failing against the same rejected promise. */
    negotiated ??= negotiate().catch((error: unknown) => {
      negotiated = null;
      throw error;
    });
    return negotiated;
  }

  return {
    async seal(match, body, isFormData = false) {
      /* A FormData body is never sealed: the browser writes the multipart boundary into the
         Content-Type itself, and the server could not parse a sealed one. */
      const sealRequest = sealsRequest(match.encryption) && !isFormData;
      if (!sealRequest && !sealsResponse(match.encryption))
        return { body, headers: {}, active: false };
      const { key, epk, mode } = await session();
      if (mode === 'off') return { body, headers: {}, active: false };
      const headers: Record<string, string> = { [EPK_HEADER]: epk };
      if (!sealRequest || body === null) return { body, headers, active: true };
      const envelope = await sealJson(JSON.parse(body), {
        key,
        kid: ECDH_KID,
        aadFor: (kid, ts) => requestAad(match.method, match.pattern, kid, ts),
      });
      headers['content-type'] = ENCRYPTED_MEDIA_TYPE;
      return { body: JSON.stringify(envelope), headers, active: true };
    },

    async read(match, response, active) {
      if (!active || !sealsResponse(match.encryption)) return parseBody(response.body);
      if (!response.contentType.includes(ENCRYPTED_MEDIA_TYPE)) {
        /* A plaintext answer is accepted only as a refusal or an empty body: a plaintext success
           on a sealed route is a downgrade, whoever sent it. */
        if (response.status >= 400 || response.body === '') return parseBody(response.body);
        throw new PayloadError('ENVELOPE_REQUIRED', `${match.pattern} answered in plaintext`);
      }
      const { key } = await session();
      try {
        return await openJson(parseEnvelope(response.body), {
          key,
          aadFor: (kid, ts) => responseAad(response.status, match.pattern, kid, ts),
        });
      } catch (error) {
        /* A server restarted with a new keypair answers with a tag this key cannot verify; the
           next request negotiates again instead of failing until the page reloads. */
        if (isPayloadError(error) && error.code === 'ENVELOPE_REJECTED') negotiated = null;
        throw error;
      }
    },

    reset() {
      negotiated = null;
    },
  };
}
