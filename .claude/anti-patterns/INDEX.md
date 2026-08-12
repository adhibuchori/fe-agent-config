# Anti-Patterns Index

> Lazy-loaded knowledge base. Load only the file(s) matching your current task.
> Each file is self-contained — root cause + fix + scope.

## Loading Guide

| Trigger / Task                                                             | Load                                   |
| -------------------------------------------------------------------------- | -------------------------------------- |
| Local Next.js dev/build on macOS (Node.js 25+)                             | nodejs-25-webstorage-ssr.md            |
| Any `bun build` invocation                                                 | bun-build-vs-bun-run-build.md          |
| Editing agent rules or `scripts/sync-rules.sh`                             | agent-rules-frontmatter-silent-drop.md |
| Adding a code generator, or its output keeps going stale                   | oxfmt-rewrites-generated-files.md      |
| Auto-scroll paired with a loading/skeleton state, or scroll "does nothing" | smooth-scroll-races-layout-shift.md    |

## When to add a new entry

A new anti-pattern qualifies when:

- It cost real debugging time (>30 min)
- The root cause is non-obvious from reading code/docs
- Same trap is likely to recur (vendor bug, environment quirk, tooling gotcha)

If the bug gets fixed upstream, **delete the file** — don't leave stale entries.

## File naming convention

`<scope>-<short-description>.md` — kebab-case, descriptive enough to skip without opening.

Examples:

- `nodejs-25-webstorage-ssr.md`
- `bun-build-vs-bun-run-build.md`
