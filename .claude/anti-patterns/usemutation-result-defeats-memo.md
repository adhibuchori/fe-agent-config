# The `useMutation` result object defeats a measured `memo()`

**Applies to:** Any handler built from a TanStack Query `useMutation` result and passed to a
component that is wrapped in `memo()` after a measurement (`AGENTS.md` Rule 24)
**Status:** Permanent (TanStack Query returns a new result object every render)

## Symptom

A list row is wrapped in `memo()` because the profiler showed it re-rendering, and the profiler
still shows every row re-rendering on each change. One click on one row commits the whole list.

## Root cause

`useMutation` returns `{ ...result, mutate, mutateAsync }`, a **new object every render**. A handler
that closes over that object (`() => saveMutation.mutate(v)`) is a new function every render, so
React Compiler memoises it against a dependency that always changes, and every `memo()` row
receives a new prop. `mutate` itself is stable: it is a callback keyed on the observer.

## Fix

Destructure the stable function and close over that alone:

```ts
const { mutate: saveItem, isPending } = useMutation({ ... });
return { isPending, handleToggle: (checked: boolean) => saveItem(checked) };
```

Read `isPending` and the rest into their own names the same way, rather than passing the result
object around.

## How to catch it

React Profiler: after the change, one action commits only the row whose data changed. Before
trusting a `memo()`, record once with it and once without; a wrapper that changes nothing in the
profile is speculative and goes (Rule 24).

## Scope

Every mutation whose handler reaches a memoised child. The same shape applies to any hook that
returns a fresh object holding stable functions.
