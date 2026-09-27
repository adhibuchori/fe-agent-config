/**
 * The switch: whether this service enforces the payload contract.
 *
 * Two sources, in order: the `PAYLOAD_MODE` environment variable, then `encryption` in
 * the committed `payload.config.json`, then `strict`. The file is what a developer edits, so the
 * setting travels with the branch and shows in review; the variable lets a deployment force
 * `strict` without editing anything. `off` exists to bisect a transport problem locally and is
 * refused in production, at startup, so a branch merged with the switch still flipped fails to
 * boot instead of serving plaintext. A browser never reads either source: the server tells it the
 * mode in the handshake, because a switch two sides can disagree about is worse than none.
 */

/** How a boundary behaves. */
export type EncryptionMode = 'strict' | 'off';

/** Lib: resolveEncryptionMode
 * Settles the mode from the two sources and refuses what is not allowed.
 */
export function resolveEncryptionMode(
  fromEnv: string | undefined,
  fromConfig: string | undefined,
  isProduction: boolean,
): EncryptionMode {
  const envValue = fromEnv?.trim() ?? '';
  const source = envValue ? 'PAYLOAD_MODE' : 'payload.config.json encryption';
  const raw = (envValue || fromConfig?.trim() || 'strict').toLowerCase();
  if (raw !== 'strict' && raw !== 'off') {
    throw new Error(`${source} must be "strict" or "off", received "${raw}"`);
  }
  if (raw === 'off' && isProduction) {
    throw new Error(`${source} is "off", which is refused in production`);
  }
  return raw;
}
