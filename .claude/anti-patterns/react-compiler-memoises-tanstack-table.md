# React Compiler reuses a TanStack Table subtree forever

**Applies to:** Any component rendered from a TanStack Table instance while React Compiler is on,
and any prop that is a mutable object with a stable identity
**Status:** Permanent (documented consequence of memoising on identity)

## Symptom

Clicking a page number or a sort header does nothing. The button takes focus, the rows do not move,
no error appears, and the whole unit suite passes. It reads as a dead control, so the first hours go
to the click handler, the state and the data, all of which are fine.

## Root cause

A TanStack Table instance is a **mutable object with a stable identity**. `table.setPageIndex(2)`
mutates it in place; `table` is the same object before and after.

React Compiler memoises on identity. It sees an unchanged `table` prop and reuses the entire
subtree, so the render that should paint page 2 paints nothing new.

This is not a compiler bug. It is the documented consequence of handing the compiler a value that
does not change identity when its contents change, and TanStack documents the opt-out for it.

## Fix

`'use no memo'` as the first statement in each component body that reads the table:

```tsx
export function DataTableBody<TData>({ table }: Props<TData>) {
  'use no memo';
  // ...
}
```

It is the compiler's documented per-component opt-out, not a lint silencer, and it does not
conflict with `AGENTS.md` Rules 23-24, which forbid adding memoisation, not opting out of it.

## Why no unit test can catch the bug itself

If the Vitest config renders with the plain React plugin and **no compiler**, the suite runs code
the browser never runs, and a full green suite says nothing about this defect.

The guard that survives is the presence of the directive: a test that lists the table consumers and
also walks `src/components` for any `.tsx` calling `table.get…` without the directive, so a new
consumer cannot be added quietly. Remove a directive only after a rendered browser check shows paging
and sorting still work.

## How to catch it

A control in a table updates state correctly (logging shows it, the focus ring moves) and the DOM
does not change. Everything passes. Nothing is logged.

## Scope

Any mutable, stable-identity object passed as a prop under React Compiler: a class instance, an
imperative handle, a third-party controller. If its identity cannot change when its contents do,
the compiler may skip the render, and no test run without the compiler will say so.
