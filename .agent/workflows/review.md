---
description: Review the staged changes, or else the branch against origin/dev, against this repo's frontend rules and security checklist, and report findings by severity. Reads and reports; changes nothing until you pick an option at the end.
---

<!-- Command: /review -->
<!-- Source: _workflow-source/review.md -->
<!-- Run before every commit -->

# /review — Code Review Workflow

Senior-level review covering the numbered rules in `AGENTS.md`, security, tests and documentation.
The human checklist around it, with this stack's own checks at the end, is
`.claude/docs/code-review-checklist.md`: read it too. A category with no command is a category
nobody checks, so every section below that has a gate says which one.

Severity: **CRITICAL** is exploitable or broken now; **HIGH** is exploitable under conditions or
breaks a numbered rule; **MEDIUM** is defense in depth or maintainability; **LOW** is a suggestion.
CRITICAL and HIGH block the merge.

---

## Step 1: Scope

```bash
git diff --cached --stat
git fetch origin && git diff origin/dev...HEAD --stat
```

Review the **staged** changes when there are any (`git diff --cached`): that is what `/commit` and
`/ship` hand you. Otherwise review the branch (`git diff origin/dev...HEAD`).

Read every diff whole. With RTK installed, run every `git diff` here as `rtk proxy git diff …`: its
rewrite condenses a diff and prints a line even for an empty one, so a review of a truncated diff,
or a grep piped from one, reports "clean".

---

## Step 2: The gates

```bash
bash scripts/check/gates.sh --hook   # reviewing staged changes: the gates they need
bash scripts/check/gates.sh          # reviewing a branch: every gate
```

`scripts/check/gates.list` is the list pre-commit runs: format and lint, the staged secret scan,
type check, dead code, double assertions, folder shape, the coverage policy and the tests,
translation parity and button casing, hook placement, re-exports, logic in components, Tailwind
classes, error codes and catch blocks, the optional modules, the AI config and the mirrors.

The review **cannot** pass while a gate is red. Report each failure with the gate's log tail, and
never silence one with `oxlint-disable` (Rule 28): fix the underlying issue.

---

## Step 3: Architecture and the numbered rules

Read `AGENTS.md` before auditing. Each check below names its rule; where a gate enforces it, a red
gate is the finding and the text here is what to look for beside it.

### 3.1 Separation of concerns (Rules 5–7, 32)

- CRITICAL — A component holds logic: `useState`, `useEffect`, `useLayoutEffect`, `useReducer`,
  `useMemo`, `useCallback`, a timer, an observer, `window` / `document` / `navigator` / storage,
  `await`, a `.filter` / `.reduce` / `.sort` / `.find` / data-returning `.map`, date formatting, a
  handler with a block body, or a condition over two domain fields (Rule 32, `check:soc`).
- CRITICAL — A `useRef` in a component that is not passed to a JSX `ref=` in the same file.
- HIGH — A hook with more than one concern, a filename that does not match its export, or a hook
  that returns JSX or Tailwind classes (Rule 7).
- HIGH — A hook outside its feature folder, a test not at the mirrored path under
  `src/testing/hooks/`, or two hooks with one filename (Rule 30, `check:hooks`).

### 3.2 Data and API (Rules 13–18)

- CRITICAL — A direct `fetch()` or `axios` call to a service behind `<backend-service>` (Rule 13).
- CRITICAL — A component importing from `src/lib/api/generated/` (Rule 14; oxlint refuses it).
- HIGH — A new `useQuery` with no query-key factory entry (Rule 15), a service hook not named
  `use{Domain}{Action}` (Rule 16), or one that does not expose `{ data, isLoading, isError, error }`
  (Rule 17).
- MEDIUM — A per-query `staleTime` / `gcTime` override without a comment saying why (Rule 18).
- HIGH — A request that waits for another request's answer when the URL or the server already
  holds the value it needs (`.claude/rules/web/data-fetching.md` W1–W6).

### 3.3 i18n (Rules 19–22)

- CRITICAL — A hardcoded user-facing string in JSX, `aria-label`, `alt` or `title` (Rule 19). The
  gate checks key parity, not a string that was never made a key: read the diff for literals.
- CRITICAL — A key added or changed in one locale file and not the other (Rule 21, `check:i18n`).
- HIGH — `useTranslations()` or `getTranslations()` without a namespace (Rule 20).
- HIGH — Navigation from `next/navigation` instead of `@/i18n/navigation` (Rule 22).
- MEDIUM — A button text that is not Title Case in every locale (`check:i18n`).

### 3.4 Styling (Rules 11, 12, 33)

- HIGH — A static value in `style={}`, or a dynamic value in `className` (Rule 11).
- HIGH — A dynamic arbitrary class (`` `w-[${x}px]` ``), or one property set in both `className`
  and `style` (Rule 12).
- HIGH — A non-canonical Tailwind class, a class that compiles to nothing, or two classes that set
  the same property (Rule 33, `check:tailwind`).

### 3.5 Store (Rule 8)

- CRITICAL — Server or API state in a Zustand store: it belongs to TanStack Query.
- HIGH — Per-component state in a store, or a store holding anything but UI state shared by
  unrelated components.

### 3.6 React Compiler (Rules 23–24)

- HIGH — A speculative `useMemo`, `useCallback` or `memo()`.

### 3.7 Code quality (Rules 27–29, 31, 34)

- MEDIUM — A file over 150 lines (Rule 27; oxlint reports it as an error).
- CRITICAL — An `oxlint-disable` comment (Rule 28), or a hand edit under
  `src/lib/api/generated/` (Rule 29).
- HIGH — An explicit `any` or a double assertion through `unknown` (Rule 31; oxlint and
  `double-assertion.sh`).
- HIGH — A re-export: `export * from`, `export { x } from`, or an import forwarded by `export`
  (Rule 34, `check:reexport`).

---

## Step 4: Security audit

Aligned with the OWASP Top 10 (2021), CWE Top 25 and the Next.js threat surface. Every HIGH and
CRITICAL finding is resolved before merge.

### 4.1 Active scans, every review

```bash
bun audit                                                                 # dependencies (A06)
bash scripts/check/secrets.sh                                             # staged secrets (A02)
gitleaks git --no-banner --redact --config .gitleaks.toml --log-opts="origin/dev..HEAD"   # the branch
git diff --cached --name-only | grep -E '(^|/)\.env[^/]*$' | grep -vE '\.example$'        # env files staged
git diff --cached | grep -nE 'eval\s*\(|new\s+Function\s*\(|dangerouslySetInnerHTML|__html'
```

Run the dependency audit on every review, not only when the lockfile changed, and report what it
finds. With RTK installed, start both greps with `rtk proxy git diff …`: a grep over a filtered diff
returns nothing and reads as clean.

### 4.2 A01 — Broken access control

- CRITICAL — A Server Action that skips the origin or the auth check.
- CRITICAL — `revalidatePath()` / `revalidateTag()` called with a user-supplied path or key.
- CRITICAL — An API route that exposes the generated client or an internal endpoint to the client.
- HIGH — An object id from the URL used without an ownership check.
- HIGH — Route protection in the proxy that a locale prefix bypasses.

### 4.3 A02 — Cryptographic failures

- CRITICAL — A secret, key or token in source (see 4.1), or a `NEXT_PUBLIC_*` variable holding
  anything that is not public.
- CRITICAL — A server-side secret imported into a `'use client'` file.
- HIGH — A random token from `Math.random()` rather than `crypto.randomUUID()` or Web Crypto; MD5
  or SHA-1 for anything security-sensitive.
- HIGH — A cookie without `httpOnly`, `secure` and `sameSite` of `lax` or `strict`.

### 4.4 A03 — Injection

- CRITICAL — `dangerouslySetInnerHTML` with content that DOMPurify did not sanitise.
- CRITICAL — User input in `href`, `src`, `action` or `formaction` without an allowlist, or a
  `javascript:` / `data:` scheme accepted from a user.
- CRITICAL — `eval()`, `new Function()` or `setTimeout` with a string (see 4.1).
- CRITICAL — A Server Action input not validated with Zod at runtime; types alone are not a check.
- HIGH — A Zod string field with no `.max()`, a regex with catastrophic backtracking on user
  input, unvalidated user data spread into a config object, or a file path built from user
  segments.

### 4.5 A04 — Insecure design

- HIGH — A public Server Action (a contact or newsletter form) with no rate limit.
- HIGH — `experimental.serverActions.bodySizeLimit` unset or oversized in `next.config.ts`.
- HIGH — An unbounded loop or recursion on user input.
- CRITICAL — A file upload without a MIME allowlist, a size cap and an extension check.
- MEDIUM — A public form with no honeypot field or challenge.

### 4.6 A05 — Security misconfiguration

`next.config.ts` (or the proxy, for a per-request nonce) sets these headers:

- CRITICAL — `Content-Security-Policy` without `'unsafe-eval'` or `'unsafe-inline'` (nonces or
  hashes); `Strict-Transport-Security: max-age=63072000; includeSubDomains; preload`;
  `X-Content-Type-Options: nosniff`; `X-Frame-Options: DENY`.
- HIGH — `Referrer-Policy: strict-origin-when-cross-origin`; a `Permissions-Policy` that turns off
  unused features.
- MEDIUM — `Cross-Origin-Opener-Policy: same-origin`; `Cross-Origin-Embedder-Policy: require-corp`
  where no third-party embed needs otherwise.
- HIGH — `images.remotePatterns` with a wildcard host, production source maps switched on, debug
  flags live in production, or stack traces in a production error page.
- MEDIUM — `poweredByHeader` left on.

### 4.7 A06 — Vulnerable and outdated components

- CRITICAL — A HIGH or CRITICAL advisory in `bun audit` (4.1), or a `git://`, `http://` or local
  path package source.
- HIGH — A new package that is unmaintained, barely downloaded or a likely typosquat; an unexpected
  `bun.lock` change; a `postinstall` script in a new dependency.
- MEDIUM — An `overrides` entry without a comment saying which advisory it answers.

### 4.8 A07 — Identification and authentication

> If sign-in lives in another app (`<frontend-app>`), this repo holds **no authentication** and the
> first finding applies. If this app owns sign-in, skip it and apply the last one instead.

- CRITICAL — Sign-in lives elsewhere, and auth code is introduced here: `signIn`, `useSession`,
  NextAuth, Clerk, JWT or OAuth imports (the quality gate's auth scan flags them too).
- CRITICAL — A session token in `localStorage` or `sessionStorage`, or a credential in a URL.
- HIGH — This app owns sign-in, and a session cookie lacks `HttpOnly`, `Secure` or `SameSite`, or
  a sign-in or reset form has no rate limit.

### 4.9 A08 — Software and data integrity

- CRITICAL — An external `<script src>` from a host outside an explicit allowlist.
- HIGH — An external script without `integrity` and `crossorigin`.
- HIGH — A workflow action not pinned to a full commit SHA (`workflows-lint.yml` checks it on the
  pull request), or a Dockerfile base image without a digest.
- HIGH — User-controlled JSON deserialised into a class instance without validation.

### 4.10 A09 — Logging and monitoring

- CRITICAL — A `console.log` of a secret, a token, a full request body or personal data; logged
  `Authorization` headers, cookies or URLs that carry a secret.
- HIGH — A stack trace or an internal error message in a production response.
- MEDIUM — A failed Server Action or API call logged without a correlation id.

### 4.11 A10 — Server-side request forgery

- CRITICAL — A `fetch()` URL built from user input, or one outside the `<backend-service>` host.
- CRITICAL — `router.push()` / `redirect()` to a target outside the internal route allowlist.
- HIGH — Locale navigation that allows an external redirect, or an image loader that accepts any
  host.
- MEDIUM — An external request without a timeout (`AbortSignal.timeout(5000)` or similar).

### 4.12 Next.js and React

- CRITICAL — A `'use client'` file importing a server-only module (anything under
  `src/lib/server/`, or marked `import 'server-only'`).
- HIGH — A server-only module without `import 'server-only'`; sensitive data in a
  `useActionState` result; route params or `searchParams` used without Zod validation; a
  third-party script not loaded through `next/script`.
- MEDIUM — `pages/`, `getServerSideProps` or `getInitialProps` in an App Router repo; a cached
  `cookies()` or `headers()` read.

### 4.13 Build and deploy

- CRITICAL — A `.dockerignore` that lets an env file, `.git` or the agent layer into the image.
- HIGH — A Dockerfile running as root, source maps in the public output, or an install that
  ignores the lockfile.
- MEDIUM — Dev dependencies shipped in the standalone build.

### 4.14 Manual verification on staging

1. CSP: the browser console shows no violation.
2. Headers: `curl -I https://<staging-url>` (`rtk proxy curl -I …` with RTK installed) shows the
   four CRITICAL headers from 4.6.
3. Source maps: the network tab serves no `.map` file.
4. Cookies, if any: `HttpOnly`, `Secure` and `SameSite` on each.
5. Bundle: no server-only module in a client chunk.

---

## Step 5: Accessibility and performance

The site is public-facing, so a failure here is one people see. Skip when the diff touches no
`.tsx` and no style.

### 5.1 Accessibility

For any change to `.tsx` files, **run `/a11y-audit`** on the affected paths and fold its findings
into the report. Beyond it:

- CRITICAL — An image without meaningful `alt` (or `alt=""` when decorative); an interactive
  element without an accessible name; a form field without a label; focus styles removed without a
  replacement; a keyboard trap; `<html lang>` not following the active locale.
- HIGH — `<div>` where `<nav>`, `<main>`, `<section>` or `<article>` belongs; animation that
  ignores `prefers-reduced-motion`; contrast below 4.5:1 for body text or 3:1 for large text;
  skipped heading levels or more than one `<h1>`.
- HIGH — A dialog without an announced description (`check:dialog-desc`, where the module is
  adopted).

### 5.2 Performance

- CRITICAL — A raw `<img>`, a `next/image` without `width` and `height`, or a font loaded from a
  third-party `<link>` instead of `next/font`.
- HIGH — Above-the-fold images without `priority`; `'use client'` where a Server Component would
  do; a heavy component not loaded with `next/dynamic` and a skeleton; client-side fetching for
  above-the-fold content; a third-party script not deferred.
- HIGH — A layout that shifts when data arrives: a skeleton whose height is not the real
  component's (`.claude/rules/web/skeletons.md`, where the module is adopted).
- MEDIUM — A bundle delta over 10% against the base branch; a barrel import from a large package.

Core Web Vitals on staging, mobile Lighthouse: LCP ≤ 2.5 s, INP ≤ 200 ms and CLS ≤ 0.1 are HIGH
when missed; FCP ≤ 1.8 s and TTFB ≤ 600 ms are MEDIUM.

---

## Step 6: Tests

The logic layer is `src/hooks/`, `src/lib/`, `src/store/`, `src/i18n/` and `src/proxy.ts`, held at
100% statements, branches, functions and lines (`.claude/rules/typescript/coverage.md`).

```bash
bun run test:coverage
```

`bun run test` and `bun run test:coverage` are Vitest. Bare `bun test` is Bun's own runner: it has
no `vi.mocked` and reports failures that are not real.

- CRITICAL — A failing test, or a metric below 100% on the logic layer.
- HIGH — A new hook or lib file without its test at the mirrored path: `src/hooks/<feature>/useX.ts`
  → `src/testing/hooks/<feature>/useX.test.ts`. An orphaned test stops running without failing.
- CRITICAL — A trivial assertion (`expect(true).toBe(true)`, a lone `toBeDefined()`), a test that
  reads the wall clock or `Math.random()` unfrozen, or an async test that can pass without
  asserting.
- HIGH — Missing edge cases (empty, `null`, `undefined`, limits, invalid format) or error paths; a
  module replaced from a test file instead of the shared doubles in `src/testing/mocks/`; a skipped
  test without a reason and a ticket.
- MEDIUM — A `describe` / `it` title that is not a sentence; a `console.log` left in a test.

Output lines: `Missing test: src/hooks/<feature>/useX.ts` · `Trivial test: <file>:<line>`.

---

## Step 7: Documentation

Every exported function and hook in `src/hooks/` and `src/lib/` carries a JSDoc block above its
declaration; the docs site builds its reference from them.

- HIGH — A description that restates the name, an undocumented parameter or non-trivial return, a
  throw without `@throws`, or an undocumented side effect.
- HIGH — `@deprecated` without its replacement and removal date.
- MEDIUM — A summary line over 80 characters or without a full stop; a complex hook without an
  `@example`; a related symbol not linked with `{@link}`.

A passing block:

```typescript
/**
 * Submits the contact form to <backend-service> and shows a success notice.
 *
 * @param data - Validated contact payload from React Hook Form.
 * @returns Mutation state including isPending, isSuccess, and error.
 * @throws {ApiError} When the API responds with a non-2xx status.
 *
 * @example
 * const { mutate, isPending } = useContactSubmit();
 * mutate({ name: 'Alice', email: 'a@b.com', message: 'Hi' });
 */
export function useContactSubmit() { ... }
```

Output lines: `Missing JSDoc: <file> — exported but undocumented` ·
`Poor JSDoc: <file>:<line> — <why>`.

---

## Step 8: The report

Always in this order:

````markdown
# /review Report — {feature or branch name}

## Status: {LGTM | Requires Changes | Blocked}

CRITICAL: {N} · HIGH: {N} · MEDIUM: {N} · LOW: {N}

## Gates

- `bash scripts/check/gates.sh`: {every gate passed | the gates that failed, with their log tail}
- `bun audit`: {clean | the advisories}

## Blocking Issues

> [!CAUTION]
> **{Title}** — `{file:line}`
> {Description}
> **Fix:** {Concrete fix}
> **Rule:** AGENTS.md Rule {N}, when one applies

## Suggestions

> [!TIP]
> **{Title}** — `{file:line}`
> {Description}

## Coverage

Statements, branches, functions and lines on the logic layer: {each at 100% | which one is short}.

## Files Reviewed

{N} files, +{additions} / -{deletions} lines
````

---

## Step 9: What to do with it

Offer three options:

1. **Apply all blocking fixes** — resolve every CRITICAL and HIGH finding.
2. **Walk through them one by one** — decide each together.
3. **Stop here** — the user fixes them.

Recommend option 1 when every fix is unambiguous, and option 2 when one involves an architectural
or product decision. Inside `/ship` there is no choice to offer: `/ship` fixes everything down to
MEDIUM and carries on.
