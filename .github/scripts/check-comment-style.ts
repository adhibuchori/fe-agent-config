#!/usr/bin/env bun
/* Fleet comment standard: `//` is reserved for directives (ts-expect-error, oxlint-disable,
   eslint-disable, biome-ignore, v8 ignore, triple-slash references). Everything else must use
   a block comment instead.

   Scope covers every hand-written TypeScript file the repo tracks, not just src/. Limiting it
   to src/ left scripts/, .github/scripts/, and the root config files unchecked, which is how
   repos whose own gate was green still carried violations.

   The scan is a self-contained tokenizer rather than a call into the repo's `typescript`
   package. That dependency turned out to be unusable: TypeScript 7's native port ships only
   the compiler binary and exposes no JS API at all, so a scanner-based gate silently crashed
   in whichever repo upgraded first. Tokenizing here keeps the gate identical across every
   repo regardless of which TypeScript version it pins. */

import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const ALLOWLIST =
  /^\/\/\/?\s*(@ts-expect-error|@ts-ignore|oxlint-disable|eslint-disable|biome-ignore|v8 ignore|<reference\s)/;

/* Generated output and vendored agent bundles are not hand-written, so the standard does not
   apply to them and reformatting them would be undone on the next regeneration.
   `next-env.d.ts` is rewritten by every `next build` and says so in its own header, so a fix
   there survives exactly until the next CI run. */
const EXCLUDED = ['src/lib/api/generated/', '.agents/', '.claude/', '.agent/', 'node_modules/'];
const EXCLUDED_FILES = ['next-env.d.ts'];

/* A `/` starts a regex literal only where a value may begin. After an identifier, literal, or
   closing bracket it is division instead, and the difference decides whether the rest of the
   line is scanned or skipped. */
const VALUE_CANNOT_FOLLOW = /[\w$)\]]$/;
const KEYWORDS_BEFORE_REGEX =
  /\b(return|typeof|instanceof|in|of|new|delete|void|throw|case|do|else|yield|await)$/;

interface Violation {
  line: number;
  text: string;
}

function findViolations(source: string): Violation[] {
  const out: Violation[] = [];
  let line = 1;
  let i = 0;
  /* Text seen since the last token boundary, used only for the regex-vs-division decision. */
  let prev = '';
  /* Depth of nested `${ }` inside template literals, so the closing brace returns to template
     scanning rather than to ordinary code. */
  const templateStack: number[] = [];

  const n = source.length;
  while (i < n) {
    const c = source[i];
    const next = source[i + 1];

    if (c === '\n') {
      line++;
      i++;
      prev = '';
      continue;
    }

    if (c === '/' && next === '/') {
      const end = source.indexOf('\n', i);
      const text = source.slice(i, end === -1 ? n : end).trimEnd();
      if (!ALLOWLIST.test(text)) out.push({ line, text });
      i = end === -1 ? n : end;
      continue;
    }

    if (c === '/' && next === '*') {
      const end = source.indexOf('*/', i + 2);
      const stop = end === -1 ? n : end + 2;
      for (let k = i; k < stop; k++) if (source[k] === '\n') line++;
      i = stop;
      prev = ' ';
      continue;
    }

    if (c === '"' || c === "'") {
      i++;
      while (i < n && source[i] !== c) {
        if (source[i] === '\\') i++;
        else if (source[i] === '\n') line++;
        i++;
      }
      i++;
      prev = 'x';
      continue;
    }

    if (c === '`') {
      i++;
      while (i < n) {
        if (source[i] === '\\') {
          i += 2;
          continue;
        }
        if (source[i] === '\n') line++;
        if (source[i] === '`') {
          i++;
          break;
        }
        if (source[i] === '$' && source[i + 1] === '{') {
          templateStack.push(1);
          i += 2;
          break;
        }
        i++;
      }
      prev = 'x';
      continue;
    }

    if (c === '}' && templateStack.length > 0) {
      templateStack.pop();
      i++;
      /* Resume the template literal that the `${` interrupted. */
      while (i < n) {
        if (source[i] === '\\') {
          i += 2;
          continue;
        }
        if (source[i] === '\n') line++;
        if (source[i] === '`') {
          i++;
          break;
        }
        if (source[i] === '$' && source[i + 1] === '{') {
          templateStack.push(1);
          i += 2;
          break;
        }
        i++;
      }
      prev = 'x';
      continue;
    }

    if (c === '/') {
      const trimmed = prev.trimEnd();
      const isRegex =
        trimmed === '' || !VALUE_CANNOT_FOLLOW.test(trimmed) || KEYWORDS_BEFORE_REGEX.test(trimmed);
      if (isRegex) {
        i++;
        let inClass = false;
        while (i < n) {
          if (source[i] === '\\') {
            i += 2;
            continue;
          }
          if (source[i] === '[') inClass = true;
          else if (source[i] === ']') inClass = false;
          else if (source[i] === '/' && !inClass) {
            i++;
            break;
          } else if (source[i] === '\n') {
            line++;
            break;
          }
          i++;
        }
        prev = 'x';
        continue;
      }
    }

    prev += c;
    if (prev.length > 32) prev = prev.slice(-32);
    i++;
  }

  return out;
}

const files = execSync(`git ls-files '*.ts' '*.tsx' '*.mts' '*.cts'`, { encoding: 'utf8' })
  .split('\n')
  .filter(Boolean)
  .filter((file) => !EXCLUDED.some((prefix) => file.startsWith(prefix)))
  .filter((file) => !EXCLUDED_FILES.includes(file));

/* A shallow clone or misconfigured checkout can make `git ls-files` return nothing —
   fail loudly instead of reporting a silent, meaningless pass. */
if (files.length === 0) {
  console.error('No source files found via `git ls-files` — check the checkout configuration.');
  process.exit(1);
}

let violationCount = 0;
for (const file of files) {
  for (const violation of findViolations(readFileSync(file, 'utf8'))) {
    console.log(`${file}:${violation.line} — stray \`//\` comment: ${violation.text}`);
    violationCount++;
  }
}

if (violationCount > 0) {
  console.log(
    `\n${violationCount} stray \`//\` comment(s) across ${files.length} file(s). Use /** */ for symbol docs or /* */ for implementation notes.`,
  );
  process.exit(1);
}

console.log(`No stray \`//\` comments across ${files.length} file(s).`);
