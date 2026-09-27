/**
 * Reading a source tree the way the payload checks need it: every TypeScript file, with comments
 * and API prose blanked so a sentence that names a route is never read as code, and JSON compared
 * by meaning rather than by formatting.
 */

import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

export function sourceFiles(dir: string, out: string[] = []): string[] {
  if (!existsSync(dir)) return out;
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) sourceFiles(full, out);
    else if (/\.(ts|tsx|mts)$/.test(entry) && !entry.endsWith('.d.ts')) out.push(full);
  }
  return out;
}

/* Comments, and the prose OpenAPI keeps in `summary` and `description`, are blanked rather than
   removed, so line numbers stay right. A rule that failed on naming a route in a sentence would be
   obeyed by deleting the sentence. `//` counts only after whitespace, so a URL keeps its text. */
const blank = (match: string): string => match.replace(/[^\n]/g, ' ');

export function codeOnly(source: string): string {
  return source
    .replace(/\b(?:description|summary)\s*:\s*(['"`])(?:\\.|(?!\1)[\s\S])*?\1/g, blank)
    .replace(/\/\*[\s\S]*?\*\//g, blank)
    .replace(/(^|\s)\/\/[^\n]*/g, blank);
}

export function lineOf(source: string, index: number): number {
  return source.slice(0, index).split('\n').length;
}

export const isTest = (rel: string): boolean =>
  /(^|\/)(__tests__|testing|test)\//.test(rel) || /\.(test|spec)\.tsx?$/.test(rel);
export const allowed = (rel: string, list: string[]): boolean =>
  list.some((prefix) => rel.startsWith(prefix));

export function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (!isRecord(value)) return value;
  return Object.fromEntries(
    Object.keys(value)
      .toSorted()
      .map((key) => [key, sortKeys(value[key])]),
  );
}
export const canonical = (path: string): string =>
  JSON.stringify(sortKeys(JSON.parse(readFileSync(path, 'utf8'))));
