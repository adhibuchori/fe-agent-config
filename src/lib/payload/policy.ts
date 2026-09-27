/**
 * The endpoint registry's types, and the one place that decides what a policy seals.
 *
 * Every route is one record carrying both halves of the contract: where it lives, and what
 * happens to its payload. A route with no encryption decision is not a valid entry, so there is
 * no state in which an endpoint exists and nobody decided its policy.
 */

/** An HTTP method, uppercase; part of the request AAD. */
export type HttpMethod = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE' | 'HEAD' | 'OPTIONS';

/** Which sides of an exchange are sealed. The half-policies name the side that cannot be sealed,
 * and the reason is always a property of the body, never a judgement of how sensitive it is. */
export type EncryptionPolicy =
  /** Both sides. The default for every endpoint. */
  | 'strict'
  /** Request plain, response sealed: a `multipart/form-data` upload, whose boundary must survive. */
  | 'response-only'
  /** Request sealed, response plain: a `text/event-stream`, or a file a browser saves or draws. */
  | 'request-only'
  /** Neither: probes, the spec, the handshake, a third party's webhook. Needs a reason. */
  | 'none';

/** One registered route. */
export interface EndpointDefinition {
  readonly method: HttpMethod;
  /** Route shape with `:param` placeholders; what both sides put in the AAD. */
  readonly pattern: string;
  readonly encryption: EncryptionPolicy;
  /** Why the route is not `strict`. Required for any other policy; checked by check:endpoints. */
  readonly reason?: string;
}

/** A registry: stable names to routes. */
export type EndpointMap = Readonly<Record<string, EndpointDefinition>>;

/** A policy for a route family that cannot be enumerated, such as an auth library's catch-all. */
export interface PrefixRule {
  readonly prefix: string;
  readonly encryption: EncryptionPolicy;
  readonly reason: string;
}

/** The registry entry a request resolved to. */
export interface EndpointMatch {
  readonly method: string;
  /** The registry pattern, or the concrete path for a prefix match (it has no placeholders). */
  readonly pattern: string;
  readonly encryption: EncryptionPolicy;
  readonly viaPrefix: boolean;
}

/** Lib: sealsRequest
 * Whether a policy seals the request body. Call this; never compare policy strings in a transport.
 */
export function sealsRequest(policy: EncryptionPolicy): boolean {
  return policy === 'strict' || policy === 'request-only';
}

/** Lib: sealsResponse
 * Whether a policy seals the response body.
 */
export function sealsResponse(policy: EncryptionPolicy): boolean {
  return policy === 'strict' || policy === 'response-only';
}

/* A pattern as an anchored expression: a `:param` segment matches one non-empty segment, and
   every other segment matches itself literally. */
function patternMatches(pattern: string, path: string): boolean {
  const source = pattern
    .split('/')
    .map((part) => (part.startsWith(':') ? '[^/]+' : part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
    .join('/');
  return new RegExp(`^${source}$`).test(path);
}

/** Lib: matchEndpoint
 * The entry a request belongs to. The most specific pattern wins (the most literal segments), not
 * the first declared: `/items/stats` must not take the policy of `/items/:id`. A prefix rule
 * answers only when no pattern does, and the longest prefix wins. `undefined` is not "allow": a
 * client transport refuses an unregistered route.
 */
export function matchEndpoint(
  registry: EndpointMap,
  prefixes: readonly PrefixRule[],
  method: string,
  pathname: string,
): EndpointMatch | undefined {
  const upper = method.toUpperCase();
  const path = pathname.replace(/[?#].*$/s, '');
  let best: EndpointMatch | undefined;
  let bestLiterals = -1;
  for (const entry of Object.values(registry)) {
    if (entry.method !== upper || !patternMatches(entry.pattern, path)) continue;
    const literals = entry.pattern.split('/').filter((part) => !part.startsWith(':')).length;
    if (literals <= bestLiterals) continue;
    bestLiterals = literals;
    best = {
      method: upper,
      pattern: entry.pattern,
      encryption: entry.encryption,
      viaPrefix: false,
    };
  }
  if (best) return best;
  let rule: PrefixRule | undefined;
  for (const candidate of prefixes) {
    if (
      path.startsWith(candidate.prefix) &&
      candidate.prefix.length > (rule?.prefix.length ?? -1)
    ) {
      rule = candidate;
    }
  }
  return rule
    ? { method: upper, pattern: path, encryption: rule.encryption, viaPrefix: true }
    : undefined;
}

/** Lib: pathOf
 * The concrete path for an entry, one argument per `:param` in order, each URI-encoded so an id
 * holding a slash cannot change which route the request lands on.
 */
export function pathOf(endpoint: EndpointDefinition, ...params: string[]): string {
  const names = endpoint.pattern.split('/').filter((part) => part.startsWith(':'));
  if (names.length !== params.length) {
    throw new Error(
      `${endpoint.pattern} takes ${names.length} parameter(s), received ${params.length}`,
    );
  }
  const values = params.values();
  return endpoint.pattern.replace(
    /(^|\/):[^/]+/g,
    (_segment, lead: string) => `${lead}${encodeURIComponent(String(values.next().value))}`,
  );
}
