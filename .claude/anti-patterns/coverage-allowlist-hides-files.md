# A named-file coverage allowlist cannot report what is missing from it

**Applies to:** Any `vitest.config.ts` (or Jest / nyc config) whose `coverage.include` lists files
**Status:** Permanent (a property of allowlists, not a tool bug)

## Symptom

`test:coverage` reports 100% statements, branches, functions and lines and exits 0, while real
source files sit at 0%: whole authentication hooks and server helpers with no test at all.

## Root cause

```ts
coverage: {
  include: ['src/hooks/useSidebar.ts', 'src/lib/utils.ts' /* …a hand-kept list… */],
  thresholds: { statements: 100, branches: 100, functions: 100, lines: 100 },
}
```

The threshold is computed over the listed files. A file nobody added is not under-covered: it is
**outside the measured set**, so it cannot lower a percentage or trip a threshold. Every new file
starts invisible, and the number meant to catch that is the one the omission cannot reach.

The failure is silent in the worst direction: 100% is the most reassuring output the tool can
print, and it prints it precisely when the list is most out of date.

## Fix

Patterns, never file names. A directory glob measures whatever lands in it, so a new file starts
counted and a missing test fails the first run after it is written:

```ts
coverage: {
  include: ['src/hooks/**/*.ts', 'src/lib/**/*.ts', 'src/store/**/*.ts', 'src/i18n/**/*.ts', 'src/proxy.ts'],
  exclude: ['src/lib/api/generated/**'], // generated: not ours to test
  thresholds: { statements: 100, branches: 100, functions: 100, lines: 100 },
}
```

Two rules follow, both in `.claude/rules/typescript/coverage.md`:

- **Exclusions are named, inclusions are patterns.** Forgetting to exclude something makes the gate
  stricter; forgetting to include something makes it weaker.
- **Code that is dead on purpose gets `/* v8 ignore */` with a reason**, not a missing config row.
  The comment sits next to the code and is deleted with it; a missing row is invisible from the
  file it excuses.

## How to catch it

```bash
bun run test:coverage 2>&1 | tail -30         # note how many files the table lists
git ls-files 'src/hooks/**/*.ts' | wc -l      # against how many the tree holds
```

A report that lists fewer files than the tree holds is the whole symptom.
`scripts/check/coverage-policy.mjs` fails when a logic folder drops out of the include list, a
threshold falls below 100, or an exclusion carries no reason.

## Scope

Any coverage threshold over a hand-kept file list. Never revisit.
