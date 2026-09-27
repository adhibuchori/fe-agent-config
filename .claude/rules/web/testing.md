---
paths:
  - 'src/testing/**'
  - '**/*.test.ts'
  - '**/*.test.tsx'
  - 'vitest.config.ts'
---

# Frontend Testing

Unit tests only, on Vitest in jsdom. What coverage must reach is `typescript/coverage.md`.

## Running

- `bun run test` and `bun run test:coverage`. Never bare `bun test`: that is Bun's own runner, which lacks `vi.mocked` and reports false failures.
- `bun run test` does not check coverage. The threshold lives in `vitest.config.ts` (100% on the logic layer: hooks, lib, store, i18n and the proxy) and only `test:coverage` enforces it, so run `bash scripts/check/gates.sh` before calling work done.
- Tests mirror the source tree under `src/testing/`: `src/lib/x.ts` → `src/testing/lib/x.test.ts`. A test moves in the same commit as its source; count test files before and after any move, because an orphaned test stops running without failing.

## Writing

- jsdom has no layout: assert class strings, elements and attributes, never pixels, and label any visual claim "jsdom only". Pixels are measured in a real browser (`bun run measure:skeletons` where the repo ships it).
- A test that calls a hook or proxy directly proves that function, not the framework around it. Exercise an auth hook through the auth library's real API or over HTTP, and a proxy through a real request.
- Prove a new or rewritten test rejects the defect it targets; a replacement for a flaky assertion that can never fail is worse than the flake.
- A guard that pins the old answer argues back when the fix lands: check whether it encodes a requirement or an assumption. Delete a test that moves no coverage and proves nothing.
- Uncovered branches in a new hook are usually dead code (`?? 'base'` on a typed default). Delete them before writing a test for an impossible state.

## File limits

- Test files obey `max-lines` 150, which skips blank lines and comments: measure with `bun run fl 2>&1 | grep max-lines`, never `wc -l`.
- Split a long suite by concern (`useX.test`, `useX.register.test`). Rebuild each file from a full read rather than cutting at a `describe`, and check whether the target file already exists first.
- After a split, seed shared mocks in `beforeEach`, not `afterEach`: the first test of each new file otherwise runs against unimplemented mocks.
- `unicorn/consistent-function-scoping` rejects inline closures such as a release gate: move them to module scope.
