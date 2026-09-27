#!/usr/bin/env bun
/**
 * Writes the generated half of the endpoint registry from the OpenAPI spec and the exemptions in
 * payload.config.json (.claude/PAYLOAD-CONTRACT.md § Registry).
 *
 *   bun run generate:endpoints
 *
 * Never edit the output by hand: an encryption policy typed into it would be reverted by the next
 * run, the worst way for a security decision to disappear. Decide policies in payload.config.json
 * `exemptions`, with a reason, and regenerate. `check:endpoints` derives the same content and
 * fails on any difference, so a hand edit blocks the gate instead of surviving.
 */

import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CONFIG_FILE,
  deriveEndpoints,
  readPayloadConfig,
  type DerivedEndpoint,
} from '../lib/openapi-endpoints';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');

const config = readPayloadConfig(ROOT);
if (!config) {
  console.error(`generate:endpoints: no ${CONFIG_FILE}; the payload contract is not adopted here.`);
  process.exit(1);
}
const specPath = join(ROOT, config.spec);
if (!existsSync(specPath)) {
  console.error(`generate:endpoints: ${config.spec} not found. Export or copy the spec first.`);
  process.exit(1);
}

const out = join(ROOT, config.registry, 'endpoints.generated.ts');
const policyImport = relative(join(ROOT, config.registry), join(ROOT, 'src/lib/payload/policy'))
  .split('\\')
  .join('/');
const endpoints = deriveEndpoints(JSON.parse(readFileSync(specPath, 'utf8')), config.exemptions);

function entry(endpoint: DerivedEndpoint): string {
  const reason =
    endpoint.reason === undefined ? '' : `\n    reason: ${JSON.stringify(endpoint.reason)},`;
  return [
    `  ${endpoint.name}: {`,
    `    method: '${endpoint.method}',`,
    `    pattern: '${endpoint.pattern}',`,
    `    encryption: '${endpoint.encryption}',${reason}`,
    '  },',
  ].join('\n');
}

const body = `/**
 * Generated from \`${config.spec}\` by \`scripts/generate/endpoints.ts\`. Do not edit.
 *
 * Regenerate with \`bun run generate:endpoints\`. Encryption policy is decided in
 * ${CONFIG_FILE} \`exemptions\`, never here; \`check:endpoints\` fails on any hand edit.
 */

import type { EndpointMap } from '${policyImport.startsWith('.') ? policyImport : `./${policyImport}`}';

export const GENERATED_ENDPOINTS = {
${endpoints.map(entry).join('\n')}
} as const satisfies EndpointMap;
`;

writeFileSync(out, body);
console.log(`generate:endpoints: wrote ${endpoints.length} endpoint(s) to ${relative(ROOT, out)}`);
