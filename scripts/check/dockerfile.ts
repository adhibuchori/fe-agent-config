#!/usr/bin/env bun
/**
 * The production image builds what the quality gate validated.
 *
 * The gate and the image are two environments, and nothing compares them unless something does:
 *
 *   D1  A client generated into a gitignored folder (src/lib/api/generated/) is generated in the
 *       image before the build. The gate generates it; an image that does not fails at the first
 *       import, or ships whatever stale copy the build context held.
 *   D2  A base image pinned by digest carries a version in its tag (`image:1.2-slim@sha256:…`). The
 *       digest decides what is pulled; the tag is what makes a stale pin readable in review.
 *   D3  Under Bun, the image's pinned Bun is not older than the Bun running this check: the gate
 *       proved the code on this one, and a runtime fix ships in a patch release.
 *
 * No Dockerfile: says so and passes. A Dockerfile with no source under src/ fails: D1 could not
 * be checked. Exit 1 on any violation.
 */

import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const DOCKERFILE = join(ROOT, 'Dockerfile');
/* The import path of the generated client, and the package script that produces it. */
const GENERATED_IMPORT = 'api/generated';
const GENERATE_SCRIPT = 'generate:api';

function sources(dir: string, out: string[] = []): string[] {
  if (!existsSync(dir)) return out;
  for (const entry of readdirSync(dir)) {
    if (entry === 'node_modules' || entry === 'generated') continue;
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) sources(full, out);
    else if (/\.(ts|tsx)$/.test(entry)) out.push(full);
  }
  return out;
}

if (!existsSync(DOCKERFILE)) {
  console.log('[check:dockerfile] No Dockerfile: this repo builds no image; nothing to check.');
  process.exit(0);
}
const lines = readFileSync(DOCKERFILE, 'utf8').split('\n');
const files = sources(join(ROOT, 'src')).filter(
  (f) => !/\/(testing|__tests__)\/|\.(test|spec)\.tsx?$/.test(f),
);
if (files.length === 0) {
  console.error('[check:dockerfile] ✗ no source files under src/: D1 could not be checked.');
  process.exit(1);
}
const errors: string[] = [];

/* D1: only value imports count; `import type` is erased and cannot fail the build. */
const consumers = files.filter((file) =>
  readFileSync(file, 'utf8')
    .split('\n')
    .some((line) => line.includes(GENERATED_IMPORT) && !/^\s*import\s+type\b/.test(line)),
);
if (consumers.length > 0) {
  const at = (pattern: RegExp): number => lines.findIndex((line) => pattern.test(line));
  const build = at(/^\s*RUN\s+(?:bun|npm|pnpm|yarn)\s+(?:run\s+)?build\s*(?:&&|$)/);
  const generate = at(
    new RegExp(`^\\s*RUN\\s+(?:bun|npm|pnpm|yarn)\\s+(?:run\\s+)?${GENERATE_SCRIPT}(?:\\s|&&|$)`),
  );
  if (generate === -1) {
    errors.push(
      `D1 ${consumers.length} file(s) import ${GENERATED_IMPORT}, which git does not carry ` +
        `(first: ${relative(ROOT, consumers[0] ?? '')}); add RUN <pm> run ${GENERATE_SCRIPT} before the build.`,
    );
  } else if (build !== -1 && generate > build) {
    errors.push(
      `D1 Dockerfile:${generate + 1} generates the client after the build on line ${build + 1}; move it above.`,
    );
  }
}

/* D2: `FROM [--flag…] image[:tag]@sha256:…` needs a tag with a digit that is not a bare variant. */
const VARIANT_ONLY = /^(alpine|latest|slim|bookworm|bullseye|trixie|distroless)$/;
for (const [index, line] of lines.entries()) {
  const match = /^FROM(?:\s+--\S+)*\s+([^\s@:]+)(?::([^\s@]+))?(@sha256:[a-f0-9]{64})?/i.exec(line);
  if (!match?.[3]) continue;
  const tag = match[2] ?? '';
  if (tag && !VARIANT_ONLY.test(tag) && /\d/.test(tag)) continue;
  errors.push(
    `D2 Dockerfile:${index + 1} pins ${match[1]} by digest with no version in the tag; write image:<version>-<variant>@sha256:…`,
  );
}

/* D3: only meaningful under Bun, where the running version is the one the gate used. */
const running = (process.versions.bun ?? '').split('.').map(Number);
for (const [index, line] of lines.entries()) {
  const match = /^FROM(?:\s+--\S+)*\s+oven\/bun:(\d+)\.(\d+)\.(\d+)/.exec(line);
  if (!match || running.length !== 3) continue;
  const pinned = [Number(match[1]), Number(match[2]), Number(match[3])];
  const behind = [0, 1, 2].some(
    (i) =>
      pinned.slice(0, i).every((v, j) => v === running[j]) && (pinned[i] ?? 0) < (running[i] ?? 0),
  );
  if (behind)
    errors.push(
      `D3 Dockerfile:${index + 1} pins Bun ${pinned.join('.')}, behind the ${running.join('.')} that ran the gate; repin.`,
    );
}

if (errors.length > 0) {
  console.error(`[check:dockerfile] ✗ ${errors.length} violation(s):`);
  for (const error of errors) console.error(`  ${error}`);
  process.exit(1);
}
console.log(
  `[check:dockerfile] ✓ Read the Dockerfile and ${files.length} source file(s): the image builds what the gate validated.`,
);
