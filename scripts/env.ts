#!/usr/bin/env bun
/**
 * Environment file bootstrap and preflight.
 *
 *   bun run scripts/env.ts init                    create .env.<target> from its template
 *   bun run scripts/env.ts check <target> [--soft] verify the file exists and is complete
 *
 * Next.js already loads `.env.development` for `next dev` and `.env.production`
 * for `next build` / `next start`, so this script does not inject anything — it
 * only makes the active file explicit and stops a command before it starts with
 * a half-configured environment.
 *
 * `--soft` downgrades every failure to a warning. `build` and `start` use it
 * because in Docker and CI the values arrive as real environment variables and
 * no `.env.production` file exists (it is gitignored and .dockerignored).
 */

import { copyFileSync, existsSync, readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const TARGETS = ['development', 'production'] as const;

type Target = (typeof TARGETS)[number];

function envPath(target: Target, template = false): string {
  return join(ROOT, `.env.${target}${template ? '.example' : ''}`);
}

/** Lib: parseEntries
 * Reads KEY=value pairs from a dotenv file, skipping blanks and comments.
 */
function parseEntries(contents: string): Map<string, string> {
  const entries = new Map<string, string>();

  for (const line of contents.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;

    const separator = trimmed.indexOf('=');
    if (separator === -1) continue;

    entries.set(trimmed.slice(0, separator).trim(), trimmed.slice(separator + 1).trim());
  }

  return entries;
}

function report(message: string, soft: boolean): void {
  if (soft) {
    console.warn(`[env] ${message} — continuing on ambient environment`);
    return;
  }

  console.error(`[env] ${message}`);
  process.exit(1);
}

/** Lib: check
 * Verifies `.env.<target>` exists and defines every key its template requires.
 * A key is required when the template gives it a non-empty value; a template
 * entry left empty (SENTRY_DSN=) is optional by construction.
 */
function check(target: Target, soft: boolean): void {
  const file = envPath(target);

  if (!existsSync(file)) {
    report(`.env.${target} not found — run \`bun run env:init\` to create it`, soft);
    return;
  }

  const actual = parseEntries(readFileSync(file, 'utf8'));
  const templateFile = envPath(target, true);
  const template = existsSync(templateFile)
    ? parseEntries(readFileSync(templateFile, 'utf8'))
    : new Map<string, string>();

  const missing = [...template.entries()]
    .filter(([key, value]) => value !== '' && !actual.get(key))
    .map(([key]) => key);

  if (missing.length > 0) {
    report(`.env.${target} has no value for: ${missing.join(', ')}`, soft);
    return;
  }

  console.log(`[env] ${target} -> .env.${target} (${actual.size} vars)`);
}

/** Lib: init
 * Copies each template to its real file. Never overwrites an existing file —
 * running this twice is safe and is the documented way to refresh a clone.
 * A missing template exits non-zero: otherwise `init` would report success
 * while `check` keeps telling you to run `init`, with no way out of the loop.
 */
function init(): void {
  let missingTemplate = false;

  for (const target of TARGETS) {
    const file = envPath(target);
    const template = envPath(target, true);

    if (!existsSync(template)) {
      console.error(`[env] .env.${target}.example is missing from this repo`);
      missingTemplate = true;
      continue;
    }

    if (existsSync(file)) {
      console.log(`[env] .env.${target} already exists — left untouched`);
      continue;
    }

    copyFileSync(template, file);
    console.log(`[env] created .env.${target} from .env.${target}.example`);
  }

  if (missingTemplate) process.exit(1);
}

const [command, ...args] = process.argv.slice(2);

if (command === 'init') {
  init();
} else if (command === 'check') {
  const target = args.find((arg) => !arg.startsWith('--'));

  if (!TARGETS.includes(target as Target)) {
    console.error(`[env] usage: env.ts check <${TARGETS.join('|')}> [--soft]`);
    process.exit(1);
  }

  check(target as Target, args.includes('--soft'));
} else {
  console.error('[env] usage: env.ts init | env.ts check <target> [--soft]');
  process.exit(1);
}
