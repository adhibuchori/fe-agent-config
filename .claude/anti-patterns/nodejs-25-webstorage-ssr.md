# Node.js 25 — Broken localStorage breaks Next.js SSR

**Applies to:** Any local Next.js dev/build on macOS with Node.js 25+
**Discovered:** 2026-05-21
**Status:** Permanent (workaround required)

## Symptom

SSR crashes with:

```
TypeError: localStorage.getItem is not a function
```

Often shows as `unhandledRejection` repeated multiple times. Triggered by `next-themes` (used by `nextra-theme-docs`, shadcn theme provider, etc.) or any library that touches `localStorage` during render.

Companion warning that confirms the diagnosis:

```
Warning: `--localstorage-file` was provided without a valid path
```

## Root Cause

Node.js 25 enables `--experimental-webstorage` by default. It injects a `localStorage` global, but the implementation is incomplete — methods like `.getItem` / `.setItem` are `undefined` when `--localstorage-file` isn't set to a valid path. The standard SSR guard fails too:

```js
if (typeof window === 'undefined') return; // ❌ Node.js 25 injects `window` global
const value = localStorage.getItem('theme'); // 💥 .getItem is undefined
```

## Fix

Disable the experimental flag via `NODE_OPTIONS` in `package.json` scripts:

```json
{
  "scripts": {
    "dev": "NODE_OPTIONS='--no-experimental-webstorage' next dev",
    "build": "NODE_OPTIONS='--no-experimental-webstorage' next build"
  }
}
```

CI is unaffected — GitHub Actions uses Node.js 20 LTS where this flag doesn't exist.

## When to revisit

When Node.js fixes the broken localStorage implementation, or when `next-themes` adds a stronger SSR guard (e.g., checking `typeof localStorage.getItem === 'function'`). Test by removing the `NODE_OPTIONS` prefix and running `next build` locally.
