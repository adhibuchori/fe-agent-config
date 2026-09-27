#!/usr/bin/env bun
/**
 * Every error code the API can send has a message here (.claude/rules/common/error-codes.md).
 *
 * The backend publishes its closed code list as the `Problem.code` enum in `openapi.json`. A code
 * this app has no row for resolves to `unknown`, which people read as "Something went wrong" — a
 * named failure (a rejected key, a file that was too large) reaching them as no information at
 * all. This fails the gate on any code that is neither mapped to a key in
 * `src/lib/errors/problem-key.ts` (`CODE_TO_KEY`, or `AUTH_CODE_TO_KEY` in
 * `src/lib/auth/auth-error.ts` where the app has an auth library) nor listed below with the reason
 * it needs none.
 *
 * Also fails on a stale exemption or problem-table row (a code the spec does not have) and on a code
 * both mapped and exempted, so neither the table nor the lists below can quietly rot. An app with
 * no `problem-key.ts` yet has nothing to check and says so.
 */

import { existsSync, readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const PROBLEM_KEY = join(ROOT, 'src/lib/errors/problem-key.ts');
const AUTH_ERROR = join(ROOT, 'src/lib/auth/auth-error.ts');
const SPEC = join(ROOT, 'openapi.json');

/* Handled by a hook before any table is read, because the right response is not a message.
   Example: `LOGIN_THROTTLED: 'the sign-in form shows a countdown instead of a dialog'`. */
const INTERCEPTED: Record<string, string> = {};

/* Carries no meaning beyond its HTTP status, so the status row in problem-key.ts is the answer.
   Example: `HTTP_ERROR: 'an HTTP exception with no dedicated code; the status row resolves it'`. */
const STATUS_RESOLVED: Record<string, string> = {};

/* Raised on routes this app never calls. Listed rather than mapped so a new one is a decision.
   Example: `INVALID_WEBHOOK_SIGNATURE: 'the payment webhook, called by the provider'`. */
const NOT_SENT_HERE: Record<string, string> = {};

interface Spec {
  components?: { schemas?: { Problem?: { properties?: { code?: { enum?: unknown } } } } };
}

/** The string-keyed table a module exports under `name`, or an empty one when it has none. */
async function tableFrom(path: string, name: string): Promise<Record<string, unknown>> {
  if (!existsSync(path)) return {};
  const mod: unknown = await import(path);
  const table = typeof mod === 'object' && mod !== null ? Reflect.get(mod, name) : undefined;
  if (typeof table !== 'object' || table === null) {
    console.error(`[error-codes] ✗ ${path} does not export ${name}.`);
    process.exit(1);
  }
  return table as Record<string, unknown>;
}

if (!existsSync(PROBLEM_KEY)) {
  console.log('[error-codes] No src/lib/errors/problem-key.ts in this repo - nothing to check.');
  process.exit(0);
}
if (!existsSync(SPEC)) {
  console.error(
    '[error-codes] ✗ problem-key.ts exists but openapi.json does not — copy the API spec.',
  );
  process.exit(1);
}

const spec = JSON.parse(readFileSync(SPEC, 'utf8')) as Spec;
const published = spec.components?.schemas?.Problem?.properties?.code?.enum;
if (!Array.isArray(published) || published.length === 0) {
  console.error('[error-codes] ✗ openapi.json has no Problem.code enum — re-copy the API spec.');
  process.exit(1);
}

const problemTable = await tableFrom(PROBLEM_KEY, 'CODE_TO_KEY');
const authTable = await tableFrom(AUTH_ERROR, 'AUTH_CODE_TO_KEY');

const codes = new Set(published.filter((code): code is string => typeof code === 'string'));
const mapped = new Set([...Object.keys(problemTable), ...Object.keys(authTable)]);
const exempt: Record<string, string> = { ...INTERCEPTED, ...STATUS_RESOLVED, ...NOT_SENT_HERE };

const failures: string[] = [];
for (const code of codes) {
  if (!mapped.has(code) && !(code in exempt)) {
    failures.push(`${code}: no row in src/lib/errors/problem-key.ts and no exemption here`);
  }
}
/* A problem-table row for a code the API never sends is dead, or a typo that hides the real one.
   The auth table is exempt from this: most of it is the auth library's own vocabulary. */
for (const code of Object.keys(problemTable)) {
  if (!codes.has(code))
    failures.push(`${code}: mapped in problem-key.ts but the API never sends it`);
}
for (const [code, reason] of Object.entries(exempt)) {
  if (!reason.trim()) failures.push(`${code}: exempted here without a reason`);
  if (!codes.has(code)) failures.push(`${code}: exempted here but no longer in openapi.json`);
  if (mapped.has(code)) failures.push(`${code}: both mapped and exempted — drop the exemption`);
}

if (failures.length > 0) {
  console.error(`[error-codes] ✗ ${failures.length} problem(s):`);
  for (const failure of failures) console.error(`  - ${failure}`);
  console.error(
    '  Map each new code to a key with copy in every locale, or exempt it with a reason.',
  );
  process.exit(1);
}

console.log(`[error-codes] ✓ All ${codes.size} API error codes have a message or a stated reason.`);
