# `bun <name>` ≠ `bun run <name>` — build **and** test

**Applies to:** Any Bun project
**Status:** Permanent (intentional Bun CLI design)

## Symptom

**`build`:** `bun build` prints bundler output or bundler errors instead of running the project's
`build` script from `package.json`.

**`test`:** `bun test` reports dozens of failures that do not exist, while `bun run test` passes.
Most of them share one error:

```text
TypeError: vi.mocked is not a function
```

The `test` case is the more dangerous one. A wrong bundler call fails loudly; false test failures
look exactly like a regression, so someone "fixes" working code to chase them, or decides the suite
is flaky and stops trusting it.

## Root cause

`build` and `test` are both **native Bun subcommands**, and a native subcommand never looks at
`package.json`. `bun test` runs Bun's own test runner, which does not implement Vitest's API
(`vi.mocked`, `vi.stubEnv`, …), so every Vitest-specific call throws.

A script whose name is not a Bun subcommand (`bun fl`, `bun type-check`) does run from
`package.json`, which is what makes the two colliding names easy to miss.

## Fix

Run package scripts with `bun run <script>`:

```bash
bun run build          # ✅ package.json "build"
bun run test           # ✅ package.json "test" → vitest run
bun run test:coverage  # ✅ package.json "test:coverage"

bun build              # ❌ Bun's native bundler
bun test               # ❌ Bun's native test runner
```

Anywhere a doc or a command list says `bun build` or `bun test` as shorthand, treat it as a typo and
add `run`.

## How to catch it

Before believing a mass failure, check the command before the code: dozens of failures that all
share one error message point at the runner, not at the change.

## Scope

Every Bun project with a `build` or `test` script. Never revisit: this is how the Bun CLI is
designed.
