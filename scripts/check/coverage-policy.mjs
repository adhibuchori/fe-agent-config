#!/usr/bin/env node
/**
 * COVER: refuses a coverage gate that was weakened.
 *
 * The suite itself proves coverage; this proves the suite is still asked the right question. It
 * reads the coverage config of whichever stack the repo has (vitest.config.ts, bunfig.toml, or
 * pyproject.toml's [tool.coverage]), and fails when a threshold drops below 100, a logic folder
 * falls out of scope, an exemption carries no reason, or the pre-commit hook stops running the
 * coverage suite. A repo with no test runner configured has nothing to check and passes.
 * The rule is the language's `coverage.md`: `.claude/rules/typescript/` or `.claude/rules/python/`.
 *
 * usage: node scripts/check/coverage-policy.mjs
 */
import { existsSync, readFileSync } from 'node:fs';

const RULES = ['.claude/rules/typescript/coverage.md', '.claude/rules/python/coverage.md'];
const problems = [];
const read = (path) => (existsSync(path) ? readFileSync(path, 'utf8') : null);

/** The bracketed list after `key` (`[` … matching `]`), or null. */
function listAfter(text, key) {
  const start = text.search(key);
  if (start < 0) return null;
  const open = text.indexOf('[', start);
  let depth = 0;
  for (let i = open; i < text.length; i++) {
    if (text[i] === '[') depth++;
    if (text[i] === ']' && --depth === 0)
      return { body: text.slice(open + 1, i), before: text.slice(0, start) };
  }
  return null;
}

/** Entries with no reason. A comment explains the run of entries right below it, up to the next
 *  blank line; `headerExplains` covers the first run when the comment sits above the key. */
function unexplained(list, isComment, entriesOf, generic, headerExplains) {
  const missing = [];
  let explained = headerExplains;
  for (const line of list.split('\n')) {
    const trimmed = line.trim();
    if (trimmed === '') explained = false;
    else if (isComment(trimmed)) explained = true;
    for (const entry of entriesOf(trimmed)) {
      if (!explained && !generic(entry)) missing.push(entry);
    }
  }
  return missing;
}

const quoted = (line) => [...line.matchAll(/['"]([^'"]+)['"]/g)].map((m) => m[1]);

/** Why pre-commit would skip the coverage suite. With scripts/check/gates.list the suite is a line
 *  of that list, and the list runs only while .husky/pre-commit hands it to gates.sh --hook, so both
 *  are checked; without one, the hook must run the suite itself. A commented line runs nothing. */
const GATES_LIST = 'scripts/check/gates.list';
const HOOK = '.husky/pre-commit';
const active = (path) => (read(path) ?? '').split('\n').filter((l) => !l.trim().startsWith('#'));
function preCommitCoverageProblems() {
  const runsSuite = (path) => active(path).some((l) => l.includes('test:coverage'));
  if (!existsSync(GATES_LIST))
    return runsSuite(HOOK) ? [] : [`${HOOK} must run the \`test:coverage\` script`];
  const out = [];
  if (!active(HOOK).some((l) => /scripts\/check\/gates\.sh\b.*--hook/.test(l)))
    out.push(`${HOOK} must run \`bash scripts/check/gates.sh --hook\`, which runs ${GATES_LIST}`);
  if (!runsSuite(GATES_LIST)) out.push(`${GATES_LIST} must run the \`test:coverage\` script`);
  return out;
}
const GENERIC = (entry) => /(^\*\*\/index\.ts$|\.gitkeep$|generated)/.test(entry);

function checkVitest(config) {
  const block = config.match(/thresholds\s*:\s*\{([^}]*)\}/);
  for (const metric of ['statements', 'branches', 'functions', 'lines']) {
    const value = block?.[1].match(new RegExp(`${metric}\\s*:\\s*(\\d+)`))?.[1];
    if (value !== '100')
      problems.push(
        `vitest.config: coverage.thresholds.${metric} is ${value ?? 'missing'}, must be 100`,
      );
  }
  // Read include and exclude inside the `coverage: {` block, so the test-file globs of
  // `test.include` are never mistaken for the coverage scope.
  const at = config.search(/\bcoverage\s*:\s*\{/);
  const coverage = at < 0 ? '' : config.slice(at);
  const include = listAfter(coverage, /\binclude\s*:\s*\[/);
  const scope = include ? quoted(include.body) : [];
  for (const dir of ['hooks', 'lib', 'store', 'i18n']) {
    if (existsSync(`src/${dir}`) && !scope.includes(`src/${dir}/**`)) {
      problems.push(`vitest.config: coverage.include must list 'src/${dir}/**'`);
    }
  }
  if (existsSync('src/proxy.ts') && !scope.includes('src/proxy.ts')) {
    problems.push("vitest.config: coverage.include must list 'src/proxy.ts'");
  }
  const exclude = listAfter(coverage, /\bexclude\s*:\s*\[/);
  if (exclude) {
    const bare = unexplained(
      exclude.body,
      (l) => /^(\/\*|\*|\/\/)/.test(l),
      quoted,
      GENERIC,
      false,
    );
    for (const entry of bare)
      problems.push(`vitest.config: exclusion '${entry}' has no reason comment above it`);
  }
  problems.push(...preCommitCoverageProblems());
}

function checkBun(bunfig) {
  const threshold = bunfig.match(/^coverageThreshold\s*=\s*([\d.]+)/m)?.[1];
  if (Number(threshold) !== 1)
    problems.push(`bunfig.toml: coverageThreshold is ${threshold ?? 'missing'}, must be 1.0`);
  if (!/coverageReporter\s*=\s*\[[^\]]*"lcov"/.test(bunfig))
    problems.push('bunfig.toml: coverageReporter must include "lcov"');
  const list = listAfter(bunfig, /coveragePathIgnorePatterns\s*=/);
  if (list) {
    const header = list.before.trimEnd().split('\n').at(-1)?.trim().startsWith('#') ?? false;
    const bare = unexplained(
      list.body,
      (l) => l.startsWith('#'),
      (l) => (l.startsWith('#') ? [] : quoted(l)),
      GENERIC,
      header,
    );
    for (const entry of bare)
      problems.push(`bunfig.toml: ignore entry '${entry}' has no reason comment above it`);
  }
  const script = JSON.parse(read('package.json') ?? '{}').scripts?.['test:coverage'] ?? '';
  if (!script.includes('coverage-files.mjs'))
    problems.push('package.json: test:coverage must run scripts/check/coverage-files.mjs');
  problems.push(...preCommitCoverageProblems());
}

/** The body of one TOML table: the lines after `[name]` up to the next table header. A `[` inside
 *  a value (`source = ["src"]`) does not end the table. */
function tomlTable(text, name) {
  const lines = text.split('\n');
  const start = lines.findIndex((l) => l.trim() === `[${name}]`);
  if (start < 0) return '';
  const end = lines.findIndex((l, i) => i > start && /^\s*\[/.test(l));
  return lines.slice(start + 1, end < 0 ? undefined : end).join('\n');
}

function checkPython(pyproject) {
  const run = tomlTable(pyproject, 'tool.coverage.run');
  const report = tomlTable(pyproject, 'tool.coverage.report');
  if (!/^\s*branch\s*=\s*true/m.test(run))
    problems.push('pyproject.toml: [tool.coverage.run] must set branch = true');
  const floor = report.match(/^\s*fail_under\s*=\s*([\d.]+)/m)?.[1];
  if (Number(floor) !== 100)
    problems.push(`pyproject.toml: fail_under is ${floor ?? 'missing'}, must be 100`);
  // Only a live line counts: a comment that mentions pytest and --cov runs nothing. The suite runs
  // from .pre-commit-config.yaml directly, or from gates.list when pre-commit (or husky) hands the
  // commit to gates.sh --hook.
  const runsPytest = (path) => active(path).some((l) => /pytest.*--cov/.test(l));
  const hooks = active('.pre-commit-config.yaml');
  const viaGates = [...hooks, ...active(HOOK)].some((l) => /scripts\/check\/gates\.sh\b.*--hook/.test(l));
  if (!runsPytest('.pre-commit-config.yaml') && !(viaGates && runsPytest(GATES_LIST)))
    problems.push(
      `.pre-commit-config.yaml must run pytest with --cov (directly, or through gates.sh --hook and a ${GATES_LIST} line)`,
    );
}

const vitest = read('vitest.config.ts') ?? read('vitest.config.mts');
const bunfig = read('bunfig.toml');
const pyproject = read('pyproject.toml');
if (vitest) checkVitest(vitest);
if (bunfig?.includes('coverageThreshold') || bunfig?.includes('[test]')) checkBun(bunfig);
if (pyproject?.includes('[tool.coverage')) checkPython(pyproject);
if (!vitest && !bunfig && !pyproject?.includes('[tool.coverage')) {
  console.log('coverage-policy: no test runner configured here, nothing to check.');
  process.exit(0);
}

if (problems.length > 0) {
  // The rule file the repo ships, else the one its runner's language implies.
  const rule = RULES.find((path) => existsSync(path)) ?? RULES[vitest || bunfig ? 0 : 1];
  console.error(`coverage-policy (COVER): ${problems.length} problem(s) — see ${rule}`);
  for (const p of problems) console.error(`  ${p}`);
  process.exit(1);
}
console.log('coverage-policy: thresholds at 100, scope complete, every exemption explained.');
