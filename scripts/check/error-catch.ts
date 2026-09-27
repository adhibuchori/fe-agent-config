#!/usr/bin/env bun
/**
 * No failure is swallowed without saying so (.claude/rules/common/error-codes.md).
 *
 * A bare `catch {` cannot read what went wrong, so everything it catches gets the same line: a
 * missing key, a rejected request and an outage all reach people as one sentence. In hooks and
 * components, where failures turn into what people read, a bare `catch` must open with
 * `/* error ignored: <why> *\/` so the choice is written down and reviewable. A bound
 * `catch (error)` that never reads `error` is already refused by the linter's `no-unused-vars`.
 */

import { readdirSync, readFileSync, statSync } from 'fs';
import { dirname, join, relative } from 'path';
import { fileURLToPath } from 'url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const SCANNED = ['src/hooks', 'src/components'];
const MARKER = '/* error ignored:';

/* A layer the app does not have yet has nothing to check; it is not an error. */
function* sourceFiles(dir: string): Generator<string> {
  let entries: string[];
  try {
    entries = readdirSync(dir);
  } catch {
    return;
  }
  for (const entry of entries) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) yield* sourceFiles(path);
    else if (/\.tsx?$/.test(entry) && !/\.test\.tsx?$/.test(entry)) yield path;
  }
}

const failures: string[] = [];
let scanned = 0;
for (const dir of SCANNED) {
  for (const path of sourceFiles(join(ROOT, dir))) {
    scanned++;
    const lines = readFileSync(path, 'utf8').split('\n');
    for (const [index, line] of lines.entries()) {
      if (!/\bcatch\s*\{/.test(line)) continue;
      const firstInside = lines.slice(index + 1).find((next) => next.trim().length > 0) ?? '';
      if (!firstInside.trim().startsWith(MARKER)) {
        failures.push(`${relative(ROOT, path)}:${index + 1}`);
      }
    }
  }
}

if (failures.length > 0) {
  console.error(
    `[error-catch] ✗ ${failures.length} bare catch block(s) swallow a failure unexplained:`,
  );
  for (const failure of failures) console.error(`  - ${failure}`);
  console.error(
    `  Bind the error and resolve it through the app's error-message helper, or open the block with ${MARKER} <why> */.`,
  );
  process.exit(1);
}

console.log(
  `[error-catch] ✓ Every bare catch in hooks and components states why it ignores the error (${scanned} files read).`,
);
