#!/usr/bin/env bun
/**
 * Every loading skeleton a screen renders is measured against that screen, or named as not yet.
 *
 * The measuring harness (a dev-only page that draws each registered real component beside its
 * skeleton, run by `bun run measure:skeletons`) proves a pair to half a pixel, but only the pairs
 * someone registered. A skeleton sized from comments about the component, and never measured,
 * reads as careful and ships hundreds of pixels off. `.claude/rules/web/skeletons.md` S5.
 *
 * A skeleton is a `*-skeleton*.tsx` file. It needs a pair once a file that is not a skeleton, a
 * test or the harness imports it: a screen swapping it in. It counts as paired when the harness
 * reaches it through its imports, however deep. One not paired yet is listed in UNMEASURED with a
 * reason; an entry that is paired now, or names no rendered skeleton, fails too, so the list
 * cannot rot. Imports are read as text (`@/` and relative paths), with comments and re-exports
 * removed first. Reachable is not rendered: whether the pair shows the right state is the
 * harness's question, not this file's.
 */

import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, normalize, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
/* Where the harness lives, what runs it, and the reasoned list of pairs still owed. */
const HARNESS = 'src/app/[locale]/dev/measure/';
const MEASURER = 'scripts/measure/skeletons.ts';
const UNMEASURED = 'scripts/measure/unmeasured-skeletons.json';
const SKELETON = /-skeleton[\w-]*\.tsx$/;
const TEST = /(^src\/(testing|test)\/|__tests__\/|\.(test|spec)\.tsx?$)/;

interface Entry {
  path: string;
  reason: string;
}

function collect(dir: string, out: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) collect(full, out);
    else if (/\.(ts|tsx)$/.test(entry) && !entry.endsWith('.d.ts')) {
      out.push(relative(ROOT, full).split('\\').join('/'));
    }
  }
  return out;
}

/* The modules a file imports, as repo paths without extension; comments and re-exports dropped. */
function importsOf(file: string): string[] {
  const code = readFileSync(join(ROOT, file), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:'"`])\/\/.*$/gm, '$1')
    .replace(/export\s+(?:type\s+)?(?:\*|\{[^}]*\})(?:\s+as\s+\w+)?\s+from\s*['"][^'"]+['"]/g, '');
  return [...code.matchAll(/(?:from|import\()\s*['"]([^'"]+)['"]/g)].flatMap(([, spec = '']) => {
    if (spec.startsWith('@/'))
      return [
        normalize(join('src', spec.slice(2)))
          .split('\\')
          .join('/'),
      ];
    if (spec.startsWith('.'))
      return [
        normalize(join(dirname(file), spec))
          .split('\\')
          .join('/'),
      ];
    return [];
  });
}

if (!existsSync(join(ROOT, HARNESS))) {
  if (existsSync(join(ROOT, MEASURER))) {
    console.error(`[check:skeleton-pairs] ✗ ${MEASURER} exists but ${HARNESS} does not.`);
    process.exit(1);
  }
  console.log(`[check:skeleton-pairs] No measuring harness at ${HARNESS}; nothing to pair.`);
  process.exit(0);
}

const files = collect(join(ROOT, 'src'));
const known = new Set(files);
const fileOf = (module: string): string | undefined =>
  [`${module}.tsx`, `${module}.ts`, `${module}/index.tsx`, `${module}/index.ts`].find((f) =>
    known.has(f),
  );
const edges = new Map<string, string[]>();
const importers = new Map<string, string[]>();
for (const file of files) {
  const targets = importsOf(file).flatMap((module) => fileOf(module) ?? []);
  edges.set(file, targets);
  for (const target of targets) importers.set(target, [...(importers.get(target) ?? []), file]);
}

const reachable = new Set<string>();
const queue = files.filter((file) => file.startsWith(HARNESS));
for (let file = queue.pop(); file !== undefined; file = queue.pop()) {
  if (reachable.has(file)) continue;
  reachable.add(file);
  queue.push(...(edges.get(file) ?? []));
}

const skeletons = files
  .filter((file) => SKELETON.test(file))
  .map((file) => ({
    file,
    screen: (importers.get(file) ?? []).find(
      (f) => !SKELETON.test(f) && !TEST.test(f) && !f.startsWith(HARNESS),
    ),
    paired: reachable.has(file),
  }))
  .filter((skeleton) => skeleton.screen !== undefined);

const listed: Entry[] = existsSync(join(ROOT, UNMEASURED))
  ? JSON.parse(readFileSync(join(ROOT, UNMEASURED), 'utf8'))
  : [];
const problems: string[] = [];
for (const { file, screen, paired } of skeletons) {
  if (paired || listed.some((entry) => entry.path === file)) continue;
  problems.push(
    `${file}: rendered by ${screen} and not paired in ${HARNESS}. Register its real component and ` +
      `skeleton there (the skeleton skill), or list it in ${UNMEASURED} with the reason.`,
  );
}
for (const entry of listed) {
  const skeleton = skeletons.find((s) => s.file === entry.path);
  if (!entry.reason?.trim()) problems.push(`${UNMEASURED}: ${entry.path} has no reason.`);
  else if (!skeleton)
    problems.push(`${UNMEASURED}: ${entry.path} is not a skeleton a screen renders; drop it.`);
  else if (skeleton.paired)
    problems.push(`${UNMEASURED}: ${entry.path} is paired now; drop the entry.`);
}
if (files.length === 0) problems.push('read 0 files under src/; the scan did not run');

console.log(
  `[check:skeleton-pairs] Read ${files.length} files: ${skeletons.length} skeleton(s) a screen renders, ` +
    `${skeletons.filter((s) => s.paired).length} paired, ${listed.length} listed as not yet measured.`,
);
for (const problem of problems) console.error(`  ✗ ${problem}`);
if (problems.length > 0) process.exit(1);
console.log(
  '[check:skeleton-pairs] ✓ Every skeleton a screen renders is paired or listed with a reason.',
);
