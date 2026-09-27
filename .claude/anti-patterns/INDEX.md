# Anti-Patterns Index

> Lazy-loaded knowledge base. Load only the file(s) matching your current task.
> Each file is self-contained: symptom, root cause, fix, how to catch it, scope.

## Loading Guide

### Tooling and git

| Trigger / Task                                                                     | Load                                   |
| ---------------------------------------------------------------------------------- | -------------------------------------- |
| Any `bun build` or `bun test` invocation, or a mass test failure sharing one error | bun-build-vs-bun-run-build.md          |
| Local Next.js dev/build on macOS (Node.js 25+)                                     | nodejs-25-webstorage-ssr.md            |
| Editing agent rules or `scripts/sync/rules.sh`                                     | agent-rules-frontmatter-silent-drop.md |
| Adding a code generator, or its output keeps going stale                           | oxfmt-rewrites-generated-files.md      |
| Checking file length against the 150-line rule                                     | max-lines-skips-blanks-and-comments.md |
| Applying any patch, or building one with `git diff --no-index`                     | git-apply-check-passes-then-deletes.md |
| Committing while another agent session shares the checkout                         | shared-git-index-across-sessions.md    |

### Tests and coverage

| Trigger / Task                                                | Load                                          |
| ------------------------------------------------------------- | --------------------------------------------- |
| Editing `vitest.config.ts` coverage settings                  | coverage-allowlist-hides-files.md             |
| A 100% branch threshold failing with a negative branch count  | v8-negative-branch-counts.md                  |
| A 100% branch threshold failing on a guard nothing can reach  | unreachable-guard-vs-100-percent-branches.md  |
| A mock records a call with no arguments that nothing makes    | vitest-hook-return-value-is-a-teardown.md     |
| A styling-only change breaks tests through `getComputedStyle` | jsdom-min-in-inline-style-breaks-getbyrole.md |
| Writing a test that two renderers agree on a layout           | parity-guard-compares-a-proxy.md              |

### React and data

| Trigger / Task                                                                 | Load                                      |
| ------------------------------------------------------------------------------ | ----------------------------------------- |
| A `memo()` row still re-renders when its handlers come from `useMutation`      | usemutation-result-defeats-memo.md        |
| Rendering from a TanStack Table instance, or a table control that does nothing | react-compiler-memoises-tanstack-table.md |
| Fire-and-forget promises (`void x.finally(...)`)                               | promise-finally-rethrows.md               |
| A screen reading a live session that also hosts a dialog                       | live-session-flip-skips-flow-steps.md     |

### Styling and layout

| Trigger / Task                                                             | Load                                                |
| -------------------------------------------------------------------------- | --------------------------------------------------- |
| A Tailwind utility with no effect against a hand-written rule              | unlayered-css-beats-tailwind-layers.md              |
| A colour utility that renders nothing, or a class copied from elsewhere    | tailwind-raw-var-without-theme-mirror.md            |
| Setting a width or height cap on a native `<dialog>`                       | dialog-inline-maxwidth-drops-ua-gutter.md           |
| A `position: fixed` menu, popover or tooltip that lands offset             | fixed-popover-in-contained-ancestor-lands-offset.md |
| Auto-scroll paired with a loading/skeleton state, or scroll "does nothing" | smooth-scroll-races-layout-shift.md                 |
| Building a skeleton, a bar overflows, or the page still jumps on load      | skeleton-height-drifts-from-real-row.md             |
| Adding a route `loading.tsx` to a signed-in app                            | nextjs-page-level-shell-loading-flashes-chrome.md   |

### i18n

| Trigger / Task                                            | Load                                  |
| --------------------------------------------------------- | ------------------------------------- |
| Formatting a number, date, or currency for display        | tolocalestring-ignores-app-locale.md  |
| Deleting a component that uses a template translation key | i18n-template-key-blinds-namespace.md |

### API, errors and deploys

| Trigger / Task                                                  | Load                                               |
| --------------------------------------------------------------- | -------------------------------------------------- |
| Branching on whether a request carried a body                   | bodiless-request-is-an-empty-stream.md             |
| Error copy that names a cause, or a code with no mapping        | unmapped-error-code-makes-the-ui-lie.md            |
| After any `openapi.json` change in the backend                  | openapi-change-needs-every-consumer-regenerated.md |
| Changing environment variables on a self-hosted deploy platform | deploy-platform-env-is-encrypted-at-rest.md        |

## When to add a new entry

A new anti-pattern qualifies when:

- It cost real debugging time (>30 min)
- The root cause is non-obvious from reading code/docs
- Same trap is likely to recur (vendor bug, environment quirk, tooling gotcha)

Write it with the shape the others use: `**Applies to:**` and `**Status:**` lines, then Symptom,
Root cause, Fix, How to catch it and Scope. Use neutral names in examples, and state the lesson
rather than the date or the story it came from. Add its row here in the same change: a file with
no row is never loaded, and a row with no file sends the reader nowhere.

If the bug gets fixed upstream, **delete the file** — don't leave stale entries.

## File naming convention

`<scope>-<short-description>.md` — kebab-case, descriptive enough to skip without opening.

Examples:

- `nodejs-25-webstorage-ssr.md`
- `bun-build-vs-bun-run-build.md`
