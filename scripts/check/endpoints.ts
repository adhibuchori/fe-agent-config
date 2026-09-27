#!/usr/bin/env bun
/**
 * The static half of the payload contract (.claude/PAYLOAD-CONTRACT.md). The runtime half refuses
 * an unsealed request at the boundary; this refuses the code that would send or serve one.
 *
 *   1. The switch: payload.config.json says `strict`. A branch never merges with the contract off;
 *      debug with PAYLOAD_MODE=off in your own shell instead.
 *   2. Registry drift: the generated registry equals what the spec and the exemptions imply.
 *   3. Reasons: every non-strict entry and prefix says why, and no strict entry carries a reason.
 *   4. Route literals: no quoted route path in src/ outside the files allowed to name routes.
 *   5. Raw transport (where `fetchAllow` is set): no `fetch(`, XMLHttpRequest or axios outside the
 *      transport files, so nothing sends a request the cipher never saw.
 *   6. Generated client (where src/lib/api/generated/ exists): every URL it builds is registered.
 *   7. Peers (where checked out): the spec copy and the exemptions equal the peer's.
 *
 * Compares meaning, not text: registries are imported and specs compared as canonical JSON, so
 * formatting never reads as drift. Exit 0 clean, 1 on any problem.
 */

import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import {
  CONFIG_FILE,
  deriveEndpoints,
  readPayloadConfig,
  type PayloadConfig,
} from '../lib/openapi-endpoints';
import {
  allowed,
  canonical,
  codeOnly,
  isRecord,
  isTest,
  lineOf,
  sortKeys,
  sourceFiles,
} from '../lib/source-scan';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const problems: string[] = [];
const fail = (check: string, detail: string): void => {
  problems.push(`${check}: ${detail}`);
};

async function registryOf(config: PayloadConfig): Promise<{
  generated: Record<string, unknown>;
  all: Record<string, unknown>;
  prefixes: unknown[];
}> {
  const dir = join(ROOT, config.registry);
  const generated: unknown = await import(pathToFileURL(join(dir, 'endpoints.generated.ts')).href);
  const main: unknown = await import(pathToFileURL(join(dir, 'endpoints.ts')).href);
  const pick = (mod: unknown, name: string): unknown => (isRecord(mod) ? mod[name] : undefined);
  const gen = pick(generated, 'GENERATED_ENDPOINTS');
  const all = pick(main, 'ENDPOINTS');
  const prefixes = pick(main, 'ENDPOINT_PREFIXES') ?? [];
  if (!isRecord(gen) || !isRecord(all) || !Array.isArray(prefixes)) {
    throw new Error(
      `${config.registry}: expected GENERATED_ENDPOINTS, ENDPOINTS and ENDPOINT_PREFIXES exports`,
    );
  }
  return { generated: gen, all, prefixes };
}

const config = readPayloadConfig(ROOT);
if (!config) {
  console.log(
    `[check:endpoints] No ${CONFIG_FILE}: this repo has not adopted the payload contract; nothing to check.`,
  );
  process.exit(0);
}

/* 1. The switch */
if (config.encryption !== 'strict') {
  fail(
    'switch',
    `${CONFIG_FILE} says "${config.encryption}"; commit "strict" and debug with PAYLOAD_MODE=off in your shell`,
  );
}

/* 2. Registry drift */
const specPath = join(ROOT, config.spec);
const registry = await registryOf(config);
if (!existsSync(specPath)) {
  fail(
    'spec',
    `${config.spec} not found; export it (backend) or copy the backend's (frontend), then generate:endpoints`,
  );
} else {
  const expected = deriveEndpoints(JSON.parse(readFileSync(specPath, 'utf8')), config.exemptions);
  const names = new Set(expected.map((endpoint) => endpoint.name));
  for (const want of expected) {
    const got = registry.generated[want.name];
    if (!isRecord(got)) {
      fail(
        'registry drift',
        `${want.name} (${want.method} ${want.pattern}) is missing; run bun run generate:endpoints`,
      );
    } else if (
      got.method !== want.method ||
      got.pattern !== want.pattern ||
      got.encryption !== want.encryption ||
      got.reason !== want.reason
    ) {
      fail(
        'registry drift',
        `${want.name} differs from what ${config.spec} and the exemptions imply; run bun run generate:endpoints`,
      );
    }
  }
  for (const name of Object.keys(registry.generated)) {
    if (!names.has(name))
      fail('registry drift', `${name} is not in ${config.spec}; run bun run generate:endpoints`);
  }
  const patterns = new Set(expected.map((endpoint) => `${endpoint.method} ${endpoint.pattern}`));
  for (const route of Object.keys(config.exemptions)) {
    if (!patterns.has(route))
      fail(
        'stale exemption',
        `${route} is exempted in ${CONFIG_FILE} but ${config.spec} has no such operation`,
      );
  }
}

/* 3. Reasons */
for (const [name, entry] of Object.entries(registry.all)) {
  const policy = isRecord(entry) ? entry.encryption : undefined;
  const reason = isRecord(entry) ? entry.reason : undefined;
  const hasReason = typeof reason === 'string' && reason.trim() !== '';
  if (policy !== 'strict' && !hasReason)
    fail('unjustified exemption', `${name} is "${String(policy)}" with no reason`);
  if (policy === 'strict' && reason !== undefined)
    fail('stray reason', `${name} is strict but carries a reason, which reads as an exemption`);
}
for (const rule of registry.prefixes) {
  const reason = isRecord(rule) ? rule.reason : undefined;
  if (typeof reason !== 'string' || reason.trim() === '')
    fail('unjustified prefix', `a prefix rule has no reason: ${JSON.stringify(rule)}`);
}

/* 4. Route literals and 5. raw transport */
const files = sourceFiles(join(ROOT, 'src'));
const literalAllow = [`${config.registry}/`, ...config.routeLiterals.allow];
const escaped = config.routeLiterals.prefix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const literal = new RegExp(`['"\`](${escaped}[A-Za-z0-9\\-{}$():/[\\]._+]*)['"\`]`, 'g');
for (const file of files) {
  const rel = relative(ROOT, file).split('\\').join('/');
  if (isTest(rel)) continue;
  const code = codeOnly(readFileSync(file, 'utf8'));
  if (!allowed(rel, literalAllow)) {
    for (const match of code.matchAll(literal)) {
      fail(
        'route literal',
        `${rel}:${lineOf(code, match.index)} names '${match[1]}'; take it from ${config.registry}/endpoints.ts`,
      );
    }
  }
  if (config.fetchAllow && !allowed(rel, config.fetchAllow)) {
    for (const match of code.matchAll(/\bfetch\s*\(|\bXMLHttpRequest\b|\baxios\b/g)) {
      fail(
        'raw transport',
        `${rel}:${lineOf(code, match.index)} sends a request outside the transport (${config.fetchAllow.join(', ')})`,
      );
    }
  }
}
if (files.length === 0) fail('scan', 'read 0 source files under src/; the scan did not run');

/* 6. Generated client URLs */
const generatedClient = join(ROOT, 'src/lib/api/generated');
const shape = (pattern: string): string => pattern.replace(/:[^/]+/g, ':p');
if (existsSync(generatedClient)) {
  const known = new Set(
    Object.values(registry.all).flatMap((entry) =>
      isRecord(entry) && typeof entry.pattern === 'string' ? [shape(entry.pattern)] : [],
    ),
  );
  for (const file of sourceFiles(generatedClient)) {
    for (const match of readFileSync(file, 'utf8').matchAll(/return\s+`(\/[^`?]*)(?:\?|`)/g)) {
      const path = (match[1] ?? '').replace(/\$\{[^}]+\}/g, ':p');
      if (!known.has(path))
        fail(
          'unregistered generated route',
          `${relative(ROOT, file)} builds ${path}, which the registry does not hold`,
        );
    }
  }
}

/* 7. Peers */
for (const peer of config.peers) {
  const peerRoot = resolve(ROOT, peer.root);
  const peerConfig = existsSync(peerRoot) ? readPayloadConfig(peerRoot) : null;
  if (!peerConfig) {
    console.log(
      `[check:endpoints] SKIPPED peer ${peer.name}: no ${CONFIG_FILE} at ${peer.root} (not checked out here)`,
    );
    continue;
  }
  const theirs = join(peerRoot, peerConfig.spec);
  if (existsSync(specPath) && existsSync(theirs) && canonical(specPath) !== canonical(theirs)) {
    fail(
      'spec parity',
      `${config.spec} differs from ${peer.name}'s; copy the owner's spec and regenerate`,
    );
  }
  if (
    JSON.stringify(sortKeys(config.exemptions)) !== JSON.stringify(sortKeys(peerConfig.exemptions))
  ) {
    fail(
      'policy parity',
      `the exemptions in ${CONFIG_FILE} differ from ${peer.name}'s; both sides must seal the same routes`,
    );
  }
}

if (problems.length > 0) {
  console.error(`[check:endpoints] ✗ ${problems.length} problem(s):`);
  for (const problem of problems) console.error(`  ${problem}`);
  console.error('  See .claude/PAYLOAD-CONTRACT.md.');
  process.exit(1);
}
console.log(
  `[check:endpoints] ✓ ${Object.keys(registry.all).length} registered endpoint(s); read ${files.length} source file(s); all checks passed.`,
);
