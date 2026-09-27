#!/usr/bin/env node
/**
 * SHAPE — folder shape. Violations are reported as SHAPE-1 to SHAPE-4, the numbers below.
 * See .claude/rules/common/folder-shape.md for the rules and the reasoning behind them.
 *
 * Checks for:
 * 1. Shape — a folder that holds folders holds no loose files
 * 2. Mirroring — a test sits at the path of the source it is named after
 * 3. Naming — no folder or test named for why it was written (`misc`, `final-branches`)
 * 4. Support files — mocks, fixtures and helpers live in their own folders in a test tree
 *
 * Plain Node ESM with no dependencies, so the same file runs under bun in the TypeScript repos and
 * under the runner's node in the Python ones. Exit code 1 on any violation; `--warn` reports and
 * exits 0, for a repo whose existing tree has not been moved yet.
 */

import { existsSync, readdirSync, statSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';

const WARN = process.argv.includes('--warn');
const RULES = '.claude/rules/common/folder-shape.md';

const IS_NEXT = ['next.config.ts', 'next.config.mjs', 'next.config.js'].some((f) => existsSync(f));
const IS_PYTHON = existsSync('pyproject.toml');

const ROOTS = ['src', 'tests', 'scripts', 'components', 'lib'].filter((r) => existsSync(r));

/* Output of a tool, or a cache: nobody chooses its shape, so nobody is held to one. */
const SKIPPED_DIRS = new Set(
  'node_modules __pycache__ .pytest_cache .mypy_cache .ruff_cache .next out dist coverage generated migrations'.split(
    ' ',
  ),
);

/* Route trees: the framework decides that page files sit beside their child routes. */
const ROUTE_TREES = IS_NEXT ? ['src/app', 'app', 'content'] : [];

/* Files a runtime or tool requires at a fixed path. */
const ENTRYPOINTS = new Set(
  'src/app.ts src/index.ts src/env.ts src/proxy.ts src/middleware.ts src/instrumentation.ts src/instrumentation-client.ts src/app/main.py src/app/cli.py src/testing/setup.ts'.split(
    ' ',
  ),
);
/* A test of an entrypoint mirrors it at the root of the test tree. */
const isEntrypointTest = (path) =>
  path.startsWith('src/testing/') &&
  ENTRYPOINTS.has(path.replace('src/testing/', 'src/').replace(/\.test\.(ts|tsx)$/, '.ts'));
const IGNORED_FILES = new Set(['.DS_Store', '__init__.py', 'conftest.py', 'py.typed']);

const SUPPORT_DIRS = new Set(['helpers', 'mocks', 'fixtures', 'stubs']);
const BANNED_NAMES = new Set(
  'misc miscellaneous extra extras other others stuff temp tmp final-branches coverage-gaps'.split(
    ' ',
  ),
);

const SOURCE_EXT = /\.(ts|tsx|mts|js|mjs|jsx)$/;
const TEST_FILE = /\.test\.(ts|tsx|mts)$|^test_.+\.py$/;

const errors = [];

/** Lib: report
 * Records one violation under the rule it breaks.
 */
function report(path, message, rule) {
  errors.push(`${path}\n    ${message} (SHAPE-${rule})`);
}

/** Lib: isSkipped
 * True for a directory whose shape the rules do not govern.
 */
function isSkipped(path) {
  if (ROUTE_TREES.some((tree) => path === tree || path.startsWith(`${tree}/`))) return true;
  return path.split('/').some((segment) => SKIPPED_DIRS.has(segment) || segment.startsWith('.'));
}

/** Lib: listDir
 * Splits a directory into its files and the subdirectories the rules count.
 */
function listDir(dir) {
  const files = [];
  const dirs = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      if (!isSkipped(full)) dirs.push(entry);
    } else if (!IGNORED_FILES.has(entry)) files.push(entry);
  }
  return { files, dirs };
}

/** Lib: walk
 * Visits every governed directory under a root, depth first.
 */
function walk(dir, visit) {
  if (isSkipped(dir)) return;
  const { files, dirs } = listDir(dir);
  visit(dir, files, dirs);
  for (const sub of dirs) walk(join(dir, sub), visit);
}

/** Lib: stemOf
 * The name a test and its source share: everything before the first dot.
 */
function stemOf(file) {
  return file.replace(/^test_/, '').split('.')[0];
}

const sourceCache = new Map();
/** Lib: collectSources
 * Maps each source stem under a root to the directories holding a file with that stem. Memoised.
 */
function collectSources(root, recursive) {
  const key = `${root}|${recursive}`;
  if (sourceCache.has(key)) return sourceCache.get(key);
  const byStem = new Map();
  sourceCache.set(key, byStem);
  const visit = (dir, files) => {
    for (const file of files) {
      const isSource = IS_PYTHON ? file.endsWith('.py') : SOURCE_EXT.test(file);
      if (!isSource || TEST_FILE.test(file)) continue;
      const stem = stemOf(file);
      byStem.set(stem, [...(byStem.get(stem) ?? []), dir]);
    }
  };
  if (!existsSync(root)) return byStem;
  if (recursive) walk(root, visit);
  else visit(root, listDir(root).files);
  return byStem;
}

/* SHAPE-1 and SHAPE-3 */
for (const root of ROOTS) {
  walk(root, (dir, files, dirs) => {
    const counted = dirs.filter((d) => d !== '__tests__');
    for (const d of counted) {
      if (BANNED_NAMES.has(d)) {
        report(`${dir}/${d}/`, `"${d}" names why it was written. Name it for its subject.`, 3);
      }
    }
    if (counted.length === 0) return;
    const loose = files.filter(
      (f) =>
        !ENTRYPOINTS.has(`${dir}/${f}`) &&
        !isEntrypointTest(`${dir}/${f}`) &&
        !f.includes('.generated.'),
    );
    if (loose.length === 0) return;
    report(
      `${dir}/`,
      `Holds ${counted.length} folder(s) and ${loose.length} loose file(s): ${loose.slice(0, 5).join(', ')}${loose.length > 5 ? ', …' : ''}\n    Move each file into a folder named for its domain.`,
      1,
    );
  });
}

/* SHAPE-2, per test layout */
/** Lib: checkMirror
 * Flags a test whose name matches a source file that lives somewhere other than its mirror.
 * `toTestDir` maps a source directory to the directory its tests belong in.
 */
function checkMirror(testPath, mirrorDir, root, recursive, toTestDir) {
  const stem = stemOf(basename(testPath));
  if (BANNED_NAMES.has(stem)) {
    report(testPath, `"${stem}" names why it was written. Name it for its subject.`, 3);
    return;
  }
  const homes = collectSources(root, recursive).get(stem);
  if (!homes || homes.includes(mirrorDir)) return;
  const targets = [...new Set(homes.map(toTestDir))].map((dir) => `${dir}/`);
  report(
    testPath,
    `Named after ${stem} in ${homes.join(', ')}: move it to ${targets.join(' or ')}.`,
    2,
  );
}

if (existsSync('src/testing')) {
  walk('src/testing', (dir, files) => {
    const rel = dir === 'src/testing' ? '' : dir.slice('src/testing/'.length);
    const layer = rel.split('/')[0];
    for (const file of files) {
      const path = `${dir}/${file}`;
      if (ENTRYPOINTS.has(path)) continue;
      if (!TEST_FILE.test(file)) {
        if (!SUPPORT_DIRS.has(layer)) {
          report(
            path,
            'A support file beside tests: move it to src/testing/<helpers|mocks|…>/.',
            4,
          );
        }
        continue;
      }
      if (SUPPORT_DIRS.has(layer)) {
        report(path, 'A test inside a support folder. Move it to the mirror of its source.', 2);
        continue;
      }
      if (rel === '') {
        checkMirror(path, 'src', 'src', false, () => 'src/testing');
        continue;
      }
      const mirrorDir = layer === 'scripts' ? rel : `src/${rel}`;
      if (!existsSync(mirrorDir)) {
        report(path, `No ${mirrorDir}/ to mirror: a test lives at its source's path.`, 2);
        continue;
      }
      const root = layer === 'scripts' ? 'scripts' : `src/${layer}`;
      const toTestDir = (home) =>
        layer === 'scripts' ? `src/testing/${home}` : home.replace(/^src/, 'src/testing');
      checkMirror(path, mirrorDir, root, true, toTestDir);
    }
  });
}

if (!IS_PYTHON && existsSync('src')) {
  walk('src', (dir, files) => {
    if (basename(dir) !== '__tests__') return;
    for (const file of files) {
      if (TEST_FILE.test(file))
        checkMirror(`${dir}/${file}`, dirname(dir), 'src', true, (home) => `${home}/__tests__`);
    }
  });
}

if (IS_PYTHON && existsSync('tests')) {
  walk('tests', (dir, files) => {
    const segments = dir.split('/').slice(1);
    const kind = segments[0];
    for (const file of files) {
      const path = `${dir}/${file}`;
      if (!file.endsWith('.py')) continue;
      if (!TEST_FILE.test(file)) {
        if (kind !== 'fixtures')
          report(path, 'A support file beside tests. Move it to tests/fixtures/.', 4);
        continue;
      }
      if (!kind || kind === 'fixtures') {
        report(path, 'A test outside tests/<unit|routes|integration>/.', 2);
        continue;
      }
      const toTestDir = (home) => home.replace(/^src\/app/, `tests/${kind}`);
      checkMirror(path, ['src/app', ...segments.slice(1)].join('/'), 'src/app', true, toTestDir);
    }
  });
}

console.log(`[check-folder-shape] Scanning ${ROOTS.join(', ')}...`);

if (errors.length > 0) {
  const log = WARN ? console.warn : console.error;
  log(`\n[check-folder-shape] ${WARN ? '⚠' : '✗'} ${errors.length} violation(s):\n`);
  for (const error of errors) log(`  ${error}\n`);
  log(`[check-folder-shape] See ${RULES} for the standard.`);
  process.exit(WARN ? 0 : 1);
}

console.log('[check-folder-shape] ✓ Every folder holds files or folders, and every test mirrors.');
process.exit(0);
