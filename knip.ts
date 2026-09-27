import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import type { KnipConfig } from 'knip';

/* A `@documented` index.ts is a docs-generator marker that exports nothing (AGENTS.md §L), so
   nothing imports it by design. Only those are exempt — any other file nothing imports is a real
   finding. */
const documentedMarkers = existsSync('src')
  ? readdirSync('src', { recursive: true, encoding: 'utf8' })
      .filter((path) => basename(path) === 'index.ts')
      .map((path) => join('src', path))
      .filter((path) => {
        const source = readFileSync(path, 'utf8');
        return source.startsWith('/** @documented ') && /^export \{\};$/m.test(source);
      })
  : [];

const config: KnipConfig = {
  /* The gates run these from the shell (scripts/check/gates.list, quality-gate.sh), and vitest
     reaches a stub through a `resolve.alias` — neither is an import Knip can follow. A
     `page.dev.tsx` is a route only under `next dev` (next.config.ts), so the Next plugin does not
     list it. */
  entry: [
    'scripts/check/*.{ts,mjs}',
    'scripts/measure/*.ts',
    '.github/scripts/*.ts',
    'src/testing/stubs/*.ts',
    'src/app/**/page.dev.tsx',
  ],
  ignore: [...documentedMarkers, '.agents/**', '.claude/**'],
  ignoreExportsUsedInFile: false,
};

export default config;
