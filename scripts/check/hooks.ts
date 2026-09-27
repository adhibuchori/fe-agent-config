#!/usr/bin/env bun
/**
 * HOOK — hook folder placement (AGENTS.md Rule 30).
 * See .claude/rules/web/file-organization.md for the rules and the reasoning behind them.
 *
 * Checks for:
 * HOOK-1 Placement — every hook lives in a feature folder, never loose in src/hooks/
 * HOOK-2 Mirroring — folders are kebab-case, and a feature folder has its twin under
 *        src/components/ (api/, shared/ and ui/ are not features and are exempt)
 * HOOK-3 Tests — a test named after a hook sits at the mirrored path under src/testing/hooks/
 * HOOK-4 Uniqueness — no two hooks share a filename, whatever folder they are in
 *
 * Exit code 1 on any violation. There are no warning-only rules here: a hooks folder that is only
 * warned about drifts, because nothing fails while it does.
 */

import { existsSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const HOOKS_DIR = 'src/hooks';
const TESTS_DIR = 'src/testing/hooks';
const COMPONENTS_DIR = 'src/components';
const KEBAB_CASE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
/* Folders that are not features (file-organization rule 3), so they have no component twin. */
const NOT_FEATURES = new Set(['api', 'shared', 'ui']);
/* Empty on purpose: nothing sits loose in src/hooks/, not even a barrel (re-exports are refused
   by check:reexport). */
const ROOT_ALLOWLIST = new Set<string>();

interface HookFile {
  name: string;
  folder: string;
  path: string;
}

/** Walks a directory tree and returns every file path it contains; a missing one is empty. */
function collectFiles(dir: string): string[] {
  let entries: string[];
  try {
    entries = readdirSync(dir);
  } catch {
    return [];
  }
  const files: string[] = [];
  for (const entry of entries) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) files.push(...collectFiles(full));
    else files.push(full);
  }
  return files;
}

const errors: string[] = [];
const hookFiles: HookFile[] = [];
const featureRoots = new Set<string>();

for (const path of collectFiles(HOOKS_DIR)) {
  const rel = relative(HOOKS_DIR, path);
  const segments = rel.split('/');
  const file = segments.at(-1) ?? '';

  if (segments.length === 1) {
    if (!ROOT_ALLOWLIST.has(file)) {
      errors.push(
        `${path}\n    Loose in src/hooks/. Move it into the folder of the feature it serves,\n    matching the src/components/ folder that consumes it. (HOOK-1)`,
      );
    }
    continue;
  }

  for (const folder of segments.slice(0, -1)) {
    if (!KEBAB_CASE.test(folder)) {
      errors.push(`${path}\n    Folder "${folder}" is not kebab-case. (HOOK-2)`);
    }
  }
  featureRoots.add(segments[0] ?? '');

  if (file.endsWith('.ts') && file !== 'index.ts') {
    hookFiles.push({
      name: file.replace(/\.tsx?$/, ''),
      folder: segments.slice(0, -1).join('/'),
      path,
    });
  }
}

/* The mirror is checked at the feature root: hooks/<feature>/ answers components/<feature>/. */
if (existsSync(COMPONENTS_DIR)) {
  for (const root of featureRoots) {
    if (NOT_FEATURES.has(root) || existsSync(join(COMPONENTS_DIR, root))) continue;
    errors.push(
      `${join(HOOKS_DIR, root)}/\n    No src/components/${root}/ to mirror. Name the folder after the feature it serves,\n    or move it under api/, shared/ or ui/ if it is not a feature. (HOOK-2)`,
    );
  }
}

const byName = new Map<string, HookFile[]>();
for (const hook of hookFiles) {
  const existing = byName.get(hook.name) ?? [];
  existing.push(hook);
  byName.set(hook.name, existing);
}

for (const [name, files] of byName) {
  if (files.length > 1) {
    errors.push(
      `${files.map((f) => f.path).join('\n    ')}\n    ${files.length} hooks named "${name}". A generator that keys on the filename (a docs site,\n    a symbol index) sees one of them. (HOOK-4)`,
    );
  }
}

for (const path of collectFiles(TESTS_DIR)) {
  const rel = relative(TESTS_DIR, path);
  const segments = rel.split('/');
  const file = segments.at(-1) ?? '';
  const match = file.match(/^(use[A-Za-z0-9]+)(?:\.[A-Za-z0-9]+)*\.test\.tsx?$/);
  if (!match) continue;

  const hook = byName.get(match[1] ?? '')?.[0];
  if (!hook) continue;

  const actual = segments.slice(0, -1).join('/');
  if (actual !== hook.folder) {
    errors.push(
      `${path}\n    Mirrors ${hook.path}, so it belongs in src/testing/hooks/${hook.folder}/.\n    A test at the wrong path is never found, so it stops running silently\n    instead of failing. (HOOK-3)`,
    );
  }
}

console.log(`[check-hooks] Scanning ${hookFiles.length} hooks and their tests...`);

if (errors.length > 0) {
  console.error(`\n[check-hooks] ✗ ${errors.length} violation(s):\n`);
  for (const error of errors) console.error(`  ${error}\n`);
  console.error('[check-hooks] See .claude/rules/web/file-organization.md for the standard.');
  process.exit(1);
}

console.log('[check-hooks] ✓ Every hook sits in a feature folder with its test alongside.');
