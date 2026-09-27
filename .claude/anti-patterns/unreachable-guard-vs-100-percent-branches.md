# A guard nothing can reach, against a 100% branch threshold

**Applies to:** A repo with `noUncheckedIndexedAccess` in `tsconfig.json` and a 100% branch
threshold in `vitest.config.ts` (`.claude/rules/typescript/coverage.md`)
**Status:** Permanent (a collision between two settings, not a bug in either)

## Symptom

`test:coverage` reports every statement, function and line at 100% and stops one branch short:

```text
Statements   : 100% ( <n>/<n> )
Branches     : 99.9%  ( <m-1>/<m> )
ERROR: Coverage for branches (99.9%) does not meet global threshold (100%)
```

The uncovered branch has one shape: an `undefined` check right after an array index, or after a
call whose return type is wider than what it can produce.

```ts
const key = keys[target];
if (key === undefined) return; // ← never taken, by any input
```

The counts are ordinary non-negative numbers. That separates this from
[v8-negative-branch-counts.md](v8-negative-branch-counts.md), where v8 miscounts a branch that does
run; this is a branch that genuinely never runs.

## Root cause

`noUncheckedIndexedAccess` types `keys[target]` as `T | undefined` whatever the surrounding code
knows. When the index comes from a helper that only ever returns a valid one (a keyboard handler's
`nextIndex()` that returns `null` or an index inside the array), the guard is demanded by the type
checker and reachable by nothing.

The same shape appears without an index whenever a declared return type is wider than the values a
function can produce. A `parseBody<T>(): Promise<T>` fed by `JSON.parse` makes `result ===
undefined` look prudent, but `JSON.parse` never yields `undefined`: it returns a value or throws.

## Fix

Remove the possibility. Do not test it, and do not annotate it.

For an index, iterate instead: `entries()` yields `T`, not `T | undefined`, so the guard has nothing
to guard:

```ts
for (const [index, key] of keys.entries()) {
  if (index !== target) continue;
  onChange?.(key);
  return;
}
```

For a too-wide return type, state the guarantee in a comment where the call is and let the value
through:

```ts
/* parseBody either returns a value JSON.parse produced or throws; JSON.parse never yields undefined. */
return rebuild(response, JSON.stringify(parsed));
```

## A second shape: a guard the dependency array already rules out

```ts
useEffect(() => {
  if (!required || !token) return;
  if (lastTokenRef.current === token) return; // ← never taken
  lastTokenRef.current = token;
  void retry();
}, [required, token]);
```

React re-runs an effect only when a dependency **changed**, so it cannot see the same `token` twice
in a row. Strict Mode does not reach it either: it double-invokes an effect on mount, not on each
later change, and at mount the first guard returns before the second is evaluated. A test wrapped in
`<StrictMode>` to cover the branch moves the coverage numbers by zero. Treat that null result as the
proof, not as a test to fix.

## Deleting it versus annotating it

- **Delete it** when nothing but the type checker ever wanted it.
- **Annotate it** (`/* v8 ignore next -- <reason> */`) only when it is load-bearing against a
  specific past bug, and name that bug in the comment, next to the test that documents the shape.
  The test is whether deleting the guard loses a real defence or only a line.

## What not to do

- **Do not lower the threshold.** It is the only thing that made the dead code visible.
- **Do not write a test that fabricates the impossible state.** A sparse array or a cast through
  `unknown` turns the gate green with a test that documents a state the program cannot be in.
- **Do not reach for `/* v8 ignore */` first.** It is for code that cannot run and cannot be
  restructured (a flag-gated stub, a platform branch), not for a branch that exists only because
  of how a value was fetched.

## Scope

Caught only by `test:coverage`, which `bun run test` does not run
(`.claude/rules/web/testing.md` § Running).
