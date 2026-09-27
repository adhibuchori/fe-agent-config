# Code Review Checklist

On-demand reference: CLAUDE.md lists it under **On-demand References**, and nothing imports it.
Where the repo has an `AGENTS.md`, a reviewer subagent checks its numbered rules mechanically; this
is the human checklist around it. `/review` reads it, and `/ship` fixes what it finds down to
MEDIUM.

The base below applies to every stack; skip a section the change cannot touch (a docs site runs no
queries). Each stack adds its own checks in the marked section at the end, citing its `AGENTS.md`
rules by number there, where it has them, rather than here.

## When to review

- After writing or modifying code
- Before any commit to a shared branch
- When the diff touches authentication, authorization, user data, the env schema, or anything that
  reads a secret
- When a query, schema or migration changes
- Before merging a pull request

**Before requesting review:** CI is green, conflicts are resolved, and the branch is up to date
with its target.

## Machine first

Run CLAUDE.md § Quality Gates before reading a line. The gates already fail on formatting, lint,
types, dead code, coverage, secrets and folder shape, so flagging those by hand is noise. Spend the
review on what no gate can see: behaviour, contracts, data access, and whether the change is
testable and honest about its failures.

## Checklist

**Boundaries and contract**

- [ ] Each layer does its own job: entry points (handlers, pages, CLI commands) stay thin glue, and
      logic lives where a unit test can reach it without a live service
- [ ] Cross-module access goes through the module's public entry, never into its internals
- [ ] Errors carry a code from the registry and are mapped in one place; no response leaks an ID, a
      path, a stack trace or an upstream provider's message
- [ ] Every status a route can return is declared, and every code a client can receive is mapped
- [ ] Every new route that changes state declares its auth guard explicitly

**Data and performance**

- [ ] Every list read is bounded and paginated; no deep `OFFSET` paging on a growing table
- [ ] Columns are selected explicitly on wide tables
- [ ] No query or remote call inside a loop, directly or through a helper
- [ ] Every newly filtered, sorted or joined column is indexed in the same change; foreign keys
      always
- [ ] Transactions hold only database work: no HTTP, no cache, no queue publish inside one
- [ ] Writes are batched; an upsert is a real upsert, not select-then-insert
- [ ] A new cache entry has a TTL and an invalidation path in the same change

**Tests**

- [ ] New logic ships with tests that meet the coverage rule (`.claude/rules/*/coverage.md`)
- [ ] A new guard's test was proven by mutating the guarded line and watching it fail
- [ ] No test replaces a module that the shared doubles own

**General**

- [ ] Readable and well named; files within the max-lines limit; nesting no deeper than 4 levels
- [ ] No lint-disable comments, no explicit `any`, no double assertion
- [ ] Every ignored error says why, in the code
- [ ] Docs and comments that describe the changed behaviour were updated with it

## Security review triggers

**Stop and read carefully when the diff touches:** authentication or authorization, user input
handling, raw SQL or template interpolation, a redirect, a shell command, a file path built from
input, an outbound request to a URL a user controls, anything that reads a secret, or the env
schema.

## Severity levels

| Level    | Meaning                                  | Action                             |
| -------- | ---------------------------------------- | ---------------------------------- |
| CRITICAL | Security vulnerability or data loss risk | **BLOCK** — must fix before merge  |
| HIGH     | Bug or significant quality issue         | **WARN** — should fix before merge |
| MEDIUM   | Maintainability concern                  | **INFO** — fix now; `/ship` does   |
| LOW      | Style or minor suggestion                | **NOTE** — optional                |

## Common issues to catch

**Security**

- Hard-coded credentials; environment read outside the one env module
- SQL injection: interpolation into a raw query outside the data-access layer
- Error responses leaking internals
- A new endpoint outside the rate limit or request budget the rest of the API sits behind
- CORS without an origin allowlist
- Unescaped user input rendered as HTML; path traversal; server-side requests to user-supplied URLs

**Correctness**

- An async call that is never awaited: it type-checks and silently discards its result
- A cache key missing an input that changes the answer
- A code-side fallback that turns a missing env key into a quiet wrong address instead of a crash
- A bare catch that swallows the failure; a blocking call on an async path

**Performance**

- N+1 access patterns
- Unbounded reads
- A cache added where an index was missing
- Heavy work repeated on every render or request that could be computed once

## Approval criteria

- **Approve** — no CRITICAL or HIGH issues
- **Warning** — only HIGH issues (merge with caution)
- **Block** — CRITICAL issues found

## Stack checks

<stack-block name="review-checks">

**Next.js frontend** (numbered rules are `AGENTS.md`'s)

- [ ] A component renders and holds no logic: state, effects, timers, browser APIs and derivation
      sit in a named hook or in `src/lib/` (Rules 6 and 32, `.claude/rules/web/separation-of-concerns.md`)
- [ ] Hooks and components live in the folder of the feature they serve (Rules 7 and 30)
- [ ] Components reach data only through service hooks in `src/hooks/api/`, never through the
      generated client, and never through a service that sits behind the backend (Rules 13 and 14)
- [ ] A new query has its key in the key factory and starts from what the URL already names, not
      from another request's answer (Rule 15, `.claude/rules/web/data-fetching.md`)
- [ ] Every user-facing string goes through next-intl, and every locale file carries the key
      (Rules 19 and 21)
- [ ] Classes are canonical Tailwind, no class interpolates a value, and nothing sets the same
      property in `className` and `style` (Rules 11, 12 and 33)
- [ ] No `useMemo`, `useCallback` or `memo()` without a measured reason (Rules 23 and 24)
- [ ] No re-export, and `src/lib/api/generated/` is untouched: a spec change was regenerated
      (Rules 29 and 34)
- [ ] Every error code the app can receive is mapped, and a mutation has an `onError`
      (`.claude/rules/common/error-codes.md`)
- [ ] Server-only values carry no `NEXT_PUBLIC_` prefix, and raw HTML reaches the page only
      through an escaping helper (`.claude/rules/web/security.md`)
- [ ] Where the repo adopted them: every dialog has an announced description, a skeleton matches
      the height of what it stands in for, and a layout holds at a phone width
      (`.claude/rules/web/{dialog-content,skeletons,responsive}.md`)

</stack-block>
