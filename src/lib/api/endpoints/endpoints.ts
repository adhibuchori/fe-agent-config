/**
 * Every route this app calls, and what happens to its payload (.claude/PAYLOAD-CONTRACT.md).
 *
 * The backend's routes arrive generated from the committed copy of its spec, with policies decided
 * in payload.config.json. Only routes this app serves itself are written here. The transport
 * refuses a route it cannot find in this registry: a route nobody registered is a route nobody
 * decided a policy for.
 */

import type { EndpointMap, PrefixRule } from '../../payload/policy';
import { GENERATED_ENDPOINTS } from './endpoints.generated';

/** Routes this app serves itself, outside the backend's spec. */
const LOCAL_ENDPOINTS = {
  GET_PAYLOAD_HANDSHAKE: {
    method: 'GET',
    pattern: '/api/payload/handshake',
    encryption: 'none',
    reason: 'delivers the public key every other envelope is sealed to; a public key is public',
  },
} as const satisfies EndpointMap;

/** The whole registry. */
export const ENDPOINTS = {
  ...GENERATED_ENDPOINTS,
  ...LOCAL_ENDPOINTS,
} as const satisfies EndpointMap;

/**
 * Policies for route families that cannot be enumerated. An auth library's catch-all decides its
 * own route list; a prefix covers routes a future upgrade adds.
 */
export const ENDPOINT_PREFIXES: readonly PrefixRule[] = [
  {
    prefix: '/api/auth/',
    encryption: 'strict',
    reason: 'the auth library owns its route list; a prefix covers routes an upgrade adds',
  },
];
