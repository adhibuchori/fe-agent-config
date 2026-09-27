# `void promise.finally(fn)` does not swallow the rejection

**Applies to:** Any JavaScript or TypeScript that calls `.finally()` on a promise that can reject
**Status:** Permanent (specified behaviour of `Promise.prototype.finally`)

## Symptom

A fire-and-forget call written with `void` still produces an unhandled rejection whenever the
promise fails: a sign-out while the API is down logs an unhandled rejection and fires
`window.onunhandledrejection`, on a path whose whole point is that the outcome does not matter.

```ts
/* Broken. */
void signOut().finally(() => {
  router.replace('/login');
});
```

## Root cause

`.finally(fn)` runs `fn` and then **re-throws**: it returns a promise that settles the same way the
original did, on purpose, so `finally` can be inserted anywhere in a chain without changing its
result. It is not a `catch`.

`void` only discards the reference. Nothing in the chain handles the rejection, so the runtime
reports it.

## Fix

Handle the rejection explicitly, so the decision to ignore it is visible:

```ts
void signOut()
  .catch(() => undefined) /* error ignored: we leave the page whatever the answer */
  .finally(() => {
    router.replace('/login');
  });
```

The `.catch()` is the code saying "swallowed on purpose", which a reader cannot infer from `void`.
Order matters: `.catch()` before `.finally()` means the chain is already settled by the time
`finally` runs. The comment follows the bare-catch rule in `.claude/rules/common/error-codes.md`.

## How to catch it

```bash
grep -rnE 'void .*\.(then|finally)\(' src | grep -v '\.catch('
```

## Scope

Every fire-and-forget chain. Never revisit: this is `Promise.prototype.finally` as specified.
