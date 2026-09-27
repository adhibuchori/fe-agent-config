/**
 * Unit tests for policies and the endpoint matcher: part of the payload contract (.claude/PAYLOAD-CONTRACT.md).
 * @vitest-environment node
 */
import { describe, expect, test } from 'vitest';
import {
  matchEndpoint,
  pathOf,
  sealsRequest,
  sealsResponse,
  type EndpointDefinition,
  type EndpointMap,
  type PrefixRule,
} from '@/lib/payload/policy';

const byId: EndpointDefinition = { method: 'GET', pattern: '/api/notes/:id', encryption: 'strict' };
const stats: EndpointDefinition = {
  method: 'GET',
  pattern: '/api/notes/stats',
  encryption: 'none',
  reason: 'public counters',
};
const share: EndpointDefinition = {
  method: 'POST',
  pattern: '/api/notes/:id/share',
  encryption: 'strict',
};
const registry: EndpointMap = {
  GET_NOTES_BY_ID: byId,
  GET_NOTES_STATS: stats,
  GET_V1_ITEMS: { method: 'GET', pattern: '/api/v1.0/items', encryption: 'strict' },
  POST_NOTES_BY_ID_SHARE: share,
};
const prefixes: PrefixRule[] = [
  { prefix: '/api/auth/', encryption: 'strict', reason: 'the auth library owns its routes' },
  { prefix: '/api/auth/public/', encryption: 'none', reason: 'a public probe' },
];

describe('policies', () => {
  test.each([
    ['strict', true, true],
    ['response-only', false, true],
    ['request-only', true, false],
    ['none', false, false],
  ] as const)('%s seals the request %s and the response %s', (policy, request, response) => {
    expect(sealsRequest(policy)).toBe(request);
    expect(sealsResponse(policy)).toBe(response);
  });
});

describe('matchEndpoint', () => {
  test('the most specific pattern wins, whatever the declaration order', () => {
    expect(matchEndpoint(registry, [], 'get', '/api/notes/stats')?.encryption).toBe('none');
    const reversed = Object.fromEntries(Object.entries(registry).toReversed());
    expect(matchEndpoint(reversed, [], 'GET', '/api/notes/stats')?.encryption).toBe('none');
    expect(matchEndpoint(registry, [], 'GET', '/api/notes/42')).toEqual({
      method: 'GET',
      pattern: '/api/notes/:id',
      encryption: 'strict',
      viaPrefix: false,
    });
  });

  test('matches a literal segment literally and ignores the query and hash', () => {
    expect(matchEndpoint(registry, [], 'GET', '/api/v1.0/items?page=2')?.pattern).toBe(
      '/api/v1.0/items',
    );
    expect(matchEndpoint(registry, [], 'GET', '/api/v1x0/items')).toBeUndefined();
    expect(matchEndpoint(registry, [], 'POST', '/api/notes/7/share#top')?.pattern).toBe(
      '/api/notes/:id/share',
    );
  });

  test('a prefix answers only when no pattern does, and the longest prefix wins', () => {
    expect(matchEndpoint(registry, prefixes, 'POST', '/api/auth/sign-in')).toEqual({
      method: 'POST',
      pattern: '/api/auth/sign-in',
      encryption: 'strict',
      viaPrefix: true,
    });
    expect(matchEndpoint(registry, prefixes, 'GET', '/api/auth/public/ok')?.encryption).toBe(
      'none',
    );
  });

  test('an unregistered route or method matches nothing', () => {
    expect(matchEndpoint(registry, prefixes, 'DELETE', '/api/notes/1')).toBeUndefined();
    expect(matchEndpoint(registry, prefixes, 'GET', '/api/notes/1/extra')).toBeUndefined();
  });
});

describe('pathOf', () => {
  test('fills each parameter in order, URI-encoded', () => {
    expect(pathOf(stats)).toBe('/api/notes/stats');
    expect(pathOf(share, 'a/b')).toBe('/api/notes/a%2Fb/share');
  });

  test('refuses the wrong number of parameters', () => {
    expect(() => pathOf(byId)).toThrow('takes 1 parameter(s), received 0');
  });
});
