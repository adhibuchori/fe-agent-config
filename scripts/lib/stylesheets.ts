/**
 * Loading the stylesheets `scripts/check/responsive.ts` validates.
 *
 * `globals.css` is the entry the app imports; any other `.css` under `src/styles/` counts only
 * when that entry `@import`s it. A sheet nobody imports never reaches the browser, so reading its
 * rules anyway would let a class pass R4 while rendering unstyled — the exact failure R4 exists
 * to catch. Such a sheet is reported instead of loaded.
 */

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

export const ENTRY_STYLESHEET = 'globals.css';

interface Stylesheet {
  /** Absolute path. */
  file: string;
  content: string;
}

export interface LoadedStylesheets {
  /** The entry first, then every imported sheet. Empty when the entry is missing. */
  sheets: Stylesheet[];
  /** Absolute paths of `.css` files under the directory that the entry does not import. */
  unimported: string[];
}

/* Recursive, so a sheet can live in a subfolder; a missing directory is simply empty. */
function collectCss(dir: string): string[] {
  let entries: string[];
  try {
    entries = readdirSync(dir);
  } catch {
    return [];
  }
  return entries.flatMap((entry) => {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) return collectCss(full);
    return entry.endsWith('.css') ? [full] : [];
  });
}

/* Both `@import './a.css'` and `@import url("a.css")` resolve relative to the entry. */
function importedPaths(entry: string): Set<string> {
  const paths = new Set<string>();
  for (const m of entry.matchAll(/@import\s+(?:url\(\s*)?['"]([^'"]+\.css)['"]/g)) {
    paths.add((m[1] ?? '').replace(/^\.\//, ''));
  }
  return paths;
}

/** Lib: loadStylesheets
 * Reads the entry stylesheet in `stylesDir` and every sheet it imports, and names the ones it does not.
 */
export function loadStylesheets(stylesDir: string): LoadedStylesheets {
  const entryFile = join(stylesDir, ENTRY_STYLESHEET);
  let entry: string;
  try {
    entry = readFileSync(entryFile, 'utf-8');
  } catch {
    return { sheets: [], unimported: [] };
  }

  const imported = importedPaths(entry);
  const sheets: Stylesheet[] = [{ file: entryFile, content: entry }];
  const unimported: string[] = [];

  for (const file of collectCss(stylesDir)) {
    if (file === entryFile) continue;
    const path = relative(stylesDir, file).split(sep).join('/');
    if (imported.has(path)) sheets.push({ file, content: readFileSync(file, 'utf-8') });
    else unimported.push(file);
  }

  return { sheets, unimported };
}
