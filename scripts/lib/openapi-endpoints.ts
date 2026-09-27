/**
 * The payload contract's configuration, and the endpoint registry an OpenAPI document implies.
 *
 * Shared by scripts/generate/endpoints.ts, which writes the generated half of the registry, and
 * scripts/check/endpoints.ts, which derives the same thing in memory and compares. One derivation
 * for both is the point: a generator and a checker with a derivation each could drift apart and
 * the gate would read clean. See .claude/PAYLOAD-CONTRACT.md.
 */

import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { EncryptionPolicy, HttpMethod } from '../../src/lib/payload/policy';

/** A route's escape from `strict`, written where review sees it: payload.config.json. */
export interface Exemption {
  encryption: EncryptionPolicy;
  reason: string;
}

/** Another repo that speaks the same contract, checked when it is checked out beside this one. */
export interface Peer {
  name: string;
  root: string;
}

/** payload.config.json, validated. */
export interface PayloadConfig {
  encryption: 'strict' | 'off';
  spec: string;
  registry: string;
  exemptions: Record<string, Exemption>;
  routeLiterals: { prefix: string; allow: string[] };
  fetchAllow: string[] | null;
  peers: Peer[];
}

/** One registry entry derived from the spec. */
export interface DerivedEndpoint {
  name: string;
  method: HttpMethod;
  pattern: string;
  params: string[];
  encryption: EncryptionPolicy;
  reason?: string;
}

export const CONFIG_FILE = 'payload.config.json';

const POLICIES: ReadonlySet<string> = new Set(['strict', 'response-only', 'request-only', 'none']);

function isPolicy(value: unknown): value is EncryptionPolicy {
  return typeof value === 'string' && POLICIES.has(value);
}
const METHODS: Readonly<Record<string, HttpMethod>> = {
  get: 'GET',
  post: 'POST',
  put: 'PUT',
  patch: 'PATCH',
  delete: 'DELETE',
  head: 'HEAD',
  options: 'OPTIONS',
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function strings(value: unknown, where: string): string[] {
  if (!Array.isArray(value) || !value.every((item) => typeof item === 'string')) {
    throw new Error(`${CONFIG_FILE}: ${where} must be a list of strings`);
  }
  return value;
}

function exemptionsOf(value: unknown): Record<string, Exemption> {
  if (!isRecord(value)) throw new Error(`${CONFIG_FILE}: exemptions must be an object`);
  const out: Record<string, Exemption> = {};
  for (const [route, entry] of Object.entries(value)) {
    if (!/^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) \/\S*$/.test(route)) {
      throw new Error(`${CONFIG_FILE}: exemption "${route}" must read "METHOD /pattern"`);
    }
    const policy = isRecord(entry) ? entry.encryption : undefined;
    const reason = isRecord(entry) ? entry.reason : undefined;
    if (!isPolicy(policy) || policy === 'strict') {
      throw new Error(`${CONFIG_FILE}: exemption "${route}" needs an encryption other than strict`);
    }
    if (typeof reason !== 'string' || reason.trim() === '') {
      throw new Error(`${CONFIG_FILE}: exemption "${route}" needs a written reason`);
    }
    out[route] = { encryption: policy, reason };
  }
  return out;
}

/** Lib: readPayloadConfig
 * payload.config.json at `root`, or null where the contract is not adopted.
 */
export function readPayloadConfig(root: string): PayloadConfig | null {
  const path = join(root, CONFIG_FILE);
  if (!existsSync(path)) return null;
  const raw: unknown = JSON.parse(readFileSync(path, 'utf8'));
  if (!isRecord(raw)) throw new Error(`${CONFIG_FILE} must hold a JSON object`);
  const literals = isRecord(raw.routeLiterals) ? raw.routeLiterals : {};
  const peers = Array.isArray(raw.peers) ? raw.peers : [];
  return {
    encryption: raw.encryption === 'off' ? 'off' : 'strict',
    spec: typeof raw.spec === 'string' ? raw.spec : 'openapi.json',
    registry: typeof raw.registry === 'string' ? raw.registry : 'src/lib/endpoints',
    exemptions: exemptionsOf(raw.exemptions ?? {}),
    routeLiterals: {
      prefix: typeof literals.prefix === 'string' ? literals.prefix : '/api/',
      allow: strings(literals.allow ?? [], 'routeLiterals.allow'),
    },
    fetchAllow: raw.fetchAllow === undefined ? null : strings(raw.fetchAllow, 'fetchAllow'),
    peers: peers.map((peer: unknown) => {
      if (!isRecord(peer) || typeof peer.name !== 'string' || typeof peer.root !== 'string') {
        throw new Error(`${CONFIG_FILE}: each peer needs a name and a root`);
      }
      return { name: peer.name, root: peer.root };
    }),
  };
}

/** `/api/notes/{id}` as `/api/notes/:id`, and the parameter names in order. */
function toPattern(path: string): { pattern: string; params: string[] } {
  const params = [...path.matchAll(/\{([^}]+)\}/g)].map((match) => match[1] ?? '');
  return { pattern: path.replace(/\{([^}]+)\}/g, ':$1'), params };
}

/** `POST /api/notes/{id}/share` as `POST_NOTES_BY_ID_SHARE`: mechanical, so every regeneration
 * chooses the same name. A leading `api` segment is dropped; it distinguishes nothing. */
function constantName(method: HttpMethod, path: string): string {
  const tail = path
    .split('/')
    .filter(Boolean)
    .filter((segment, index) => !(index === 0 && segment === 'api'))
    .map((segment) => (segment.startsWith('{') ? `by_${segment.slice(1, -1)}` : segment))
    .join('_')
    .replace(/[^A-Za-z0-9_]/g, '_')
    .replace(/_+/g, '_')
    .toUpperCase();
  return tail ? `${method}_${tail}` : `${method}_ROOT`;
}

/** Lib: deriveEndpoints
 * The registry entries a spec implies, sorted by name; an exemption from the config is the only
 * way an entry leaves `strict`.
 */
export function deriveEndpoints(
  spec: unknown,
  exemptions: Record<string, Exemption>,
): DerivedEndpoint[] {
  const out: DerivedEndpoint[] = [];
  const paths = isRecord(spec) && isRecord(spec.paths) ? spec.paths : {};
  for (const [path, operations] of Object.entries(paths)) {
    if (!isRecord(operations)) continue;
    for (const key of Object.keys(operations)) {
      const method = METHODS[key.toLowerCase()];
      if (!method) continue;
      const { pattern, params } = toPattern(path);
      const exemption = exemptions[`${method} ${pattern}`];
      out.push({
        name: constantName(method, path),
        method,
        pattern,
        params,
        encryption: exemption?.encryption ?? 'strict',
        ...(exemption ? { reason: exemption.reason } : {}),
      });
    }
  }
  return out.toSorted((a, b) => a.name.localeCompare(b.name));
}
