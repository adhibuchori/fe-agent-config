# A bodiless request arrives as an empty stream, not `null`

**Applies to:** Server-side code that branches on "did this request carry a body?": a route
handler, a proxy that forwards to the backend, a middleware that buffers or rewrites the body
**Status:** Permanent (Fetch API behaviour)

## Symptom

Every bodiless `POST` and every `DELETE` through the proxy answers `400`, while the client, the
backend and the whole unit suite are correct and green. The failure shows up as "this button does
nothing" on whichever feature happens to send no body, so the first rounds of diagnosis go into the
feature instead of the transport.

## Root cause

Two wrong answers in a row to the same question.

**First**, deciding from the method:

```ts
const hasBody = request.method !== 'GET' && request.method !== 'HEAD';
```

A bodiless `POST` is legal. A proxy that decides this way reads `''` and hands it to a parser that
expects JSON.

**Second**, deciding from the stream:

```ts
const hasBody = request.body !== null; // passes every test, fails every real request
```

| How the `Request` was built              | `request.body`     |
| ---------------------------------------- | ------------------ |
| `new Request(url, { method: 'POST' })`   | `null`             |
| `new Request(url, { method, body: '' })` | `<ReadableStream>` |
| arriving over real HTTP                  | `<ReadableStream>` |

`null` only happens for a `Request` constructed in-process, which is to say in a test. The guard
passes a test written the easy way and fails all real traffic.

## Fix

Measure the bytes. Read once, branch on length:

```ts
const raw = await request.text();
if (raw.length > 0) {
  /* parse, validate, forward with the body */
}
/* empty: forward bodiless */
```

## How to catch it

**A guard that passes every unit test and fails every real request.** When a fix turns the suite
green and the browser still fails, suspect a test that builds a shape the wire never sends.

Write the test against what actually arrives (`body: ''`, not an omitted `body`), then put the old
guard back and watch the new test fail. If the suite stays green with the old code, the test is not
guarding the thing that broke.

## Scope

Every copy of the same boundary. When two services or two proxies share this code by copy, fix
them in the same change and grep for the guard across all of them: nothing lints across repos.
[parity-guard-compares-a-proxy.md](parity-guard-compares-a-proxy.md) is the same family, a guard
measuring a stand-in for the thing that matters.
