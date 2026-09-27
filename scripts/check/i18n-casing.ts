#!/usr/bin/env bun
/**
 * Title Case check for the words a button shows, in every locale
 * (.claude/rules/web/ui-conventions.md § Copy). The texts are found in the source, not guessed from
 * key names: every `t(...)` rendered as the text of a button-like element, or of a span directly
 * inside one, read with the namespace its `useTranslations` or `getTranslations` call gave `t`.
 * A template key such as t(`status.${s}`) checks every key it can match.
 */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import ts from 'typescript';

const ROOT = join(import.meta.dirname, '../..');
const MESSAGES_DIR = join(ROOT, 'src/messages');
const BUTTON = /^(button|([A-Z]\w*)?(Btn|Button))$/;
/* Articles, conjunctions and prepositions of four letters or fewer stay lowercase inside a label.
   Indonesian keeps every preposition and conjunction lowercase, whatever its length (PUEBI). Add
   the small words of any other locale you ship. */
const SMALL = new Set([
  'a',
  'an',
  'the',
  'and',
  'but',
  'or',
  'nor',
  'for',
  'so',
  'yet',
  'as',
  'at',
  'by',
  'in',
  'of',
  'on',
  'to',
  'up',
  'via',
  'with',
  'from',
  'into',
  'onto',
  'over',
  'per',
  'than',
  'vs',
  'di',
  'ke',
  'dari',
  'dan',
  'atau',
  'yang',
  'pada',
  'oleh',
  'agar',
  'bagi',
  'tapi',
  'jika',
  'si',
  'sang',
  'pun',
  'dengan',
  'dalam',
  'untuk',
  'kepada',
  'tentang',
  'terhadap',
  'sebagai',
  'secara',
  'hingga',
  'sejak',
  'antara',
  'serta',
  'bahwa',
  'karena',
  'tetapi',
  'maupun',
]);
/* Units after a number are abbreviations, not words: "12 min", "3 mnt". */
const UNITS = new Set(['min', 'mnt', 'h', 'j', 'm', 's', 'd', 'ms', 'px', 'kb', 'mb']);

function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

type Messages = Map<string, string>;

function flatten(node: unknown, prefix: string, out: Messages): Messages {
  if (typeof node === 'string') out.set(prefix, node);
  else if (node && typeof node === 'object') {
    for (const [key, value] of Object.entries(node)) {
      flatten(value, prefix ? `${prefix}.${key}` : key, out);
    }
  }
  return out;
}

const load = (file: string): Messages =>
  flatten(JSON.parse(readFileSync(join(MESSAGES_DIR, file), 'utf8')), '', new Map());

function sources(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory())
      return ['testing', 'generated'].includes(entry.name) ? [] : sources(path);
    return entry.name.endsWith('.tsx') ? [path] : [];
  });
}

/** The index of the brace that closes the one at `open`. */
function closing(text: string, open: number): number {
  let depth = 0;
  for (let i = open; i < text.length; i++) {
    if (text[i] === '{') depth++;
    if (text[i] === '}' && --depth === 0) return i;
  }
  return text.length;
}

/** The literal runs of an ICU message: arguments removed, plural and select branches kept. */
function segments(message: string): string[] {
  const out: string[] = [];
  let run = '';
  let i = 0;
  while (i < message.length) {
    if (message[i] !== '{') {
      run += message[i++];
      continue;
    }
    const end = closing(message, i);
    const branches = /^\s*\w+\s*,\s*(?:plural|select|selectordinal)\s*,([\s\S]*)$/.exec(
      message.slice(i + 1, end),
    )?.[1];
    if (branches === undefined) {
      /* A value stands where a word would, so "Try Again in {time}" keeps "in" inside the label. */
      run += ' Value ';
    } else {
      out.push(run);
      run = '';
      for (
        let j = branches.indexOf('{');
        j >= 0;
        j = branches.indexOf('{', closing(branches, j) + 1)
      ) {
        out.push(...segments(branches.slice(j + 1, closing(branches, j))));
      }
    }
    i = end + 1;
  }
  return [...out, run];
}

function titleCase(message: string): boolean {
  return segments(message.replace(/<\/?\w+>/g, ' ')).every((segment) => {
    const words = segment.match(/\p{L}[\p{L}\p{M}'’.-]*/gu) ?? [];
    return words.every((word, i) => {
      if (/^\p{Lu}/u.test(word) || /\p{Lu}/u.test(word.slice(1)) || UNITS.has(word)) return true;
      return SMALL.has(word) && i > 0 && i < words.length - 1;
    });
  });
}

/** Namespaces bound by `const t = useTranslations('ns')`, keyed by the function that holds them. */
function translators(file: ts.SourceFile): Map<ts.Node, Map<string, string>> {
  const scopes = new Map<ts.Node, Map<string, string>>();
  const visit = (node: ts.Node): void => {
    if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.initializer) {
      const init = ts.isAwaitExpression(node.initializer)
        ? node.initializer.expression
        : node.initializer;
      if (
        ts.isCallExpression(init) &&
        /^(use|get)Translations$/.test(init.expression.getText(file))
      ) {
        const [arg] = init.arguments;
        const ns = arg && ts.isStringLiteral(arg) ? arg.text : '';
        let scope: ts.Node = node;
        while (scope.parent && !ts.isFunctionLike(scope)) scope = scope.parent;
        if (!scopes.has(scope)) scopes.set(scope, new Map());
        scopes.get(scope)?.set(node.name.text, ns);
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(file);
  return scopes;
}

function namespaceOf(call: ts.Node, name: string, scopes: Map<ts.Node, Map<string, string>>) {
  for (let node: ts.Node | undefined = call; node; node = node.parent) {
    const ns = scopes.get(node)?.get(name);
    if (ns !== undefined) return ns;
  }
  return undefined;
}

/** The keys a `t(...)` call can name: one for a literal, every match for a template. */
function keysOf(arg: ts.Expression, ns: string, messages: Messages): string[] {
  const prefix = ns ? `${ns}.` : '';
  if (ts.isStringLiteral(arg) || ts.isNoSubstitutionTemplateLiteral(arg))
    return [prefix + arg.text];
  if (!ts.isTemplateExpression(arg)) return [];
  const pattern = [arg.head.text, ...arg.templateSpans.map((span) => span.literal.text)]
    .map(escapeRegExp)
    .join('[^.]+');
  const match = new RegExp(`^${escapeRegExp(prefix)}${pattern}$`);
  return [...messages.keys()].filter((key) => match.test(key));
}

const localeFiles = existsSync(MESSAGES_DIR)
  ? readdirSync(MESSAGES_DIR).filter((name) => name.endsWith('.json'))
  : [];
if (localeFiles.length === 0 || !existsSync(join(ROOT, 'src'))) {
  console.log('No src/messages/*.json in this repo - no button text to check');
  process.exit(0);
}
const locales = localeFiles.map((name) => [name.replace(/\.json$/, ''), load(name)] as const);
/* Keys are discovered in one locale; i18n.ts already fails a key missing from another. */
const reference = locales.find(([locale]) => locale === 'en')?.[1] ?? locales[0]?.[1] ?? new Map();
const failures: string[] = [];
let scanned = 0;

for (const path of sources(join(ROOT, 'src'))) {
  scanned++;
  const file = ts.createSourceFile(
    path,
    readFileSync(path, 'utf8'),
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TSX,
  );
  const scopes = translators(file);
  const check = (expression: ts.Node): void => {
    if (ts.isJsxElement(expression) || ts.isJsxSelfClosingElement(expression)) return;
    if (ts.isCallExpression(expression) && expression.arguments[0]) {
      const callee = expression.expression;
      const name = ts.isIdentifier(callee)
        ? callee.text
        : ts.isPropertyAccessExpression(callee)
          ? callee.expression.getText(file)
          : '';
      const ns = namespaceOf(expression, name, scopes);
      if (ns !== undefined) {
        for (const key of keysOf(expression.arguments[0], ns, reference)) {
          for (const [locale, messages] of locales) {
            const value = messages.get(key);
            if (value !== undefined && !titleCase(value)) {
              const { line } = file.getLineAndCharacterOfPosition(expression.getStart(file));
              failures.push(`${relative(ROOT, path)}:${line + 1}  ${key} (${locale}): "${value}"`);
            }
          }
        }
        return;
      }
    }
    ts.forEachChild(expression, check);
  };
  const children = (element: ts.JsxElement, nested: boolean): void => {
    for (const child of element.children) {
      if (ts.isJsxExpression(child) && child.expression) check(child.expression);
      if (
        !nested &&
        ts.isJsxElement(child) &&
        child.openingElement.tagName.getText(file) === 'span'
      )
        children(child, true);
    }
  };
  const visit = (node: ts.Node): void => {
    if (ts.isJsxElement(node) && BUTTON.test(node.openingElement.tagName.getText(file))) {
      children(node, false);
    }
    ts.forEachChild(node, visit);
  };
  visit(file);
}

const unique = [...new Set(failures)];
if (unique.length > 0) {
  console.error(`✗ ${unique.length} button text(s) not in Title Case (ui-conventions.md § Copy):`);
  for (const failure of unique) console.error(`  ${failure}`);
  process.exit(1);
}
console.log(
  `✓ Every button text is Title Case in ${locales.map(([l]) => l).join(', ')} (${scanned} files read)`,
);
