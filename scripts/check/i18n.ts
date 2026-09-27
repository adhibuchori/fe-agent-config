#!/usr/bin/env bun
/**
 * Checks for:
 * 1. Unused translation keys (keys in en.json not referenced in src/)
 * 2. Sync mismatch (keys present in en.json but missing in id.json, or vice versa)
 * 3. Unscoped useTranslations() calls (Rule 20 violation)
 * 4. Missing keys: a literal t('key') in a scoped file that none of the file's namespaces holds
 *    in en.json. It would throw MISSING_MESSAGE at runtime, on the one screen nobody opened.
 *    A key built at runtime (t(`${x}.title`)) cannot be resolved; it is listed, not failed.
 *
 * Exit code 1 if unused keys or sync mismatch found.
 * Unscoped violations are warnings only (exit 0).
 */

import { readFileSync, readdirSync, statSync } from 'fs';
import { join, relative, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const ROOT = join(dirname(__filename), '../..');
const EN_PATH = join(ROOT, 'src/messages/en.json');
const ID_PATH = join(ROOT, 'src/messages/id.json');
const SRC_DIR = join(ROOT, 'src');

/* ── Flatten JSON keys ──────────────────────────────────────────────────────── */

function flattenKeys(obj: Record<string, unknown>, prefix = ''): string[] {
  const keys: string[] = [];
  for (const [k, v] of Object.entries(obj)) {
    const path = prefix ? `${prefix}.${k}` : k;
    if (v !== null && typeof v === 'object' && !Array.isArray(v)) {
      keys.push(...flattenKeys(v as Record<string, unknown>, path));
    } else {
      keys.push(path);
    }
  }
  return keys;
}

/* ── Collect all .ts/.tsx source files ─────────────────────────────────────── */

function collectSourceFiles(dir: string): string[] {
  const files: string[] = [];
  for (const entry of readdirSync(dir)) {
    const fullPath = join(dir, entry);
    const stat = statSync(fullPath);
    if (stat.isDirectory()) {
      files.push(...collectSourceFiles(fullPath));
    } else if (/\.(ts|tsx)$/.test(entry)) {
      files.push(fullPath);
    }
  }
  return files;
}

/* ── Extract t('key') calls from source ────────────────────────────────────── */

function extractUsedKeys(files: string[]): Set<string> {
  const used = new Set<string>();
  /* Matches t('key'), t("key"), t('key', {...}), t.rich('key', {...}), t.raw('key') */
  const tCallPattern = /\bt(?:\.(?:rich|raw))?\(\s*['"`]([^'"`]+)['"`]/g;
  for (const file of files) {
    const content = readFileSync(file, 'utf-8');
    let match: RegExpExecArray | null;
    while ((match = tCallPattern.exec(content)) !== null) {
      used.add(match[1] ?? '');
    }
  }
  return used;
}

/* ── Detect unscoped use/getTranslations() (Rule 20 violation) ─────────────── */

function detectUnscopedTranslations(files: string[]): string[] {
  const violations: string[] = [];
  /* No argument, or an empty one — in either the client or the server entry point. */
  const unscopedPattern =
    /(?:use|get)Translations\(\s*\)|(?:use|get)Translations\(\s*['"]\s*['"]\s*\)/;
  for (const file of files) {
    const content = readFileSync(file, 'utf-8');
    if (unscopedPattern.test(content)) {
      violations.push(relative(ROOT, file));
    }
  }
  return violations;
}

/* ── Detect keys used with dotted path on unscoped t() ──────────────────────── */

function extractNamespaceFromUsage(files: string[]): Map<string, string[]> {
  /** Returns map of file → list of namespaces used via a scoped translator.
   *
   * Matches both next-intl entry points: `useTranslations` in Client Components and
   * `getTranslations` in Server Components. Missing the server one reports its keys as unused,
   * which invites deleting keys that a rendered page depends on. */
  const map = new Map<string, string[]>();
  const scopedPattern = /(?:use|get)Translations\(\s*['"`]([^'"`]+)['"`]\s*\)/g;
  for (const file of files) {
    const content = readFileSync(file, 'utf-8');
    const namespaces: string[] = [];
    let match: RegExpExecArray | null;
    while ((match = scopedPattern.exec(content)) !== null) {
      namespaces.push(match[1] ?? '');
    }
    if (namespaces.length > 0) {
      map.set(relative(ROOT, file), namespaces);
    }
  }
  return map;
}

/* ── Resolve which full keys are reachable given scoped usage ───────────────── */

function resolveReachableKeys(
  allKeys: string[],
  files: string[],
  unscopedFiles: string[],
): Set<string> {
  const reachable = new Set<string>();

  /* For unscoped files, t() calls use fully-qualified keys (e.g. t('nav.home')) */
  const unscopedSet = new Set(unscopedFiles.map((f) => join(ROOT, f)));
  const unscopedUsed = extractUsedKeys(files.filter((f) => unscopedSet.has(f)));
  for (const key of unscopedUsed) {
    reachable.add(key);
    /* Mark entire namespace as reachable if unscoped file references it */
    const ns = key.split('.')[0];
    for (const k of allKeys) {
      if (k.startsWith(ns + '.')) reachable.add(k);
    }
  }

  /* For scoped files, collect per-file namespace → subkeys used */
  const scopedFiles = files.filter((f) => !unscopedSet.has(f));
  const nsMap = extractNamespaceFromUsage(scopedFiles);

  /* Build a map: file → Set<namespace> */
  const fileNsMap = new Map<string, Set<string>>();
  for (const [relPath, namespaces] of nsMap.entries()) {
    fileNsMap.set(join(ROOT, relPath), new Set(namespaces));
  }

  /* For each scoped file, extract t() subkeys and resolve with that file's namespaces */
  for (const file of scopedFiles) {
    const namespaces = fileNsMap.get(file);
    if (!namespaces || namespaces.size === 0) continue;

    const content = readFileSync(file, 'utf-8');
    /* Translator variables are `t` or `t` followed by a capitalised namespace hint — `tNav`,
       `tStatus`, `tForm`. The capital is what keeps the pattern honest: matching any
       lowercase continuation would swallow `toString(`, `trim(`, `then(`, and a single such
       hit inside `dynamicPattern` marks a whole namespace reachable, which would quietly
       retire the unused-key check. Naming a translator `tfoo` therefore goes unseen — by
       design, since that is not a name anyone reaches for. */
    const tCallPattern = /\bt(?:[A-Z]\w*)?(?:\.(?:rich|raw))?\(\s*['"`]([^'"`]+)['"`]/g;
    let match: RegExpExecArray | null;
    while ((match = tCallPattern.exec(content)) !== null) {
      const subKey = match[1];
      for (const ns of namespaces) {
        const fullKey = `${ns}.${subKey}`;
        reachable.add(fullKey);
        /* Also mark entire subtree reachable if subkey is a parent path */
        for (const k of allKeys) {
          if (k.startsWith(fullKey + '.') || k === fullKey) reachable.add(k);
        }
      }
    }

    /* Handle template string patterns: t(`errors.${key}`) — mark only the static prefix
       reachable, not the whole namespace. Marking the namespace blinds dead-key detection for
       every key under it (.claude/anti-patterns/i18n-template-key-blinds-namespace.md); a
       template with no static prefix, t(`${key}.title`), still marks the whole namespace. */
    const templatePattern = /\bt(?:[A-Z]\w*)?(?:\.(?:rich|raw))?\(\s*`([^`$]*)\$\{/g;
    while ((match = templatePattern.exec(content)) !== null) {
      const staticPrefix = (match[1] || '').replace(/\.$/, '');
      for (const ns of namespaces) {
        const scope = staticPrefix ? ns + '.' + staticPrefix : ns;
        for (const k of allKeys) {
          if (k.startsWith(scope + '.')) reachable.add(k);
        }
      }
    }

    /* Handle dynamic variable: t(someVar) — mark whole namespace as reachable */
    const dynamicPattern = /\bt(?:[A-Z]\w*)?(?:\.(?:rich|raw))?\(\s*[^'"`)\s][^)]*\)/g;
    while ((match = dynamicPattern.exec(content)) !== null) {
      for (const ns of namespaces) {
        for (const k of allKeys) {
          if (k.startsWith(ns + '.')) reachable.add(k);
        }
      }
    }
  }

  return reachable;
}

/* ── Main ───────────────────────────────────────────────────────────────────── */

const en = JSON.parse(readFileSync(EN_PATH, 'utf-8')) as Record<string, unknown>;
const id = JSON.parse(readFileSync(ID_PATH, 'utf-8')) as Record<string, unknown>;

const enKeys = flattenKeys(en);
const idKeys = new Set(flattenKeys(id));

console.log(`[i18n] Scanning ${enKeys.length} keys (en.json)...`);

const sourceFiles = collectSourceFiles(SRC_DIR);
console.log(`[i18n] Checking ${sourceFiles.length} source files...`);

/* 1. Sync mismatch */
const missingInId = enKeys.filter((k) => !idKeys.has(k));
const missingInEn = flattenKeys(id).filter((k) => !new Set(enKeys).has(k));

/* 2. Unscoped violations */
const unscopedViolations = detectUnscopedTranslations(sourceFiles);

/* 3. Unused keys */
const reachable = resolveReachableKeys(enKeys, sourceFiles, unscopedViolations);

/* A key is considered used if it is reachable OR any of its parent paths are
   reachable (for object-level access patterns) */
const unusedKeys = enKeys.filter((key) => {
  if (reachable.has(key)) return false;
  /* Check if any parent key references this namespace (e.g., t('nav') used as object) */
  const parts = key.split('.');
  for (let i = 1; i < parts.length; i++) {
    if (reachable.has(parts.slice(0, i).join('.'))) return false;
  }
  return true;
});

/* ── Missing keys: a scoped t('key') that no namespace of its file holds ──── */

function findMissingKeys(
  allKeys: Set<string>,
  files: string[],
): { missing: string[]; dynamic: string[] } {
  const missing: string[] = [];
  const dynamic: string[] = [];
  const namespaces = extractNamespaceFromUsage(files);
  for (const [rel, spaces] of namespaces.entries()) {
    const content = readFileSync(join(ROOT, rel), 'utf-8');
    const literal = /\bt(?:[A-Z]\w*)?(?:\.(?:rich|raw|markup|has))?\(\s*(['"])([^'"]+)\1/g;
    let match: RegExpExecArray | null;
    while ((match = literal.exec(content)) !== null) {
      const key = match[2] ?? '';
      const found = spaces.some(
        (ns) =>
          allKeys.has(`${ns}.${key}`) || [...allKeys].some((k) => k.startsWith(`${ns}.${key}.`)),
      );
      if (!found)
        missing.push(`${rel}: '${key}' is in none of ${spaces.map((ns) => `'${ns}'`).join(', ')}`);
    }
    const built = /\bt(?:[A-Z]\w*)?(?:\.(?:rich|raw|markup))?\(\s*`[^`]*\$\{/g;
    while ((match = built.exec(content)) !== null) dynamic.push(`${rel}: ${match[0]}…`);
  }
  return { missing, dynamic };
}

const { missing: missingKeys, dynamic: dynamicKeys } = findMissingKeys(
  new Set(enKeys),
  sourceFiles,
);

/* ── Report ─────────────────────────────────────────────────────────────────── */

let hasErrors = false;

if (missingInId.length > 0) {
  console.error(`\n[i18n] ✗ Keys in en.json missing from id.json (${missingInId.length}):`);
  for (const k of missingInId) console.error(`  - ${k}`);
  hasErrors = true;
} else {
  console.log('[i18n] ✓ en.json ↔ id.json sync: OK');
}

if (missingInEn.length > 0) {
  console.error(`\n[i18n] ✗ Keys in id.json missing from en.json (${missingInEn.length}):`);
  for (const k of missingInEn) console.error(`  - ${k}`);
  hasErrors = true;
}

if (unusedKeys.length > 0) {
  console.error(`\n[i18n] ✗ Unused keys (${unusedKeys.length}):`);
  for (const k of unusedKeys) console.error(`  - ${k}`);
  hasErrors = true;
} else {
  console.log('[i18n] ✓ No unused keys found');
}

if (missingKeys.length > 0) {
  console.error(`\n[i18n] ✗ Keys used in code but missing from en.json (${missingKeys.length}):`);
  for (const k of missingKeys) console.error(`  - ${k}`);
  hasErrors = true;
} else {
  console.log('[i18n] ✓ Every literal key a scoped translator uses exists in en.json');
}
if (dynamicKeys.length > 0) {
  console.warn(`\n[i18n] ⚠ Keys built at runtime, not checked (${dynamicKeys.length}):`);
  for (const k of dynamicKeys) console.warn(`  - ${k}`);
}

if (unscopedViolations.length > 0) {
  console.warn(
    `\n[i18n] ⚠ Unscoped useTranslations() — Rule 20 violation (${unscopedViolations.length} files):`,
  );
  for (const f of unscopedViolations) console.warn(`  - ${f}`);
  console.warn("[i18n]   Fix: useTranslations('namespace') instead of useTranslations()");
} else {
  console.log('[i18n] ✓ All useTranslations() calls are scoped');
}

console.log('');
if (hasErrors) {
  console.error('[i18n] ✗ Check failed — fix the issues above before committing.');
  process.exit(1);
} else if (unscopedViolations.length > 0) {
  console.log('[i18n] ⚠ Check passed with warnings (unscoped violations — not blocking).');
  process.exit(0);
} else {
  console.log('[i18n] ✓ All checks passed.');
  process.exit(0);
}
