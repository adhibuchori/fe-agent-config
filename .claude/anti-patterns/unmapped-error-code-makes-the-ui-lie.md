# An unmapped error code makes the UI lie about which layer failed

**Applies to:** Any frontend that turns a backend `problem+json` code into user-facing copy
(`src/lib/errors/problem-key.ts`, `.claude/rules/common/error-codes.md`)
**Status:** Permanent (a fallback only knows what it was told)

## Symptom

An action fails and the screen says the app "could not reach the service". Every backend is up,
healthy and answering in milliseconds. The message sends diagnosis to the network layer and keeps
it there for several rounds, while the real fault is a request the proxy rejected.

## Root cause

The key resolver tries the code, then the status, then falls back:

```ts
return status >= 500 ? 'server.internal' : 'unknown';
```

When the code map holds only a handful of entries while a boundary raises several codes at `400`
and an upstream client raises others at `503`, none of them is mapped: a rejected request reads as
`unknown`, and an unavailable upstream as "something broke on our side".

Producer and consumer are each correct alone. Nothing joins them, and the i18n check cannot see
it: the key exists and has copy, it is simply never reached.

The `unknown` copy tends to drift into naming a **cause** ("could not reach the service") because
it is the only place left to explain anything. A fallback that guesses at a cause is worse than one
that admits it has none: it is confidently wrong exactly when someone is debugging.

## Fix

1. Map the codes each boundary actually emits, enumerated from source (`grep -rhoE "'[A-Z_]+_[A-Z_]+'"`
   over the module that raises them, or the API's `openapi.json`), never from memory.
   `check:error-codes` then keeps the map and the API in step.
2. Keep the fallback **causeless**: "Nothing was changed. Try the same action again." states the
   two things that are always true.

Split keys by what the reader can **do**, not by which service broke:

| Key                       | Action          | Recoverable? |
| ------------------------- | --------------- | ------------ |
| `server.request_rejected` | reload the page | yes          |
| `server.unavailable`      | wait, retry     | no           |
| `server.internal`         | nothing         | no           |

A code that is opaque on purpose (a generic 500 from one boundary) stays unmapped and falls to the
5xx floor, because "reload" would be false advice.

## How to catch it

**An error message that names a cause nobody verified.** If copy says "reach", "connection" or
"timeout", ask which code produced it. When the answer is "the fallback", the message is a guess
wearing a diagnosis.

## Scope

Every code path from a backend error to copy. [bodiless-request-is-an-empty-stream.md](bodiless-request-is-an-empty-stream.md)
is the kind of transport bug such a message hides.
