# A spec change breaks the consumer you are not looking at

**Applies to:** Any backend route added, removed or re-pathed, when one or more frontends keep a
copy of the backend's `openapi.json` and generate code from it
**Status:** Permanent (each consumer owns what it derives from its copy)

## Symptom

You add a backend endpoint, export the spec, copy `openapi.json` where the backend's check tells
you to, and every gate in the repos you are working in passes. A consumer you never opened is now
red, and stays red until someone runs its CI:

```text
✗ generated client is stale: openapi.json has <n> operations, src/lib/api/generated has <m>
```

Or it stays green and calls a path the backend no longer serves.

## Root cause

Two different things are derived from one spec, and only the first is checked across repos.

A backend check can compare each spec copy with its source, so it notices a stale **copy**. But each
consumer also holds what it **generated** from that copy (here `src/lib/api/generated/`, written by
`bun generate:api`), and nothing on the backend side reads that. Copying the spec satisfies the
backend's gate while leaving every generated client behind it.

Consumers are rarely symmetric: one runs a full client generator, another only a route registry, a
third has no generator and reports "not present, skipped", which reads like reassurance and is easy
to mistake for "nothing to do here".

## Fix

Treat the copy and the regeneration as one operation, in every consumer:

```bash
# backend
<export the spec>
cp openapi.json <consumer>/openapi.json          # once per consumer

# each consumer
bun generate:api && bun run type-check           # regenerate, then let tsc find the call sites
```

Commit the spec copy and the regenerated output together, in each consumer. `src/lib/api/generated/`
is never edited by hand (`AGENTS.md` Rule 29).

## How to catch it

Run the generator and the type check **in each consuming repo**, not only in the one that owns the
spec. The backend's green result means the copies match; it says nothing about what was generated
from them.

## Scope

Keep the list of consumers where the backend's spec export lives, and read it rather than assuming
a count: a consumer added later fails the same silent way.
