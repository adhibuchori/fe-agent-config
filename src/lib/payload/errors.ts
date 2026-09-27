/**
 * The closed set of ways an envelope can fail to become a payload.
 *
 * Codes rather than free text, because they cross a process boundary: the backend answers with
 * one as the problem+json `code`, and the frontend maps each to a message a person can read. A
 * message invented at the throw site would reach them untranslated.
 */

/** Every payload failure a transport can report. */
export type PayloadCode =
  /** A sealed endpoint received a body that is not an envelope: nearly always a hand-rolled call. */
  | 'ENVELOPE_REQUIRED'
  /** Envelope-shaped but unreadable: an unknown version, a missing field, plaintext that is not JSON. */
  | 'ENVELOPE_MALFORMED'
  /** Outside the freshness window: a replay, or two clocks that drifted apart. */
  | 'ENVELOPE_EXPIRED'
  /** The `kid` names a key this side does not hold: mid-rotation, or a mismatched deployment. */
  | 'ENVELOPE_KEY_UNKNOWN'
  /** The tag did not verify: tampering, the wrong key, or an envelope bound to another route. */
  | 'ENVELOPE_REJECTED';

/** The codes, for a mapping table that must name every one of them. */
export const PAYLOAD_CODES: readonly PayloadCode[] = [
  'ENVELOPE_REQUIRED',
  'ENVELOPE_MALFORMED',
  'ENVELOPE_EXPIRED',
  'ENVELOPE_KEY_UNKNOWN',
  'ENVELOPE_REJECTED',
];

/** A payload failure with its code. The message is for logs; the code is for the wire. */
export class PayloadError extends Error {
  readonly code: PayloadCode;

  constructor(code: PayloadCode, message: string) {
    super(message);
    this.name = 'PayloadError';
    this.code = code;
  }
}

/** Lib: isPayloadError
 * Whether a caught value is a payload failure.
 */
export function isPayloadError(value: unknown): value is PayloadError {
  return value instanceof PayloadError;
}
