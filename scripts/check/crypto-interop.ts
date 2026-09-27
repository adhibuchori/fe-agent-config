#!/usr/bin/env bun
/**
 * Proves this repo's payload cipher still speaks the shared wire format
 * (.claude/PAYLOAD-CONTRACT.md § Tests and interop).
 *
 * Independent copies of one format fail in one way worth guarding: each copy passes its own
 * suite, and the break shows only when two services talk. So this runs the copy in
 * src/lib/payload against the shared known-answer vectors (the AAD string byte for byte, the
 * committed ciphertext opened, every reject refused), round-trips a body, and, for each peer in
 * payload.config.json that is checked out beside this repo, seals with one copy and opens with the
 * other in both directions. A peer that is not checked out is reported as skipped, never passed.
 */

import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import type * as AesModule from '../../src/lib/payload/aes-gcm';
import type * as B64Module from '../../src/lib/payload/base64url';
import type * as CodecModule from '../../src/lib/payload/codec';
import type * as EnvModule from '../../src/lib/payload/envelope';
import { CONFIG_FILE, readPayloadConfig } from '../lib/openapi-endpoints';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const VECTORS = join(ROOT, 'scripts/check/payload-vectors.json');
const problems: string[] = [];
const BODY = { check: 'crypto-interop', n: 1 };

interface Vector {
  name: string;
  kind: string;
  method?: string;
  status?: number;
  pattern: string;
  kid: string;
  ts: number;
  plaintext: unknown;
  aad: string;
  iv: string;
  ct: string;
}

type Aes = typeof AesModule;
type B64 = typeof B64Module;
type Env = typeof EnvModule;
type Codec = typeof CodecModule;

/** One copy of the implementation: this repo's, or a peer's. */
interface Impl {
  aes: Aes;
  b64: B64;
  env: Env;
  codec: Codec;
}

const CONSTANTS = [
  'ENCRYPTED_MEDIA_TYPE',
  'ENVELOPE_VERSION',
  'ENVELOPE_ALG',
  'EPK_HEADER',
  'KID_HEADER',
  'MAX_CLOCK_SKEW_MS',
] as const;

/* Loaded by path, typed by this repo's copy: a peer that lacks an export fails when it is called,
   and that failure is reported as the drift it is. */
async function load(dir: string): Promise<Impl> {
  const at = (name: string): string => pathToFileURL(join(dir, `${name}.ts`)).href;
  const aes: Aes = await import(at('aes-gcm'));
  const b64: B64 = await import(at('base64url'));
  const env: Env = await import(at('envelope'));
  const codec: Codec = await import(at('codec'));
  return { aes, b64, env, codec };
}

async function refuses(promise: Promise<unknown>): Promise<boolean> {
  try {
    await promise;
    return false;
  } catch {
    return true;
  }
}

const config = readPayloadConfig(ROOT);
if (!config) {
  console.log(
    `[check:crypto-interop] No ${CONFIG_FILE}: this repo has not adopted the payload contract; nothing to check.`,
  );
  process.exit(0);
}
const ours = join(ROOT, 'src/lib/payload');
if (!existsSync(ours)) {
  console.error(
    `[check:crypto-interop] ✗ ${CONFIG_FILE} exists but src/lib/payload/ does not: nothing implements the contract.`,
  );
  process.exit(1);
}
const impl = await load(ours);

/* The shared vectors */
interface VectorFile {
  testBytes: string;
  vectors: Vector[];
  rejects: { name: string; vector: string; aad: string }[];
}
const file: VectorFile = JSON.parse(readFileSync(VECTORS, 'utf8'));
const { aes, b64, env, codec } = impl;
const key = await aes.importAesKey(b64.fromBase64Url(file.testBytes));
const reason = (error: unknown): string => (error instanceof Error ? error.message : String(error));

async function checkVector(v: Vector): Promise<string[]> {
  const found: string[] = [];
  const aad =
    v.kind === 'request'
      ? env.requestAad(v.method ?? '', v.pattern, v.kid, v.ts)
      : env.responseAad(v.status ?? 0, v.pattern, v.kid, v.ts);
  if (b64.utf8String(aad) !== v.aad)
    found.push(`vector ${v.name}: AAD "${b64.utf8String(aad)}" is not "${v.aad}"`);
  try {
    const iv = b64.fromBase64Url(v.iv);
    const plain = await aes.open(key, iv, b64.fromBase64Url(v.ct), b64.utf8Bytes(v.aad));
    if (JSON.stringify(JSON.parse(b64.utf8String(plain))) !== JSON.stringify(v.plaintext)) {
      found.push(`vector ${v.name}: opened to another body`);
    }
  } catch (error) {
    found.push(`vector ${v.name}: did not open (${reason(error)})`);
  }
  return found;
}

async function checkReject(r: VectorFile['rejects'][number]): Promise<string[]> {
  const v = file.vectors.find((candidate) => candidate.name === r.vector);
  if (!v) return [`reject ${r.name}: names no vector`];
  const iv = b64.fromBase64Url(v.iv);
  const opened = !(await refuses(aes.open(key, iv, b64.fromBase64Url(v.ct), b64.utf8Bytes(r.aad))));
  return opened ? [`reject ${r.name}: opened, but it must be refused`] : [];
}

/* A round trip, and a route mismatch that must be refused, through the JSON codec. */
async function checkRoundTrip(): Promise<string[]> {
  const found: string[] = [];
  const roundKey = await aes.importAesKey(crypto.getRandomValues(new Uint8Array(32)));
  const aadFor = (pattern: string) => (kid: string, ts: number) =>
    env.requestAad('POST', pattern, kid, ts);
  const envelope = await codec.sealJson(BODY, {
    key: roundKey,
    kid: 'k1',
    aadFor: aadFor('/api/a'),
  });
  const back = await codec.openJson(envelope, { key: roundKey, aadFor: aadFor('/api/a') });
  if (JSON.stringify(back) !== JSON.stringify(BODY))
    found.push('round trip: a sealed body did not open to itself');
  if (!(await refuses(codec.openJson(envelope, { key: roundKey, aadFor: aadFor('/api/b') })))) {
    found.push('round trip: an envelope for one route opened on another');
  }
  return found;
}

/* A peer: seal with one copy, open with the other, both ways. */
async function checkPeer(peer: { name: string; root: string }): Promise<string[]> {
  const theirsDir = join(resolve(ROOT, peer.root), 'src/lib/payload');
  if (!existsSync(theirsDir)) {
    console.log(
      `[check:crypto-interop] SKIPPED peer ${peer.name}: ${peer.root}/src/lib/payload is not checked out here`,
    );
    return [];
  }
  try {
    const theirs = await load(theirsDir);
    const found = CONSTANTS.filter((name) => theirs.env[name] !== env[name]).map(
      (name) =>
        `peer ${peer.name}: ${name} is ${String(theirs.env[name])}, here ${String(env[name])}`,
    );
    const material = crypto.getRandomValues(new Uint8Array(32));
    const [ourKey, theirKey] = await Promise.all([
      aes.importAesKey(material),
      theirs.aes.importAesKey(material),
    ]);
    const ourAad = (kid: string, ts: number) => env.requestAad('PATCH', '/api/x/:id', kid, ts);
    const theirAad = (kid: string, ts: number) =>
      theirs.env.requestAad('PATCH', '/api/x/:id', kid, ts);
    const fromUs = await codec.sealJson(BODY, { key: ourKey, kid: 'k1', aadFor: ourAad });
    const fromThem = await theirs.codec.sealJson(BODY, {
      key: theirKey,
      kid: 'k1',
      aadFor: theirAad,
    });
    const opened = await Promise.all([
      theirs.codec.openJson(fromUs, { key: theirKey, aadFor: theirAad }),
      codec.openJson(fromThem, { key: ourKey, aadFor: ourAad }),
    ]);
    if (opened.some((value) => JSON.stringify(value) !== JSON.stringify(BODY)))
      throw new Error('another body');
    return found;
  } catch (error) {
    return [
      `peer ${peer.name}: the two copies no longer open each other's envelopes (${reason(error)})`,
    ];
  }
}

const results = await Promise.all([
  ...file.vectors.map(checkVector),
  ...file.rejects.map(checkReject),
  checkRoundTrip(),
  ...config.peers.map(checkPeer),
]);
problems.push(...results.flat());

if (problems.length > 0) {
  console.error(`[check:crypto-interop] ✗ ${problems.length} problem(s):`);
  for (const problem of problems) console.error(`  ${problem}`);
  console.error(
    '  The cipher drifted from the shared format. Never regenerate the vectors to make this pass.',
  );
  process.exit(1);
}
console.log(
  `[check:crypto-interop] ✓ ${file.vectors.length} vector(s) opened, ${file.rejects.length} replay(s) refused, round trip ok; peers checked: ${config.peers.length}.`,
);
