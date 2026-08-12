# oxfmt rewrites generated files unless they are ignored

**Applies to:** Any file written by a generator in this repo
**Discovered:** 2026-08-07
**Status:** Permanent (oxfmt works as configured)

## Symptom

A generator runs clean, its `--check` mode passes, then `bun fl` runs and the same `--check`
reports every generated file as stale. Re-running the generator fixes it until the next `bun fl`.
An endless loop with no error from either tool.

## Root cause

`bun fl` runs `oxfmt --write` across the repo, including Markdown and its YAML frontmatter. With
`"singleQuote": true` in `.oxfmtrc.json`, it rewrites `"` to `'`:

```diff
- globs: "**/*.tsx, next.config.ts"
+ globs: '**/*.tsx, next.config.ts'
```

Byte-identical comparison is how a generator detects staleness, so a single quote flip is enough
to make every file look out of date.

## Fix

Add the generated directory to `ignorePatterns` in `.oxfmtrc.json`, alongside the entry that is
already there for the same reason:

```json
"ignorePatterns": [
  "node_modules/",
  ".next/",
  "src/lib/api/generated/",
  ".agents/rules/"
]
```

Do **not** instead make the generator emit whatever oxfmt happens to prefer. That inverts
ownership — the formatter's config becomes the spec for the output format, and any config change
silently breaks the generator.

## How to catch it

Test the interaction explicitly, in this order. Checking only the first step passes and proves
nothing:

```bash
bun sync:rules && bun sync:rules --check   # clean
bun fl
bun sync:rules --check                     # must still be clean
```

## Scope

Any generator added later. `src/lib/api/generated/` (Orval) and `.agents/rules/`
(`scripts/sync-rules.sh`) are the current cases.
