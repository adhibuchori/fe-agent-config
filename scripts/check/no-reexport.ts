#!/usr/bin/env bun
/**
 * Refuses re-exports: a module may export only what it declares (AGENTS.md Rule 34).
 *
 * A re-export adds a second name for a binding without moving the dependency — the import it was
 * hiding is still there, one hop further away, and a rename or a layer boundary now has two paths
 * to keep in step. Import from the module that declares the name.
 *
 * Three shapes, all refused:
 *   export * from './x'            export * as ns from './x'
 *   export { a, type B } from './x'
 *   import { a } from './x'; export { a };     — the same forwarding, spelled in two statements
 *
 * Parsed with the TypeScript compiler rather than grepped: a multi-line `export { … } from` and
 * the two-statement form are both invisible to a line regex, so a sweep that trusts one reports a
 * tree clean while barrels still stand.
 *
 * `@documented` index.ts files are markers a docs generator reads by NAME, never by content —
 * they stay, exporting nothing (`export {}`), and pass this check like any other module.
 * `src/lib/api/generated/**` is emitted by a tool and excluded.
 */

import { existsSync, readdirSync, readFileSync, statSync } from 'fs';
import { dirname, join, relative } from 'path';
import { fileURLToPath } from 'url';
import ts from 'typescript';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const SRC = join(ROOT, 'src');
/* Generated output: a tool writes it, so a tool's choices are not this rule's to judge. */
const SKIP = ['src/lib/api/generated/'];

function collect(dir: string, out: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) collect(full, out);
    else if (/\.(ts|tsx|mts)$/.test(entry) && !entry.endsWith('.d.ts')) out.push(full);
  }
  return out;
}

type Finding = { rel: string; line: number; detail: string };
const findings: Finding[] = [];
const files = existsSync(SRC) ? collect(SRC) : [];

for (const file of files) {
  const rel = relative(ROOT, file);
  if (SKIP.some((prefix) => rel.startsWith(prefix))) continue;
  const text = readFileSync(file, 'utf8');
  const sf = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true);
  const lineOf = (node: ts.Node) => sf.getLineAndCharacterOfPosition(node.getStart(sf)).line + 1;

  const imported = new Set<string>();
  for (const stmt of sf.statements) {
    const clause = ts.isImportDeclaration(stmt) ? stmt.importClause : undefined;
    if (!clause) continue;
    if (clause.name) imported.add(clause.name.text);
    const bindings = clause.namedBindings;
    if (bindings && ts.isNamespaceImport(bindings)) imported.add(bindings.name.text);
    if (bindings && ts.isNamedImports(bindings)) {
      for (const el of bindings.elements) imported.add(el.name.text);
    }
  }

  for (const stmt of sf.statements) {
    if (!ts.isExportDeclaration(stmt)) continue;
    if (stmt.moduleSpecifier) {
      findings.push({ rel, line: lineOf(stmt), detail: stmt.getText(sf).split('\n')[0] ?? '' });
      continue;
    }
    const clause = stmt.exportClause;
    if (!clause || !ts.isNamedExports(clause)) continue;
    for (const el of clause.elements) {
      const local = (el.propertyName ?? el.name).text;
      if (imported.has(local)) {
        findings.push({ rel, line: lineOf(el), detail: `export { ${local} } forwards an import` });
      }
    }
  }
}

if (findings.length > 0) {
  console.error(`\nRe-exports: ${findings.length} found — import from the declaring module\n`);
  for (const f of findings) console.error(`  ✗ ${f.rel}:${f.line} — ${f.detail}`);
  console.error('');
  process.exit(1);
}

console.log(
  `Re-exports: none in ${files.length} file(s) — every module exports only what it declares`,
);
