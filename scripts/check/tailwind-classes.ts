#!/usr/bin/env bun
/**
 * Refuses a Tailwind class that is not in its canonical form (AGENTS.md Rule 33).
 *
 * The editor already says this: `mt-[15px] can be written as mt-3.75 (suggestCanonicalClasses)`.
 * A warning nothing in the repo repeats accumulates while every gate passes. This closes that gap,
 * and it does not reimplement the rule: it calls Tailwind's own `canonicalizeCandidates`, the same
 * function behind the editor diagnostic, against a design system loaded from THIS repo's
 * stylesheet. So the answer tracks the theme, and an upgrade cannot leave the checker asserting
 * last year's scale. `__unstable__loadDesignSystem` is Tailwind v4's own loader; its name says it
 * may change, so re-run this after a Tailwind upgrade.
 *
 * Five checks, any of which fails the gate. The first mirrors the editor's `suggestCanonicalClasses`;
 * the last two mirror `cssConflict` and the invalid-class family, so "no warnings" means all of them
 * rather than the one that happened to be noticed:
 *
 *   1. Every class candidate is already canonical.
 *   2. No arbitrary value contains a `${…}` interpolation — Tailwind never generates those, so
 *      `w-[${size}px]` is a class that silently does nothing, not merely an unidiomatic one.
 *   3. `--spacing` is still undefined, because the whole fractional family (`mt-3.75`) is computed
 *      from it and redefining it would change every one of them without touching a line of TSX.
 *   4. Every candidate compiles to CSS. A class Tailwind cannot resolve is dead text: no error, no
 *      style, nothing in the DOM to strike through.
 *   5. No class list sets the same CSS property twice. `flex block` is not a style choice, it is one
 *      of the two losing silently on source order.
 *
 * `--fix` rewrites check 1; the rest name a defect a human has to decide about.
 */

import { readdirSync, readFileSync, statSync, writeFileSync } from 'fs';
import { dirname, join, relative, resolve } from 'path';
import { fileURLToPath } from 'url';
import { __unstable__loadDesignSystem } from 'tailwindcss';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const SRC_DIR = join(ROOT, 'src');
const NODE_MODULES = join(ROOT, 'node_modules');
const FIX = process.argv.includes('--fix');
const ALLOW_FILE = 'scripts/check/tailwind-classes.allow.json';

/* The stylesheet the app actually builds from. Loading Tailwind's default theme instead would make
   the checker right about a project that does not exist here. */
const ENTRY_CSS = join(SRC_DIR, 'styles/globals.css');

/* Matches the editor extension's default `tailwindCSS.rootFontSize`, so a px value converts to the
   same scale step the editor names. Without it Tailwind cannot turn `15px` into `3.75` at all. */
const ROOT_FONT_SIZE = 16;

/* Where a class string is scanned. `className`/`class` is what the editor reads by default; the
   four helpers are the class functions to register in the editor's `tailwindCSS.classFunctions`
   setting too, or a class inside `cn(...)` is linted by nobody. */
const CLASS_FUNCTIONS = ['cn', 'cva', 'clsx', 'twMerge'];

/**
 * Paths the scan does not touch.
 *
 * `src/lib/api/generated/` is overwritten by the next `generate:api`.
 *
 * `src/testing/` names class strings as data — sometimes deliberately non-canonical data, such as a
 * test of what tailwind-merge does with `cn('px-0', 'px-[18px]')` — and nothing there renders.
 * Canonicalising the argument without the expectation beside it would break a passing test.
 */
const SKIP = ['src/lib/api/generated/', 'src/testing/'];

type Finding = { rel: string; line: number; from: string; to: string; kind: string };
const findings: Finding[] = [];

/* ── Design system, loaded the way the build loads it ───────────────────────── */
/* Async because that is the signature Tailwind declares, even though every read here is
   synchronous. */
async function loadStylesheet(id: string, base: string) {
  const path = id.startsWith('.') ? resolve(base, id) : resolvePackageCss(id);
  return { path, base: dirname(path), content: readFileSync(path, 'utf8') };
}

function resolvePackageCss(id: string): string {
  const direct = join(NODE_MODULES, id);
  if (safeIsFile(direct)) return direct;
  const index = join(NODE_MODULES, id, 'index.css');
  if (safeIsFile(index)) return index;
  throw new Error(`cannot resolve stylesheet '${id}'`);
}

function safeIsFile(path: string): boolean {
  try {
    return statSync(path).isFile();
  } catch {
    return false;
  }
}

/* `@plugin` and `@config` are not loaded. Throwing names the day a stylesheet uses one, instead of
   silently building a design system that is missing whatever the plugin contributed. */
async function loadModule(id: string): Promise<never> {
  throw new Error(`@plugin/@config is not supported by this checker: '${id}'`);
}

/* A repo that carries the Tailwind dependency but no entry stylesheet yet has no design system to
   ask. Reported as SKIPPED rather than passed: a check that cannot run must not read as a check
   that passed. */
if (!safeIsFile(ENTRY_CSS)) {
  console.warn(`Tailwind classes: ${relative(ROOT, ENTRY_CSS)} not found — check SKIPPED`);
  process.exit(0);
}

const designSystem = await __unstable__loadDesignSystem(readFileSync(ENTRY_CSS, 'utf8'), {
  base: dirname(ENTRY_CSS),
  loadStylesheet,
  loadModule,
});

/**
 * Candidates that compile to nothing on purpose.
 *
 * `group` and `peer` are Tailwind's own markers: they emit no CSS and exist so that `group-hover:`
 * and `peer-checked:` have something to target. Anything else a repo needs to accept lives in
 * `scripts/check/tailwind-classes.allow.json` (`[{ "candidate": "…", "reason": "…" }]`), so every
 * exemption shows up in a diff with its reason.
 */
const TAILWIND_MARKERS = ['group', 'peer'];

type Exemption = { candidate: string; reason: string };

function isExemption(entry: unknown): entry is Exemption {
  if (typeof entry !== 'object' || entry === null) return false;
  const { candidate, reason } = entry as Record<string, unknown>;
  return typeof candidate === 'string' && (reason === undefined || typeof reason === 'string');
}

function loadExemptions(): Exemption[] {
  const path = join(ROOT, ALLOW_FILE);
  if (!safeIsFile(path)) return [];
  const parsed: unknown = JSON.parse(readFileSync(path, 'utf8'));
  if (!Array.isArray(parsed) || !parsed.every(isExemption)) {
    throw new Error(`${ALLOW_FILE} must be an array of { candidate, reason }`);
  }
  return parsed;
}

const canonicalCache = new Map<string, string>();

function canonical(candidate: string): string {
  const cached = canonicalCache.get(candidate);
  if (cached !== undefined) return cached;
  /* `collapse` stays off: merging `mt-2 mr-2 mb-2 ml-2` into `m-2` changes what a later variant can
     override, and it makes a class impossible to grep for. */
  const [result] = designSystem.canonicalizeCandidates([candidate], { rem: ROOT_FONT_SIZE });
  const value = result ?? candidate;
  canonicalCache.set(candidate, value);
  return value;
}

/**
 * Class names this repo declares in its own stylesheets.
 *
 * Tailwind cannot compile a hand-written class such as `app-sidebar-header`, and should not.
 * Reading the selectors off the stylesheets rather than allowing a prefix is what keeps a typo
 * inside an owned prefix detectable.
 */
function declaredCssClasses(): Set<string> {
  const names = new Set<string>();
  for (const file of collectFiles(SRC_DIR)) {
    const source = readFileSync(file, 'utf8');
    if (file.endsWith('.css')) {
      for (const match of source.matchAll(/\.(-?[_a-z][\w-]*)/gi)) names.add(match[1] ?? '');
      /* `@utility name` defines a first-party utility that Tailwind resolves only when a source
         file uses it, which is not the case while this checker asks about it in isolation. */
      for (const match of source.matchAll(/@utility\s+([\w-]+)/g)) names.add(match[1] ?? '');
      continue;
    }
    /* A class can also be declared in a `<style>` string built in TypeScript (a keyframe set that
       ships with its component). A selector is a `.name` in selector position on a line that opens
       a rule, which is what separates `.card-pulse {` from `header.column.id`. */
    for (const match of source.matchAll(/(?:^|[\s,>+~])\.(-?[_a-z][\w-]*)(?=[^\n]*\{)/gm)) {
      names.add(match[1] ?? '');
    }
  }
  return names;
}

const cssCache = new Map<string, string | null>();

function compiledCss(candidate: string): string | null {
  if (!cssCache.has(candidate)) {
    const [css] = designSystem.candidatesToCss([candidate]);
    cssCache.set(candidate, css ?? null);
  }
  return cssCache.get(candidate) ?? null;
}

/** The CSS properties a candidate sets, ignoring Tailwind's internal `--tw-*` plumbing. */
function propertiesOf(candidate: string): string[] {
  const css = compiledCss(candidate);
  if (css === null) return [];
  const bodies = [...css.matchAll(/\{([^{}]*)\}/g)].map((match) => match[1] ?? '').join(';');
  const properties = new Set<string>();
  for (const match of bodies.matchAll(/([-a-z]+)\s*:/gi)) {
    const property = (match[1] ?? '').toLowerCase();
    if (!property.startsWith('--tw-') && property !== 'syntax' && property !== 'inherits') {
      properties.add(property);
    }
  }
  return [...properties];
}

/** True when the utility contributes to a composed value, where a second class adds rather than wins. */
function composesThroughVariable(candidate: string): boolean {
  return (compiledCss(candidate) ?? '').includes('var(--tw-');
}

/**
 * Everything before a candidate's final utility, so conflicts are only compared like with like.
 *
 * `flex md:block` is a responsive override and correct; `flex block` is two utilities fighting over
 * `display` with source order deciding. Splitting on `:` outside brackets is what tells them apart.
 */
function variantKey(candidate: string): string {
  let depth = 0;
  let cut = -1;
  for (let i = 0; i < candidate.length; i++) {
    const char = candidate[i];
    if (char === '[' || char === '(') depth++;
    else if (char === ']' || char === ')') depth--;
    else if (char === ':' && depth === 0) cut = i;
  }
  return cut === -1 ? '' : candidate.slice(0, cut + 1);
}

/* ── Source scanning ───────────────────────────────────────────────────────────── */
function collectFiles(dir: string, out: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      if (entry !== 'node_modules') collectFiles(full, out);
    } else if (/\.(tsx?|css)$/.test(full)) out.push(full);
  }
  return out;
}

/**
 * Blanks comments while preserving every offset and line break.
 *
 * Offsets have to survive: the scan runs on the blanked copy and the rewrite is applied to the
 * original at the same positions. Replacing with spaces rather than deleting is what makes that
 * safe.
 */
const blank = (match: string): string => match.replace(/[^\n]/g, ' ');

/* Strings and comments are matched as tokens in ONE ordered alternation, so a comment opener
   inside a string is consumed as part of the string and never read as a comment. Blanking comments
   first is wrong: a string holding a slash-star, plus any later comment terminator, makes the scan
   skip everything between them — and this very comment cannot spell the terminator, for the same
   reason. */
const CODE_TOKEN =
  /(['"])(?:\\.|(?!\1)[^\\\n])*\1|`(?:\\.|[^\\`])*`|\/\*[\s\S]*?\*\/|(?<=^|\s)\/\/[^\n]*/g;

function withoutComments(source: string): string {
  return source.replace(CODE_TOKEN, (match) =>
    match.startsWith('/*') || match.startsWith('//') ? blank(match) : match,
  );
}

/** Finds the index just past the region opened at `open`, honouring nesting and string literals. */
function matchDelimiter(source: string, open: number, closeChar: string, openChar: string): number {
  let depth = 0;
  for (let i = open; i < source.length; i++) {
    const char = source[i];
    if (char === '\\') {
      i++;
      continue;
    }
    if (char === '"' || char === "'" || char === '`') {
      i = skipString(source, i);
      continue;
    }
    if (char === openChar) depth++;
    else if (char === closeChar) {
      depth--;
      if (depth === 0) return i;
    }
  }
  return source.length;
}

/** Given the index of a quote, returns the index of its closing quote. */
function skipString(source: string, start: number): number {
  const quote = source[start];
  for (let i = start + 1; i < source.length; i++) {
    if (source[i] === '\\') {
      i++;
      continue;
    }
    if (source[i] === quote) return i;
  }
  return source.length;
}

/** Every string-literal body inside `[from, to)`, as absolute offsets. */
function stringLiteralsIn(source: string, from: number, to: number): [number, number][] {
  const spans: [number, number][] = [];
  for (let i = from; i < to; i++) {
    const char = source[i];
    if (char === '"' || char === "'" || char === '`') {
      const end = skipString(source, i);
      spans.push([i + 1, Math.min(end, to)]);
      i = end;
    }
  }
  return spans;
}

/**
 * Spans whose string literals are not class lists, even though they sit inside a scanned call.
 *
 * `variant === 'panel' ? 'rounded-…' : '…'` puts an operand and two class lists in one `cn()`, and
 * `defaultVariants: { variant: 'primary' }` puts a variant name there. Reported as classes they
 * read as typos.
 */
function nonClassSpans(source: string): [number, number][] {
  const spans: [number, number][] = [];
  for (const match of source.matchAll(/(?:===|!==|==|!=)\s*(['"`])/g)) {
    const quote = match.index + match[0].length - 1;
    spans.push([quote, skipString(source, quote) + 1]);
  }
  for (const match of source.matchAll(/\bdefaultVariants\s*:\s*\{/g)) {
    const open = match.index + match[0].length - 1;
    spans.push([open, matchDelimiter(source, open, '}', '{') + 1]);
  }
  return spans;
}

/** The spans of a file that hold class names. */
function classRegions(source: string): [number, number][] {
  const regions: [number, number][] = [];

  for (const match of source.matchAll(/\b(?:className|class)\s*=\s*/g)) {
    const at = match.index + match[0].length;
    const char = source[at];
    if (char === '{') {
      const close = matchDelimiter(source, at, '}', '{');
      regions.push(...stringLiteralsIn(source, at + 1, close));
    } else if (char === '"' || char === "'" || char === '`') {
      regions.push([at + 1, skipString(source, at)]);
    }
  }

  const callPattern = new RegExp(`\\b(?:${CLASS_FUNCTIONS.join('|')})\\s*\\(`, 'g');
  for (const match of source.matchAll(callPattern)) {
    const open = match.index + match[0].length - 1;
    const close = matchDelimiter(source, open, ')', '(');
    regions.push(...stringLiteralsIn(source, open + 1, close));
  }

  /* `@apply` in a stylesheet carries the same candidates and the editor lints it the same way. */
  for (const match of source.matchAll(/@apply\s+([^;]+);/g)) {
    const applied = match[1] ?? '';
    const at = match.index + match[0].indexOf(applied);
    regions.push([at, at + applied.length]);
  }

  /* `className={cn('a', 'b')}` is found twice — once as the attribute's braces, once as the call —
     and would report each class twice. Deduping spans is enough because both passes yield the
     identical string-literal offsets. */
  const excluded = nonClassSpans(source);
  const seen = new Set<string>();
  return regions.filter(([from, to]) => {
    const key = `${from}:${to}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return !excluded.some(([start, end]) => from >= start && to <= end);
  });
}

/**
 * Whitespace-separated candidates in `[from, to)`, as absolute offsets.
 *
 * A `${…}` group counts as part of its token even when it contains spaces, so an interpolated class
 * is reported whole. Splitting naively cuts `w-[${on ? 4 : 8}px]` at the first space and reports
 * `w-[${on`, which names no class anyone can search for.
 */
function candidatesIn(source: string, from: number, to: number): [number, number, string][] {
  const out: [number, number, string][] = [];
  let i = from;
  while (i < to) {
    while (i < to && /\s/.test(source[i] ?? '')) i++;
    const start = i;
    while (i < to && !/\s/.test(source[i] ?? '')) {
      if (source[i] === '$' && source[i + 1] === '{') i = matchDelimiter(source, i + 1, '}', '{');
      i++;
    }
    if (i > start) out.push([start, Math.min(i, to), source.slice(start, Math.min(i, to))]);
  }
  return out;
}

const lineOf = (source: string, index: number): number => source.slice(0, index).split('\n').length;

const CSS_CLASSES = declaredCssClasses();
const EXEMPTIONS = loadExemptions();
const EXEMPT = new Set(EXEMPTIONS.map((entry) => entry.candidate));

/* ── Check 3: the scale the fractional classes are computed from ───────────── */
function assertSpacingUntouched(): void {
  const sheets = [
    ENTRY_CSS,
    ...collectFiles(join(SRC_DIR, 'styles')).filter((f) => f.endsWith('.css')),
  ];
  for (const sheet of new Set(sheets)) {
    const source = readFileSync(sheet, 'utf8');
    if (/--spacing\s*:/.test(source)) {
      findings.push({
        rel: relative(ROOT, sheet),
        line: lineOf(source, source.search(/--spacing\s*:/)),
        from: '--spacing',
        to: 'must stay at its default',
        kind: 'spacing scale redefined',
      });
    }
  }
}

/* ── Run ───────────────────────────────────────────────────────────────────────── */
assertSpacingUntouched();

let filesFixed = 0;
let filesScanned = 0;

for (const file of collectFiles(SRC_DIR)) {
  const rel = relative(ROOT, file);
  if (SKIP.some((skip) => rel.startsWith(skip))) continue;
  filesScanned++;

  const original = readFileSync(file, 'utf8');
  const scan = withoutComments(original);
  const edits: [number, number, string][] = [];

  for (const [from, to] of classRegions(scan)) {
    /* Property owners within THIS string literal only. A class list split across literals is
       usually `cn('flex', open && 'block')`, where exactly one of the two ever applies. */
    const owners = new Map<string, string>();

    for (const [start, end, candidate] of candidatesIn(scan, from, to)) {
      if (candidate.includes('${')) {
        /* Only an arbitrary value is broken by interpolation. `${base}-active` composes a class
           name, which is a different (and legitimate) thing. */
        if (candidate.includes('[')) {
          findings.push({
            rel,
            line: lineOf(scan, start),
            from: candidate,
            to: 'never generated by Tailwind — use a style prop or a cva variant',
            kind: 'interpolated arbitrary value',
          });
        }
        continue;
      }

      const wanted = canonical(candidate);
      if (wanted !== candidate) {
        if (FIX) edits.push([start, end, wanted]);
        else
          findings.push({
            rel,
            line: lineOf(scan, start),
            from: candidate,
            to: wanted,
            kind: 'non-canonical class',
          });
      }

      /* Checks 4 and 5 judge the canonical form, so a class is never reported twice for the same
         defect once `--fix` has run. */
      if (TAILWIND_MARKERS.includes(wanted) || CSS_CLASSES.has(wanted)) continue;
      if (EXEMPT.has(wanted)) continue;

      if (compiledCss(wanted) === null) {
        findings.push({
          rel,
          line: lineOf(scan, start),
          from: wanted,
          to: 'compiles to nothing — a typo, or a token this repo does not define',
          kind: 'class generates no CSS',
        });
        continue;
      }

      /* Only an unambiguous clash counts: the two candidates set exactly the same properties and
         neither composes through a `--tw-*` variable. Comparing property by property instead
         reports `transition-colors duration-200` and `text-sm leading-relaxed`, which are the
         documented way to override a utility's default, not defects. */
      const signature = `${variantKey(wanted)}${[...propertiesOf(wanted)].sort().join(',')}`;
      if (propertiesOf(wanted).length > 0 && !composesThroughVariable(wanted)) {
        const previous = owners.get(signature);
        if (previous !== undefined && previous !== wanted) {
          findings.push({
            rel,
            line: lineOf(scan, start),
            from: `${previous} + ${wanted}`,
            to: 'both set the same properties — source order decides, not intent',
            kind: 'conflicting classes',
          });
        }
        owners.set(signature, wanted);
      }
    }
  }

  if (FIX && edits.length > 0) {
    let next = original;
    for (const [start, end, replacement] of [...edits].sort((a, b) => b[0] - a[0])) {
      next = next.slice(0, start) + replacement + next.slice(end);
    }
    writeFileSync(file, next);
    filesFixed++;
    console.log(`  fixed ${edits.length.toString().padStart(3)} in ${rel}`);
  }
}

/* An exemption with no reason is an unreviewed one. */
for (const entry of EXEMPTIONS) {
  if (!entry.reason) {
    findings.push({
      rel: ALLOW_FILE,
      line: 0,
      from: entry.candidate,
      to: 'needs a reason',
      kind: 'unjustified exemption',
    });
  }
}

if (FIX) {
  console.log(`\nTailwind classes: rewrote ${filesFixed} file(s). Re-run without --fix to verify.`);
  process.exit(0);
}

if (findings.length > 0) {
  console.error(`\nTailwind classes: ${findings.length} problem(s)\n`);
  for (const finding of findings) {
    console.error(`  ✗ ${finding.rel}:${finding.line} — ${finding.kind}`);
    console.error(`      ${finding.from}  →  ${finding.to}`);
  }
  console.error('\nRun `bun run check:tailwind --fix` for the rewritable ones.\n');
  process.exit(1);
}

console.log(
  `Tailwind classes: ${filesScanned} file(s), all candidates canonical, no interpolated arbitrary values`,
);
