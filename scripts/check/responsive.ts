#!/usr/bin/env bun
/**
 * RESP — responsive layout. Optional module: delete it with its rule.
 * See .claude/rules/web/responsive.md for the rules and the reasoning behind them.
 *
 * Checks for:
 * 1. R1 — media queries read breakpoints by name, never as a pixel literal
 * 2. R2 — the --breakpoint-* tokens exist in @theme
 * 3. R3 — no class inside a width media query without a consumer in JSX
 * 4. R4 — no project-prefixed class in JSX without a rule behind it
 * 5. R5 — an inline dimension >= 200px carries a fluid guard
 * 6. R6 — a grid track >= 280px is wrapped in min()
 * 7. R7 — every shell and screen root is responsive by some mechanism
 *
 * Exit code 1 on any violation. There are no warning-only rules here: breakpoint systems drift
 * into each other precisely because nothing fails while they do, and a media query with no
 * consumer describes a layout that has never rendered.
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { ENTRY_STYLESHEET, loadStylesheets } from '../lib/stylesheets';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const SRC = join(ROOT, 'src');
const STYLES_DIR = join(SRC, 'styles');

/**
 * Class prefixes this repo owns: its hand-written CSS classes, as opposed to Tailwind utilities.
 * R3 and R4 read only these. List every prefix your stylesheets use.
 */
const OWNED = ['app-'];

/** R5 floor: below this a number describes content (an avatar, an icon), not layout. */
const DIMENSION_FLOOR = 200;
/** R6 floor: a track narrower than this still fits the narrowest viewport supported. */
const TRACK_FLOOR = 280;

/** Values that make a fixed number fluid again. */
const FLUID = /min\(|max\(|clamp\(|%|vw|vh|dvh|dvw|calc\(|auto|100%/;

/**
 * R7 scope — roots that decide a page's shape. Deliberately NOT *-screen.tsx: a screen
 * inside a layout that already caps its column is correct as it stands, and demanding a
 * breakpoint from it would punish the arrangement wanted. The layout is what answers.
 */
const ROOT_FILE = /(-(shell|app|sidebar)|\/layout)\.tsx$/;

const errors: string[] = [];

/** Lib: collectFiles */
function collectFiles(dir: string, ext: string): string[] {
  const out: string[] = [];
  let entries: string[];
  try {
    entries = readdirSync(dir);
  } catch {
    return out;
  }
  for (const entry of entries) {
    if (entry === 'node_modules' || entry === 'generated') continue;
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) out.push(...collectFiles(full, ext));
    else if (entry.endsWith(ext)) out.push(full);
  }
  return out;
}

/** Lib: lineOf */
function lineOf(content: string, index: number): number {
  return content.slice(0, index).split('\n').length;
}

/** Lib: rel */
function rel(file: string): string {
  return file.slice(ROOT.length + 1);
}

/** Lib: mediaBodies
 * The body of every width media query in a sheet, walked to the matching brace so nested rules count.
 */
function mediaBodies(content: string): string[] {
  const bodies: string[] = [];
  for (const block of content.matchAll(/@media[^{]*width[^{]*\{/g)) {
    let depth = 1;
    let i = block.index + block[0].length;
    const start = i;
    while (i < content.length && depth > 0) {
      if (content[i] === '{') depth++;
      else if (content[i] === '}') depth--;
      i++;
    }
    bodies.push(content.slice(start, i));
  }
  return bodies;
}

/*
 * Every sheet the entry imports is read, not just the entry: a rule moved into its own file is
 * still a rule. A sheet the entry does not import never loads, so it is an error rather than a
 * source of declarations — see scripts/lib/stylesheets.ts.
 */
const { sheets, unimported } = loadStylesheets(STYLES_DIR);
const ENTRY = join(STYLES_DIR, ENTRY_STYLESHEET);

if (sheets.length === 0) {
  console.error(`[check-responsive] ✗ cannot read ${rel(ENTRY)} — nothing to check.`);
  process.exit(1);
}

const css = sheets.map((s) => s.content).join('\n');

for (const file of unimported) {
  errors.push(
    `${rel(file)} — stylesheet is not imported by ${rel(ENTRY)}\n` +
      `    Fix: @import it from ${ENTRY_STYLESHEET}, or delete it. Its rules never load, so any class\n` +
      `    it declares renders unstyled. (RESP R4)`,
  );
}

const tsxFiles = collectFiles(SRC, '.tsx').filter((f) => !f.includes('/testing/'));
const jsx = tsxFiles.map((f) => ({ file: f, content: readFileSync(f, 'utf-8') }));

console.log(
  `[check-responsive] Scanning ${sheets.map((s) => rel(s.file)).join(', ')} and ${tsxFiles.length} component files...`,
);

/* ── R1 — no pixel literal in a width media query ───────────────────────────── */
for (const { file, content } of sheets) {
  for (const m of content.matchAll(/@media[^{]*?\b(?:min|max)-width:\s*\d[^{]*/g)) {
    errors.push(
      `${rel(file)}:${lineOf(content, m.index)} — media query uses a pixel literal\n` +
        `    ${m[0].trim().slice(0, 90)}\n` +
        `    Fix: read the breakpoint by name — @media (width < theme(--breakpoint-md)). (RESP R1)`,
    );
  }
}

/* ── R2 — the tokens R1 points at must exist ────────────────────────────────── */
for (const name of ['sm', 'md', 'lg', 'xl']) {
  if (!new RegExp(`--breakpoint-${name}\\s*:`).test(css)) {
    errors.push(
      `${rel(ENTRY)} — --breakpoint-${name} is not declared in @theme\n` +
        `    Fix: declare it in rem alongside the others; R1 has nothing to name without it. (RESP R2)`,
    );
  }
}

/* ── R3 — a class inside a width media query needs a consumer in JSX ────────── */
/** Owned class → the sheet whose media query styles it, for the error message. */
const inMedia = new Map<string, string>();
for (const { file, content } of sheets) {
  for (const body of mediaBodies(content)) {
    for (const sel of body.matchAll(/\.([a-zA-Z][\w-]*)/g)) {
      const name = sel[1] ?? '';
      if (OWNED.some((p) => name.startsWith(p)) && !inMedia.has(name)) {
        inMedia.set(name, file);
      }
    }
  }
}
for (const [cls, file] of inMedia) {
  const used = jsx.some(({ content }) => content.includes(cls));
  if (!used) {
    errors.push(
      `${rel(file)} — .${cls} has a rule inside a media query but no consumer in JSX\n` +
        `    Delete it or apply it. A responsive rule nobody applies is a layout that has never\n` +
        `    rendered. (RESP R3)`,
    );
  }
}

/* ── R4 — a project-prefixed class in JSX needs a rule behind it ────────────── */
const declared = new Set([
  ...[...css.matchAll(/\.([a-zA-Z][\w-]*)/g)].map((m) => m[1]),
  /*
   * @utility declares a class too, and it is how Tailwind v4 wants custom utilities
   * written — they get variants for free. Missing these flags every one of them.
   */
  ...[...css.matchAll(/@utility\s+([a-zA-Z][\w-]*)/g)].map((m) => m[1]),
]);
for (const { file, content } of jsx) {
  for (const attr of content.matchAll(/className=(?:"([^"]*)"|\{`([^`]*)`\})/g)) {
    const raw = attr[1] ?? attr[2] ?? '';
    if (raw.includes('${')) continue; /* interpolated — the static half is still below */
    for (const cls of raw.split(/\s+/).filter(Boolean)) {
      if (!OWNED.some((p) => cls.startsWith(p))) continue;
      if (declared.has(cls)) continue;
      errors.push(
        `${rel(file)}:${lineOf(content, attr.index)} — .${cls} is applied but has no CSS rule\n` +
          `    Fix: add the rule, or drop the class. It renders unstyled and reads as a spacing\n` +
          `    bug rather than a missing rule. (RESP R4)`,
      );
    }
  }
}

/**
 * Classes whose media query sets a width — on themselves or on their children via `> *`.
 * An element inside one of these already collapses at the breakpoint, so a fixed width on
 * it is not a blocker: `.app-dashboard > * { width: 100% !important }` makes every rail inside
 * it correct, however fixed it looks.
 */
const widthHandled = new Set<string>();
for (const body of sheets.flatMap(({ content }) => mediaBodies(content))) {
  for (const rule of body.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    if (!/\bwidth\s*:/.test(rule[2] ?? '')) continue;
    for (const sel of (rule[1] ?? '').matchAll(/\.([a-zA-Z][\w-]*)/g))
      widthHandled.add(sel[1] ?? '');
  }
}

/* ── R5 — inline dimension >= 200px needs a fluid guard ─────────────────────── */
for (const { file, content } of jsx) {
  if ([...widthHandled].some((c) => content.includes(c))) continue;
  for (const m of content.matchAll(/\b(width|minWidth|flexBasis)\s*:\s*(['"]?)([\d.]+)(px)?\2/g)) {
    const value = Number(m[3]);
    if (!Number.isFinite(value) || value < DIMENSION_FLOOR) continue;
    const decl = content.slice(m.index, m.index + 120);
    if (FLUID.test(decl.split(/[,}\n]/)[0] ?? '')) continue;
    /*
     * `flex: 1, minWidth: N` inside a wrapping row is the wrap POINT, not a blocker —
     * it is what makes the row break instead of squashing, as long as the parent sets
     * flexWrap. Flagging these would teach people to break them.
     */
    const around = content.slice(Math.max(0, m.index - 160), m.index + 160);
    if (m[1] === 'minWidth' && /\bflex\s*:/.test(around) && content.includes('flexWrap')) continue;
    errors.push(
      `${rel(file)}:${lineOf(content, m.index)} — ${m[1]}: ${value} cannot shrink\n` +
        `    Fix: min(${value}px, 100%). At or above ${DIMENSION_FLOOR}px this is layout, and layout\n` +
        `    that cannot shrink overflows. (RESP R5)`,
    );
  }
}

/* ── R6 — a grid track >= 280px needs min() ─────────────────────────────────── */
for (const { file, content } of jsx) {
  for (const m of content.matchAll(/minmax\(\s*([\d.]+)px/g)) {
    if (Number(m[1]) < TRACK_FLOOR) continue;
    const head = content.slice(Math.max(0, m.index - 10), m.index + m[0].length);
    if (head.includes('min(')) continue;
    errors.push(
      `${rel(file)}:${lineOf(content, m.index)} — grid track floor of ${m[1]}px cannot collapse\n` +
        `    Fix: minmax(min(${m[1]}px, 100%), 1fr). Without it the track overflows its container\n` +
        `    instead of dropping to one column. (RESP R6)`,
    );
  }
}

/*
 * ── R7 — shell and screen roots must be responsive by SOME mechanism ─────────
 * A Tailwind variant is `md:flex` — colon then a utility character. A CVA size key is
 * `md: 'px-4'` — colon then a space. Only the first is a breakpoint.
 */
const VARIANT = /\b(?:sm|md|lg|xl|2xl):[a-z[-]/;
/**
 * A file that never writes a layout property is not deciding a shape — it is a provider
 * or it delegates to a shell. Demanding a breakpoint from `<AppShell>{children}</AppShell>`
 * would be asking the wrong file.
 */
const LAYOUT_BEARING =
  /className=[^>]*\b(flex|grid|w-|h-|max-w|min-h|inset|absolute|fixed|columns)/;

for (const { file, content } of jsx) {
  if (!ROOT_FILE.test(file)) continue;
  if (!LAYOUT_BEARING.test(content)) continue;
  const viaVariant = VARIANT.test(content);
  const viaMediaClass = [...inMedia.keys()].some((c) => content.includes(c));
  const viaFluid = /clamp\(|minmax\(|\bmin\(|\d(?:vw|dvh|dvw)\b/.test(content);
  if (viaVariant || viaMediaClass || viaFluid) continue;
  errors.push(
    `${rel(file)} — screen root with no responsive mechanism at all\n` +
      `    Fix: a Tailwind variant, a class a media query reaches, or a fluid value. Any one\n` +
      `    counts — the shell may legitimately do all of it in CSS. (RESP R7)`,
  );
}

if (errors.length > 0) {
  console.error(`\n[check-responsive] ✗ ${errors.length} violation(s):\n`);
  for (const error of errors) console.error(`  ${error}\n`);
  console.error('[check-responsive] See .claude/rules/web/responsive.md for the standard.');
  process.exit(1);
}

console.log('[check-responsive] ✓ Breakpoints are named, and no fixed value blocks a narrow view.');
