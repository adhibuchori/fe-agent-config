---
paths:
  - 'src/**'
  - 'tests/**'
  - 'scripts/**'
  - 'components/**'
  - 'lib/**'
---

# SHAPE — Folder Shape

A file's path should be guessable from what it does. Enforced by `scripts/check/folder-shape.mjs`
in pre-commit and the quality gate, which reports violations as SHAPE-1 to SHAPE-4. Where a stack
adds its own file-organization rule (a frontend's `web/file-organization.md`, for example), that
rule sits on top of this one.

## Shape

- **SHAPE-1.** A folder holds files or folders, never both. Once a folder has a subfolder, every
  file in it moves into a subfolder named for its domain (`lib/cache/`, `lib/mail/`,
  `core/settings/`). A folder with one domain file is fine; split a domain folder only when it has
  its own sub-domains, not to make the tree look even.
- **SHAPE-3.** Name a folder or a test for its subject, never for why it was written: `misc/`,
  `extra/`, `final-branches.test.ts` and `coverage-gaps/` say nothing about what is inside.

## Tests

- **SHAPE-2.** A test sits at the mirror of the source it is named after. Next.js:
  `src/lib/format/date.ts` → `src/testing/lib/format/date.test.ts`. Hono or another TypeScript
  API: the `__tests__/` folder beside the source. Python: `src/app/core/settings/config.py` →
  `tests/unit/core/settings/test_config.py`, under `unit/`, `routes/` or `integration/`.
- A second test of one source adds an aspect: `date.timezone.test.ts`. A test that spans several
  sources sits in the nearest folder that holds all of them.
- **SHAPE-4.** Mocks, fixtures, helpers and stubs live in
  `src/testing/{helpers,mocks,fixtures,stubs}/` or `tests/fixtures/`, never beside the tests. A
  co-located `__tests__/` may keep its own `helpers.ts` or `*-fixtures.ts`.
- A test moves in the same commit as its source. Count test files before and after: a test at a
  path the runner does not match stops running without failing.

## Exempt, and only these

- Route trees the framework shapes, in a Next.js repo: `src/app/**`, `app/**` and Nextra's
  `content/**`.
- Entrypoints at a fixed path: `src/{app,index,env,proxy,middleware,instrumentation}.ts`,
  `src/instrumentation-client.ts`, `src/app/{main,cli}.py`, and `src/testing/setup.ts`, with tests
  of those entrypoints at the root of the test tree.
- `__tests__/` does not count as a subfolder. `__init__.py`, `conftest.py` and `py.typed` do not
  count as files.
- Tool output and caches: `migrations/`, `generated/`, `*.generated.*`, `node_modules/`, `.next/`,
  `out/`, `dist/`, `coverage/` and the Python tool caches.

A `.gitkeep` is not exempt: delete it once the folder has content. Adding an exemption means
changing this file and `scripts/check/folder-shape.mjs` together, in one change.

## Moving files

- Convert relative imports to absolute in their own commit first; an escaping `../` breaks at build
  time, not at move time.
- `git mv`, then rewrite imports, then type-check. A path that a config names (`orval.config.ts`,
  `drizzle.config.ts`, `components.json`, `vitest.config.ts`, CI steps) moves in the same commit.
