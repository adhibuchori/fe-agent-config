#!/usr/bin/env bun
/**
 * SOC — refuses logic in the presentation layer (AGENTS.md Rule 32).
 * See .claude/rules/web/separation-of-concerns.md for S1–S11 and the reasoning behind them.
 *
 * The line this draws: a component file may declare props, call custom hooks, compose classes and
 * return JSX. It may not hold React state or effects, derive a domain value, reshape server data,
 * or reach for the browser. Behaviour and state belong in a custom hook under `src/hooks/`; pure
 * derivation belongs in `src/lib/`. A category with no command is a category nobody checks, which
 * is why each one is read here rather than left to a reviewer.
 *
 * The distinction that makes S5 work: `.map()` whose callback returns JSX is RENDERING and stays;
 * every other traversal is RESHAPING and moves. Without that the rule would forbid the normal way
 * to write a list. S9 (a `.ts` module under src/components/ reaching across a layer) is enforced by
 * the `no-restricted-imports` overrides in oxlint.json, not here.
 *
 * Exemptions live in `scripts/check/soc.allow.json` — path, check and a reason. An entry with no
 * reason fails, and so does one matching nothing, so the list cannot rot into a record of things
 * that used to be true.
 */

import { readdirSync, readFileSync, statSync } from 'fs';
import { dirname, join, relative, sep } from 'path';
import { fileURLToPath } from 'url';
import ts from 'typescript';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const COMPONENTS = join(ROOT, 'src/components');
const ALLOW_FILE = 'scripts/check/soc.allow.json';

/* Each check and the rule it enforces, for the report. */
const RULE = {
  'react-state-in-component': 'S1',
  'unbound-ref': 'S2',
  'function-in-component-file': 'S3',
  'date-logic': 'S4',
  'data-reshaping': 'S5',
  'browser-api': 'S6',
  'async-in-component': 'S7',
  'compound-domain-condition': 'S8',
  'handler-in-component': 'S10',
  'domain-literal-comparison': 'S11',
} as const;

type Check = keyof typeof RULE;
type Exemption = { path: string; check: Check; reason: string };
type Finding = { rel: string; line: number; check: Check; detail: string };

const findings: Finding[] = [];

function isExemption(entry: unknown): entry is Exemption {
  if (typeof entry !== 'object' || entry === null) return false;
  const { path, check, reason } = entry as Record<string, unknown>;
  return (
    typeof path === 'string' &&
    typeof check === 'string' &&
    check in RULE &&
    (reason === undefined || typeof reason === 'string')
  );
}

function loadExemptions(): Exemption[] {
  let text: string;
  try {
    text = readFileSync(join(ROOT, ALLOW_FILE), 'utf8');
  } catch {
    return [];
  }
  const parsed: unknown = JSON.parse(text);
  if (!Array.isArray(parsed)) throw new Error(`${ALLOW_FILE} must be an array`);
  const bad = parsed.filter((entry) => !isExemption(entry));
  if (bad.length > 0) {
    throw new Error(
      `${ALLOW_FILE}: ${bad.length} entr(ies) need a path, a known check and a reason`,
    );
  }
  return parsed.filter(isExemption);
}

const EXEMPTIONS = loadExemptions();
const used = new Set<number>();

function exempt(rel: string, check: Check): boolean {
  const at = EXEMPTIONS.findIndex((entry) => entry.path === rel && entry.check === check);
  if (at === -1) return false;
  used.add(at);
  return true;
}

function safeIsDirectory(path: string): boolean {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

function collectFiles(dir: string, out: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) collectFiles(full, out);
    else out.push(full);
  }
  return out;
}

/* Comments blanked to spaces, so line numbers still point at the right line and a docblock that
   explains a trap cannot be read as the trap itself. */
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

const lineOf = (source: string, index: number): number => source.slice(0, index).split('\n').length;

function report(rel: string, source: string, index: number, check: Check, detail: string): void {
  if (exempt(rel, check)) return;
  findings.push({ rel, line: lineOf(source, index), check, detail });
}

/** Whether the text that follows a `(` contains a JSX tag before the call closes. */
function callRendersJsx(source: string, open: number): boolean {
  let depth = 0;
  for (let i = open; i < source.length; i++) {
    const char = source[i];
    if (char === '(') depth++;
    else if (char === ')') {
      depth--;
      if (depth === 0) return false;
    } else if (char === '<' && /[A-Za-z>]/.test(source[i + 1] ?? '')) return true;
  }
  return false;
}

const RESHAPERS = ['filter', 'reduce', 'sort', 'toSorted', 'flatMap', 'some', 'every', 'find'];

const BROWSER = [
  'window.',
  'document.',
  'navigator.',
  'localStorage',
  'sessionStorage',
  'setTimeout(',
  'setInterval(',
  'requestAnimationFrame(',
  'IntersectionObserver',
  'ResizeObserver',
  'MutationObserver',
  /* A render-loop callback (react-three-fiber) runs every frame: it belongs in a named motion
     hook, like any other effect. */
  'useFrame(',
];

/* A repo with no presentation layer yet has nothing to audit, and says so. */
if (!safeIsDirectory(COMPONENTS)) {
  console.log('Separation of concerns: no src/components/ in this repo — nothing to audit');
  process.exit(0);
}

const componentFiles = collectFiles(COMPONENTS).filter((file) => file.endsWith('.tsx'));

/* Only components are scanned. A `.ts` beside a component is usually an icon or variant map, which
   file-organization rule 9 deliberately colocates with its single consumer; when such a file
   reaches across a layer instead, the `no-restricted-imports` boundary in oxlint.json catches it. */
for (const file of componentFiles) {
  const rel = relative(ROOT, file);
  const source = withoutComments(readFileSync(file, 'utf8'));

  /* S1. React state and effects belong in a custom hook. A paren or an opening generic, not `\(`
     alone: `useState<Filter>(` puts a type argument between the name and the paren, which a grep
     for `useState\(` misses. The generic must not be `</`, or the word `useEffect` in prose —
     `<span>useEffect</span>` — reads as a hook call. */
  for (const match of source.matchAll(
    /\b(useState|useEffect|useLayoutEffect|useReducer|useMemo|useCallback)(?:\(|<(?!\/))/g,
  )) {
    report(rel, source, match.index, 'react-state-in-component', `${match[1]} belongs in a hook`);
  }

  /* S2. A ref is presentation only while it binds a node to JSX in this same file. One used for
     timing or as a latest-value box is bookkeeping, and bookkeeping is behaviour. */
  for (const match of source.matchAll(/const (\w+) = useRef[<(]/g)) {
    const name = match[1] ?? '';
    const bound = new RegExp(`ref=\\{${name}(\\}|\\.)`).test(source);
    if (!bound) {
      report(rel, source, match.index, 'unbound-ref', `${name} is never passed to a JSX ref=`);
    }
  }

  /* S3. A function declared beside a component is a helper that escaped its layer; a `Lib:`
     docblock on it gives that away. */
  for (const match of source.matchAll(/^(?:export )?(?:async )?function ([a-z]\w*)\s*[(<]/gm)) {
    report(
      rel,
      source,
      match.index,
      'function-in-component-file',
      `${match[1]}() belongs in src/lib/ or the hook that calls it`,
    );
  }

  /* S4. Dates. Formatting and arithmetic are both derivation, and the time zone belongs in one place. */
  for (const match of source.matchAll(
    /\bnew Date\(|\bDate\.now\(|\.toLocaleDateString\(|\.toLocaleTimeString\(|timeZone:/g,
  )) {
    report(rel, source, match.index, 'date-logic', `${match[0]} belongs in src/lib/`);
  }

  /* S5. Reshaping versus rendering. */
  for (const match of source.matchAll(/\.(\w+)\(/g)) {
    const method = match[1] ?? '';
    if (method === 'map') {
      if (!callRendersJsx(source, match.index + match[0].length - 1)) {
        report(
          rel,
          source,
          match.index,
          'data-reshaping',
          '.map() that returns data rather than JSX is a mapper',
        );
      }
      continue;
    }
    if (RESHAPERS.includes(method)) {
      report(rel, source, match.index, 'data-reshaping', `.${method}() belongs in src/lib/`);
    }
  }

  /* S6. The browser is a side effect, and a side effect needs a hook to own its cleanup. */
  for (const token of BROWSER) {
    let at = source.indexOf(token);
    while (at !== -1) {
      report(rel, source, at, 'browser-api', `${token} belongs in a hook`);
      at = source.indexOf(token, at + 1);
    }
  }

  /* S7. Anything awaited in a component is a request the component is making itself. */
  for (const match of source.matchAll(/\bawait\b/g)) {
    report(rel, source, match.index, 'async-in-component', 'await belongs in a hook');
  }

  /* S10. A handler with a block body sequences behaviour — `close(); signOut.open();` — and a
     sequence belongs in the hook that owns both steps, exposed as one named action the JSX binds.
     `onClick={menu.close}` and `() => flag.on()` forward a single call and stay; a `{ … }` body
     is where a second statement goes, so the brace is the signal. */
  for (const match of source.matchAll(
    /(?:const (\w+) = |=\{)(?:async )?(?:\([^)]*\)|\w+) =>\s*\{/g,
  )) {
    report(
      rel,
      source,
      match.index,
      'handler-in-component',
      `${match[1] ?? 'inline handler'} sequences behaviour — expose one named action from the hook`,
    );
  }

  /* S8. A rule over more than one field is the kind that breaks silently and cannot be tested
     without rendering. Two string comparisons joined by a boolean operator is its signature. */
  for (const match of source.matchAll(
    /===\s*['"][^'"]+['"]\s*(?:&&|\|\|)[\s\S]{0,40}?===\s*['"]/g,
  )) {
    report(
      rel,
      source,
      match.index,
      'compound-domain-condition',
      'a rule over two fields belongs in src/lib/ or the hook',
    );
  }
}

/* S11. A domain value compared against a bare string. `status === 'published'` spells the member a
   second time, where a typo still type-checks against a widened value and a renamed member leaves
   every copy behind; `status === POST_STATUS.published` names the one constant the union is kept in
   step with (`LiteralMap`). "Domain" is read off the type, not the text — a value whose declared
   type is a string-literal union exported from `src/types/` — because the literal alone cannot tell
   `layout === 'grid'` (a prop) from a status.

   The declared type of the compared symbol is used rather than the type at the use site: after
   `if (t === 'h2') return`, TypeScript narrows `t` and the narrowed union has lost its alias, so
   every comparison after the first in a chain would slip through. */
const TYPES = join(ROOT, 'src/types') + sep;

/** The `src/types/` union a type comes from, looking through `| undefined` and similar. */
function domainUnion(type: ts.Type): string | undefined {
  const declaration = type.aliasSymbol?.declarations?.[0];
  if (type.aliasSymbol && declaration?.getSourceFile().fileName.startsWith(TYPES)) {
    return type.aliasSymbol.name;
  }
  if (!type.isUnion()) return undefined;
  for (const member of type.types) {
    const name = domainUnion(member);
    if (name) return name;
  }
  return undefined;
}

function declaredType(checker: ts.TypeChecker, node: ts.Expression): ts.Type {
  const symbol = checker.getSymbolAtLocation(node);
  return symbol?.valueDeclaration
    ? checker.getTypeOfSymbol(symbol)
    : checker.getTypeAtLocation(node);
}

const EQUALITY = new Set([
  ts.SyntaxKind.EqualsEqualsEqualsToken,
  ts.SyntaxKind.ExclamationEqualsEqualsToken,
  ts.SyntaxKind.EqualsEqualsToken,
  ts.SyntaxKind.ExclamationEqualsToken,
]);

if (safeIsDirectory(TYPES)) {
  const configPath = ts.findConfigFile(ROOT, ts.sys.fileExists, 'tsconfig.json');
  if (!configPath) throw new Error('soc: no tsconfig.json to type the components with');
  const config = ts.parseJsonConfigFileContent(
    ts.readConfigFile(configPath, ts.sys.readFile).config,
    ts.sys,
    ROOT,
  );
  const program = ts.createProgram(config.fileNames, config.options);
  const checker = program.getTypeChecker();

  for (const file of program.getSourceFiles()) {
    if (!file.fileName.startsWith(COMPONENTS + sep) || !file.fileName.endsWith('.tsx')) continue;
    const rel = relative(ROOT, file.fileName);
    const source = file.getFullText();

    const visit = (node: ts.Node): void => {
      if (ts.isBinaryExpression(node) && EQUALITY.has(node.operatorToken.kind)) {
        const literal = ts.isStringLiteral(node.right)
          ? node.right
          : ts.isStringLiteral(node.left)
            ? node.left
            : undefined;
        const other = literal === node.right ? node.left : node.right;
        const union = literal ? domainUnion(declaredType(checker, other)) : undefined;
        if (literal && union) {
          report(
            rel,
            source,
            node.getStart(file),
            'domain-literal-comparison',
            `'${literal.text}' is a ${union} — compare against its constant in src/lib/constants/`,
          );
        }
      }
      ts.forEachChild(node, visit);
    };
    visit(file);
  }
}

/* An exemption with no reason, or one that matches nothing, is an exemption nobody reviewed. */
for (const [at, entry] of EXEMPTIONS.entries()) {
  if (!entry.reason) {
    findings.push({
      rel: ALLOW_FILE,
      line: 0,
      check: entry.check,
      detail: `${entry.path} has no reason`,
    });
  } else if (!used.has(at)) {
    findings.push({
      rel: ALLOW_FILE,
      line: 0,
      check: entry.check,
      detail: `${entry.path} no longer matches anything — remove it`,
    });
  }
}

if (findings.length > 0) {
  const byCheck = new Map<string, number>();
  for (const finding of findings) byCheck.set(finding.check, (byCheck.get(finding.check) ?? 0) + 1);

  console.error(`\nSeparation of concerns: ${findings.length} problem(s)\n`);
  for (const finding of [...findings].sort((a, b) => a.rel.localeCompare(b.rel))) {
    console.error(`  ✗ ${finding.rel}:${finding.line} — ${finding.check} (${RULE[finding.check]})`);
    console.error(`      ${finding.detail}`);
  }
  console.error('\nBy category:');
  for (const [check, count] of [...byCheck].sort((a, b) => b[1] - a[1])) {
    console.error(`  ${String(count).padStart(4)}  ${check}`);
  }
  console.error('\nSee .claude/rules/web/separation-of-concerns.md\n');
  process.exit(1);
}

console.log(`Separation of concerns: ${componentFiles.length} component file(s) hold no logic`);
