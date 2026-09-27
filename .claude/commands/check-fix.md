---
description: Write the format, run every gate in scripts/check/gates.list and the build, and fix what fails until all pass.
---

<!-- Command: /check-fix -->
<!-- Source: _workflow-source/check-fix.md -->

# /check-fix — Quality Check & Fix

1. **Format + Lint**: `bun run fl`
   - Writes oxfmt's format, then runs oxlint. Fix each lint finding at its cause: never
     `// oxlint-disable` (AGENTS.md Rule 28).

2. **Every gate**: `bash scripts/check/gates.sh`
   - The list `.husky/pre-commit` runs (`scripts/check/gates.list`): type check, dead code, double
     assertions, folder shape, the coverage policy and the tests at 100% on the logic layer,
     translation parity and button casing, hook placement, re-exports, logic in components,
     Tailwind classes, error codes and catch blocks, the optional modules, the AI config and the
     mirrors. It prints each gate's exit code and the tail of every failure. Fix, re-run, repeat
     until every gate passes; `--only <text>` re-runs just the gates whose command contains it.
   - `bun run check:tailwind --fix` rewrites non-canonical classes; the rest name a defect you fix
     by hand.

3. **Build**: `bun run build`
   - Catches what the type check does not: route and bundler failures.

A changed `openapi.json` means `bun generate:api` before the gates. Tests run with `bun run test`
(Vitest); bare `bun test` is Bun's own runner and fails for the wrong reasons.

Output: PASS/FAIL per gate, with what was fixed and what remains.
