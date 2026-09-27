#!/usr/bin/env bun
/**
 * DESC — dialog description standard. Optional module: delete it with its rule.
 * See .claude/rules/web/dialog-content.md for the eight rules and the reasoning behind them.
 *
 * Checks for:
 * 1. Structure — every dialog passes `descriptionId`, or opts out with a `desc-exempt` comment
 * 2. Copy — description strings say something, in the shape the standard asks for
 * 3. Naming — description keys end in `Description`, never `Desc`
 *
 * Exit code 1 on any violation. There are no warning-only rules here: a description that is
 * missing or empty is exactly the defect this script exists to stop shipping.
 */

import { existsSync, readdirSync, readFileSync, statSync } from 'fs';
import { dirname, join, relative } from 'path';
import { fileURLToPath } from 'url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const SRC_DIR = join(ROOT, 'src');
const MESSAGES_DIR = join(ROOT, 'src/messages');

/* The component names of this repo's dialog shells. `<Modal` is matched as a whole tag, so
   `<ModalHeader>` is not mistaken for the shell. Add yours if it is named differently. */
const DIALOG_TAGS = ['Modal'];

const MAX_DESCRIPTION_LENGTH = 200;

/* Rule 3, per locale file name. A description opening this way has told the reader nothing the
   title did not. A locale with no list here still gets every other check. */
const BANNED_OPENERS: Record<string, RegExp[]> = {
  en: [
    /^\s*are you sure\b/i,
    /^\s*warning[!:]/i,
    /^\s*please note\b/i,
    /^\s*(oops|sorry)\b/i,
    /^\s*this action cannot be undone\.?\s*$/i,
    /^\s*something went wrong\.?\s*$/i,
  ],
  id: [
    /^\s*apakah (anda|kamu) yakin\b/i,
    /^\s*(peringatan|perhatian)[!:]/i,
    /^\s*(maaf|ups)\b/i,
    /^\s*tindakan ini tidak dapat (dibatalkan|diurungkan)\.?\s*$/i,
    /^\s*terjadi kesalahan\.?\s*$/i,
  ],
};

/* The opt-out marker (rule 8). It must sit within 400 characters before the dialog — close enough
   that a reviewer reading the dialog sees the reason without hunting for it. */
const EXEMPT = /desc-exempt:\s*\S/;

/* ── File collection ────────────────────────────────────────────────────────── */

function collectSourceFiles(dir: string): string[] {
  const files: string[] = [];
  for (const entry of readdirSync(dir)) {
    if (entry === 'node_modules' || entry === 'generated') continue;
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) files.push(...collectSourceFiles(full));
    else if (entry.endsWith('.tsx')) files.push(full);
  }
  return files;
}

function flatten(obj: Record<string, unknown>, prefix = ''): Map<string, string> {
  const out = new Map<string, string>();
  for (const [k, v] of Object.entries(obj)) {
    const path = prefix ? `${prefix}.${k}` : k;
    if (v !== null && typeof v === 'object' && !Array.isArray(v)) {
      for (const [ik, iv] of flatten(v as Record<string, unknown>, path)) out.set(ik, iv);
    } else if (typeof v === 'string') {
      out.set(path, v);
    }
  }
  return out;
}

const errors: string[] = [];

/* ── 1. Structure ───────────────────────────────────────────────────────────── */

/* Matches an opening dialog tag and everything up to the `>` that closes it, so the attribute
   list can be inspected as one blob. */
const dialogOpenTag = new RegExp(`<(${DIALOG_TAGS.join('|')})(\\s[^>]*?)?>`, 'gs');

const sourceFiles = existsSync(SRC_DIR) ? collectSourceFiles(SRC_DIR) : [];

for (const file of sourceFiles) {
  const content = readFileSync(file, 'utf-8');
  const rel = relative(ROOT, file);

  for (const match of content.matchAll(dialogOpenTag)) {
    const tag = match[1];
    const attrs = match[2] ?? '';

    if (/\bdescriptionId=\{(?!undefined\})/.test(attrs)) continue;
    const before = content.slice(Math.max(0, match.index - 400), match.index);
    if (EXEMPT.test(before)) continue;

    const line = content.slice(0, match.index).split('\n').length;
    errors.push(
      `${rel}:${line}  <${tag}> has no descriptionId.\n` +
        `    Fix: pass descriptionId, or opt out with {/* desc-exempt: <reason> */} above the tag.`,
    );
  }

  /* Hand-built dialogs too. A surface that declares itself a dialog to assistive technology owes
     the same description, whether or not it uses the shared shell. */
  for (const match of content.matchAll(/role="(dialog|alertdialog)"/g)) {
    const openTag = content.slice(Math.max(0, match.index - 600), match.index + 600);
    if (/aria-describedby=\{(?!undefined\})/.test(openTag)) continue;
    const before = content.slice(Math.max(0, match.index - 400), match.index);
    if (EXEMPT.test(before)) continue;
    const line = content.slice(0, match.index).split('\n').length;
    errors.push(
      `${rel}:${line}  role="${match[1]}" with no aria-describedby.\n` +
        `    Fix: point it at a description, or opt out with {/* desc-exempt: <reason> */}.`,
    );
  }

  /* Naming, checked at the call site rather than across every key in the message file. A repo has
     plenty of `…Desc` keys that are captions or body copy and have nothing to do with a dialog;
     only the ones actually feeding a dialog description have to be findable by name. */
  for (const site of content.matchAll(
    /id=\{descriptionId\}[\s\S]{0,200}?>|description=\{(?=[^}]*\bt)/g,
  )) {
    const region = content.slice(site.index, site.index + site[0].length + 120);
    const call = region.match(/\bt[A-Z]?\w*\(\s*'([^']+)'/);
    if (!call) continue;
    const key = call[1] ?? '';
    if (key.endsWith('escription')) continue;
    /* Only a dialog's own description is in scope — the same prop name is used by cards and
       state views, which this standard says nothing about. */
    const near = content.slice(Math.max(0, site.index - 300), site.index);
    if (!/descriptionId/.test(near) && !/id=\{descriptionId\}/.test(site[0])) continue;
    const line = content.slice(0, site.index).split('\n').length;
    errors.push(
      `${rel}:${line}  dialog description uses the key '${key}'.\n` +
        `    Fix: name it '…Description' — DESC uses one suffix so descriptions stay findable.`,
    );
  }
}

/* ── 2 & 3. Copy and naming ─────────────────────────────────────────────────── */

/* A key is a dialog description if it is named like one. `.body` counts only under a `confirm.`
   path, which is how confirm dialogs name theirs — an unqualified `.body` is just as often a
   sentence fragment with a value appended, and those are not descriptions. */
const isDescriptionKey = (k: string) =>
  /(\.|^)description$/i.test(k) || k.endsWith('Description') || /\.confirm\.[^.]+\.body$/i.test(k);

const localeFiles = existsSync(MESSAGES_DIR)
  ? readdirSync(MESSAGES_DIR).filter((name) => name.endsWith('.json'))
  : [];

for (const name of localeFiles) {
  const locale = name.replace(/\.json$/, '');
  const flat = flatten(JSON.parse(readFileSync(join(MESSAGES_DIR, name), 'utf-8')));

  for (const [key, value] of flat) {
    if (!isDescriptionKey(key)) continue;

    const text = value.trim();

    if (!text) {
      errors.push(`${name}  ${key} is empty.`);
      continue;
    }

    for (const banned of BANNED_OPENERS[locale] ?? []) {
      if (banned.test(text)) {
        errors.push(
          `${name}  ${key}\n    "${text}"\n` +
            `    Fix: state the consequence instead — what changes, and what does not. (DESC rule 2/3)`,
        );
        break;
      }
    }

    if (text.length > MAX_DESCRIPTION_LENGTH) {
      errors.push(
        `${name}  ${key} is ${text.length} chars (max ${MAX_DESCRIPTION_LENGTH}).\n` +
          `    Fix: one or two sentences. (DESC rule 6)`,
      );
    }

    if (!/[.!?]$/.test(text)) {
      errors.push(
        `${name}  ${key}\n    "${text}"\n` +
          `    Fix: end with a full stop — a description is a sentence, not a label. (DESC rule 6)`,
      );
    }

    /* Rule 6: a description that repeats its own title is a description in name only. */
    const siblingTitle = flat.get(key.replace(/(description|body)$/i, 'title'));
    if (siblingTitle && siblingTitle.trim().toLowerCase() === text.toLowerCase()) {
      errors.push(
        `${name}  ${key} is identical to its title.\n` +
          `    Fix: say something the title does not. (DESC rule 6)`,
      );
    }
  }
}

/* ── Report ─────────────────────────────────────────────────────────────────── */

console.log(
  `[dialog-desc] Scanning ${sourceFiles.length} components and ${localeFiles.length} message file(s)...`,
);

if (errors.length > 0) {
  console.error(`\n[dialog-desc] ✗ ${errors.length} violation(s):\n`);
  for (const e of errors) console.error(`  ${e}\n`);
  console.error('[dialog-desc] See .claude/rules/web/dialog-content.md for the standard.');
  process.exit(1);
}

console.log('[dialog-desc] ✓ Every dialog has an announced description.');
