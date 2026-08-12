---
description: Comprehensive code review — architecture, security, testing, and documentation audit for <Project Name>.
---

<!-- Command: /review -->
<!-- Source: _workflow-source/review.md -->
<!-- Run before every commit -->

# /review — Code Review Workflow

Senior-level review covering Golden Rules (AGENTS.md), security, unit test coverage, and documentation. Zero tolerance for pattern violations.

---

## Step 1: Automated Quality Gates

```bash
bun fl && bun type-check
```

**If these fail:**

- Report errors immediately.
- The review **CANNOT** pass until both are clean.
- **NEVER** use `// oxlint-disable` — fix the underlying issue (Rule 28).

---

## Step 2: Extract Staged Changes

```bash
git diff --cached
```

---

## Step 3: Architecture & Golden Rules Audit

Read `AGENTS.md` before auditing. All rules below reference it.

### 3.1 Separation of Concerns (Rules 5–7)

| Check                                                                 | Rule   | Severity    |
| :-------------------------------------------------------------------- | :----- | :---------- |
| No `useEffect` with logic in components                               | Rule 6 | 🔴 Critical |
| No `useState` for behavior/data/async in components                   | Rule 6 | 🔴 Critical |
| No `useRef` for DOM manipulation in components                        | Rule 6 | 🔴 Critical |
| No `window.*`, `document.*`, `navigator.*` in components              | Rule 6 | 🔴 Critical |
| No `setTimeout`, `setInterval`, `requestAnimationFrame` in components | Rule 6 | 🔴 Critical |
| No Observers (`IntersectionObserver`, `ResizeObserver`) in components | Rule 6 | 🔴 Critical |
| No async functions or `await` in components                           | Rule 6 | 🔴 Critical |
| No `useCallback`/`useMemo` wrapping business logic in components      | Rule 6 | 🔴 Critical |
| Hooks: one concern per file, filename matches export name (camelCase) | Rule 7 | 🔴 High     |
| Hooks: no JSX, no Tailwind classes                                    | Rule 7 | 🔴 High     |

### 3.2 Data & API Rules (Rules 13–18)

| Check                                                                  | Rule    | Severity    |
| :--------------------------------------------------------------------- | :------ | :---------- |
| No direct `fetch()` or `axios` to Payload CMS URLs                     | Rule 13 | 🔴 Critical |
| Components do not import from `src/lib/api/generated/` directly        | Rule 14 | 🔴 Critical |
| Query key factory exists before any new `useQuery` call                | Rule 15 | 🔴 High     |
| Service hook naming: `use{Domain}{Action}`                             | Rule 16 | 🔴 High     |
| Service hooks expose `{ data, isLoading, isError, error }`             | Rule 17 | 🔴 High     |
| Per-query `staleTime`/`gcTime` overrides have a comment explaining why | Rule 18 | 🟡 Medium   |

### 3.3 i18n Rules (Rules 19–22)

| Check                                                                 | Rule    | Severity    |
| :-------------------------------------------------------------------- | :------ | :---------- |
| No hardcoded user-facing strings in JSX                               | Rule 19 | 🔴 Critical |
| `useTranslations` scoped to a namespace, not root                     | Rule 20 | 🔴 High     |
| Any new/changed translation key added to BOTH `en.json` and `id.json` | Rule 21 | 🔴 Critical |
| Navigation uses `@/i18n/navigation` (not `next/navigation`)           | Rule 22 | 🔴 High     |

### 3.4 Styling Rules (Rules 11–12)

| Check                                                           | Rule    | Severity |
| :-------------------------------------------------------------- | :------ | :------- |
| Static values use `className`, not `style={}`                   | Rule 11 | 🔴 High  |
| Dynamic values from props/state/hooks use `style={}`            | Rule 11 | 🔴 High  |
| No dynamic arbitrary Tailwind: `` `w-[${x}px]` `` → use `style` | Rule 12 | 🔴 High  |
| No same property in both `className` and `style`                | Rule 12 | 🔴 High  |

### 3.5 Store Rules (Rule 8)

| Check                                                                    | Rule   | Severity    |
| :----------------------------------------------------------------------- | :----- | :---------- |
| `src/store/` only contains global UI state (theme, mobileMenuOpen, etc.) | Rule 8 | 🔴 High     |
| No server/API state in Zustand store (→ TanStack Query)                  | Rule 8 | 🔴 Critical |
| No per-component state in store (→ hook useState)                        | Rule 8 | 🔴 High     |

### 3.6 React Compiler Rules (Rules 23–24)

| Check                                                | Rule        | Severity |
| :--------------------------------------------------- | :---------- | :------- |
| No speculative `useMemo`, `useCallback`, or `memo()` | Rules 23–24 | 🔴 High  |

### 3.7 Code Quality (Rules 27–28)

| Check                                        | Rule    | Severity    |
| :------------------------------------------- | :------ | :---------- |
| No component file exceeds 150 lines          | Rule 27 | 🟡 Medium   |
| No `oxlint-disable` comments                 | Rule 28 | 🔴 Critical |
| `src/lib/api/generated/` not edited manually | Rule 29 | 🔴 Critical |

---

## Step 4: Security Audit

Industry-standard review aligned with **OWASP Top 10 (2021)**, **CWE Top 25**, and Next.js-specific threat surface. **Zero tolerance** for HIGH/CRITICAL findings — all must be resolved before merge.

### 4.1 Active Scans (must pass)

Run these scans first. **Block merge** if any returns a HIGH/CRITICAL finding.

```bash
# Dependency vulnerabilities (OWASP A06)
bun audit

# Hardcoded secrets in staged diff (OWASP A02)
git diff --cached | grep -iE "(api[_-]?key|apikey|secret|password|passwd|token|bearer|private[_-]?key|client[_-]?secret|aws[_-]?(access|secret))[\"']?\s*[:=]\s*[\"'][^\"']{6,}"

# .env files accidentally staged (OWASP A05)
git diff --cached --name-only | grep -E "^\.env(\.|$)"

# Production source maps leaked
find .next -name "*.map" 2>/dev/null | head -5

# Dangerous JS APIs: eval, Function constructor (OWASP A03)
git diff --cached | grep -E "\beval\s*\(|new\s+Function\s*\("

# Unsafe React patterns
git diff --cached | grep -E "dangerouslySetInnerHTML|__html"
```

### 4.2 OWASP A01 — Broken Access Control

| Check                                                                                  | Severity    |
| :------------------------------------------------------------------------------------- | :---------- |
| Server Actions accessible without checking referer/origin or auth context              | 🔴 Critical |
| `revalidatePath()` / `revalidateTag()` called with user-supplied path or key           | 🔴 Critical |
| API route exposes `src/lib/api/generated/` or internal endpoints to client             | 🔴 Critical |
| Direct access to admin/internal paths without route protection                         | 🔴 Critical |
| IDOR: object/resource IDs in URL accepted without ownership check                      | 🔴 High     |
| `middleware.ts` enforces route protection consistently — no bypass via locale prefixes | 🔴 High     |

### 4.3 OWASP A02 — Cryptographic Failures

| Check                                                                                 | Severity    |
| :------------------------------------------------------------------------------------ | :---------- |
| No hardcoded secrets, API keys, tokens (see 4.1)                                      | 🔴 Critical |
| `.env*` files in `.gitignore` and never committed (see 4.1)                           | 🔴 Critical |
| `NEXT_PUBLIC_*` env vars contain only non-sensitive values (treat as public)          | 🔴 Critical |
| Server-side secrets (Resend key, BE API key) never imported into `'use client'` files | 🔴 Critical |
| Random tokens via `crypto.randomUUID()` or Web Crypto API — never `Math.random()`     | 🔴 High     |
| No MD5 or SHA1 for security-sensitive operations                                      | 🔴 High     |
| Cookies: `httpOnly`, `secure`, `sameSite: "lax"` or `"strict"`                        | 🔴 High     |
| TLS enforced via `Strict-Transport-Security` header (see 4.6)                         | 🔴 High     |

### 4.4 OWASP A03 — Injection

| Check                                                                                                                 | Severity    |
| :-------------------------------------------------------------------------------------------------------------------- | :---------- |
| **XSS**: `dangerouslySetInnerHTML` only with DOMPurify-sanitized content                                              | 🔴 Critical |
| **XSS**: User input never directly assigned to `href`, `src`, `action`, `formaction` without URL allowlist validation | 🔴 Critical |
| **XSS**: `javascript:` and `data:` URL schemes rejected in user-supplied URLs                                         | 🔴 Critical |
| **Code injection**: No `eval()`, `new Function()`, or `setTimeout(string, ...)` (see 4.1)                             | 🔴 Critical |
| **Email injection**: Resend `subject`, `to`, `from`, `replyTo` validated — no CRLF (`\r\n`), length capped            | 🔴 Critical |
| **Email header injection**: User input never concatenated into email headers                                          | 🔴 Critical |
| **Prototype pollution**: No `Object.assign`/spread of unvalidated user data into config objects                       | 🔴 High     |
| **Path traversal**: No `fs`/`path.join` with user segments without `path.normalize` + allowlist                       | 🔴 High     |
| **Server Action inputs**: validated with **Zod at runtime** — TypeScript types alone are insufficient                 | 🔴 Critical |
| Zod schemas enforce `.max()` length limits on every string field (ReDoS / DoS defense)                                | 🔴 High     |
| No regex with catastrophic backtracking patterns (e.g., `(a+)+`) on user input                                        | 🔴 High     |

### 4.5 OWASP A04 — Insecure Design

| Check                                                                                          | Severity    |
| :--------------------------------------------------------------------------------------------- | :---------- |
| Public Server Actions (contact, newsletter) have **rate limiting** (IP- or session-based)      | 🔴 High     |
| `next.config.ts` sets `experimental.serverActions.bodySizeLimit` to a sane value (e.g., `1mb`) | 🔴 High     |
| No unbounded loops, recursion, or `while(true)` on user input                                  | 🔴 High     |
| File uploads (if any): MIME allowlist + size cap + extension validation + virus scan           | 🔴 Critical |
| Honeypot field or CAPTCHA on public forms to prevent bot abuse                                 | 🟡 Medium   |
| Email-sending endpoints throttled per recipient to prevent spam relay                          | 🔴 High     |

### 4.6 OWASP A05 — Security Misconfiguration

`next.config.ts` MUST define these headers via the `headers()` function:

| Header                         | Required Value                                                        | Severity    |
| :----------------------------- | :-------------------------------------------------------------------- | :---------- |
| `Content-Security-Policy`      | Strict — no `'unsafe-eval'`, no `'unsafe-inline'` (use nonces/hashes) | 🔴 Critical |
| `Strict-Transport-Security`    | `max-age=63072000; includeSubDomains; preload`                        | 🔴 Critical |
| `X-Content-Type-Options`       | `nosniff`                                                             | 🔴 Critical |
| `X-Frame-Options`              | `DENY`                                                                | 🔴 Critical |
| `Referrer-Policy`              | `strict-origin-when-cross-origin`                                     | 🔴 High     |
| `Permissions-Policy`           | Explicitly disable unused features (camera, mic, geolocation, etc.)   | 🔴 High     |
| `Cross-Origin-Opener-Policy`   | `same-origin`                                                         | 🟡 Medium   |
| `Cross-Origin-Embedder-Policy` | `require-corp` (if no third-party embeds)                             | 🟡 Medium   |

Additional config checks:

| Check                                                                                | Severity  |
| :----------------------------------------------------------------------------------- | :-------- |
| `images.remotePatterns` is a strict allowlist — never wildcard `**`                  | 🔴 High   |
| `productionBrowserSourceMaps: false` (default) — verify unchanged                    | 🔴 High   |
| `poweredByHeader: false` to remove `X-Powered-By`                                    | 🟡 Medium |
| Debug/dev flags disabled when `NODE_ENV === 'production'`                            | 🔴 High   |
| No verbose error pages in production (`next.config.ts` does not expose stack traces) | 🔴 High   |

### 4.7 OWASP A06 — Vulnerable and Outdated Components

| Check                                                                                         | Severity    |
| :-------------------------------------------------------------------------------------------- | :---------- |
| `bun audit` reports zero HIGH or CRITICAL vulnerabilities (see 4.1)                           | 🔴 Critical |
| Newly added packages: maintained < 12 months ago, > 1k weekly downloads, no typosquat signals | 🔴 High     |
| `bun.lock` committed and unchanged outside intentional updates                                | 🔴 High     |
| No `git://`, `http://`, or local-path package sources in `package.json`                       | 🔴 Critical |
| Package `overrides`/`resolutions` audited if used — flag every entry                          | 🟡 Medium   |
| No `postinstall` scripts in untrusted packages (check `package.json` of new deps)             | 🔴 High     |

### 4.8 OWASP A07 — Identification and Authentication Failures

> This repo has **no authentication**. Login redirects to FE LMS.

| Check                                                                                          | Severity    |
| :--------------------------------------------------------------------------------------------- | :---------- |
| **No auth code introduced** — flag `signIn`, `useSession`, NextAuth, Clerk, JWT, OAuth imports | 🔴 Critical |
| No session tokens stored in `localStorage` or `sessionStorage`                                 | 🔴 Critical |
| No credentials in URL query params or path segments                                            | 🔴 Critical |
| If auth is ever added: must use HTTPS-only secure cookies, not bearer tokens in JS             | 🔴 Critical |

### 4.9 OWASP A08 — Software and Data Integrity Failures

| Check                                                                                    | Severity    |
| :--------------------------------------------------------------------------------------- | :---------- |
| External `<script>` tags include **Subresource Integrity** (`integrity` + `crossorigin`) | 🔴 High     |
| External `<script src>` only from approved domains — explicit allowlist                  | 🔴 Critical |
| GitHub Actions / CI workflows pin actions to **commit SHAs**, not tags                   | 🔴 High     |
| No deserialization of user-controlled JSON into class instances without validation       | 🔴 High     |
| Dockerfile (if used) pins base image by digest (`@sha256:...`), not tag                  | 🔴 High     |
| Build artifacts verified against known checksums before deploy                           | 🟡 Medium   |

### 4.10 OWASP A09 — Security Logging and Monitoring Failures

| Check                                                                                        | Severity    |
| :------------------------------------------------------------------------------------------- | :---------- |
| No `console.log` of secrets, tokens, full request bodies, PII, or email contents             | 🔴 Critical |
| Stack traces and internal error messages never exposed in production responses               | 🔴 High     |
| Sentry (when added): scrub PII from breadcrumbs and error payloads (configured `beforeSend`) | 🔴 High     |
| Failed Server Action / API calls logged with correlation ID but no sensitive data            | 🟡 Medium   |
| Authentication-like events (when added) logged: success, failure, lockout                    | 🔴 High     |
| Logs do not include `Authorization` headers, cookies, or full URLs with secrets              | 🔴 Critical |

### 4.11 OWASP A10 — Server-Side Request Forgery (SSRF)

| Check                                                                                  | Severity    |
| :------------------------------------------------------------------------------------- | :---------- |
| `fetch()` URLs validated against allowlist (BE Learning Management System domain only) | 🔴 Critical |
| User-supplied URLs never passed directly to `fetch()`                                  | 🔴 Critical |
| `router.push()` / `redirect()` validated against internal route allowlist              | 🔴 Critical |
| `next-intl` navigation: locale path validated, no arbitrary external redirect          | 🔴 High     |
| All external requests use `signal: AbortSignal.timeout(5000)` or equivalent            | 🟡 Medium   |
| Image proxy / Next.js Image loader: only allowlisted hostnames                         | 🔴 High     |
| No DNS rebinding vectors: outbound IPs blocked at network layer (deployment concern)   | 🟡 Medium   |

### 4.12 Email Security (Resend)

| Check                                                                                    | Severity    |
| :--------------------------------------------------------------------------------------- | :---------- |
| Recipient emails validated with Zod `.email()` schema before passing to Resend           | 🔴 Critical |
| Subject line stripped of `\r\n`, length capped (≤ 200 chars)                             | 🔴 Critical |
| `from` / `replyTo` are **constants** or from server-side allowlist — never user input    | 🔴 Critical |
| Email body sanitized when it includes user content (HTML escape via React Email)         | 🔴 High     |
| Resend API key used only in Server Actions or Server Components, never in client bundles | 🔴 Critical |
| Rate limit email-sending Server Actions per IP and per recipient                         | 🔴 High     |
| DKIM, SPF, and DMARC configured at sending domain (deployment-side verification)         | 🔴 High     |

### 4.13 Next.js / React Specific

| Check                                                                                                  | Severity    |
| :----------------------------------------------------------------------------------------------------- | :---------- |
| `'use client'` files do NOT import from `src/lib/email/`, `src/lib/server/`, or any Server-only module | 🔴 Critical |
| Server-only modules use `import 'server-only'` to enforce build-time boundary                          | 🔴 High     |
| `useFormState` / `useActionState` return values never contain sensitive data                           | 🔴 High     |
| Dynamic route params (`params.id`, `searchParams`) validated with Zod before use                       | 🔴 High     |
| Image `src` from allowlisted hostnames only (see 4.6)                                                  | 🔴 High     |
| `next/script` with `strategy="afterInteractive"` for third-party scripts — no inline scripts           | 🔴 High     |
| App Router only — no `getServerSideProps` / `getInitialProps` / `pages/` directory                     | 🟡 Medium   |
| `cookies()` and `headers()` reads not cached (Next.js dynamic API requirement)                         | 🟡 Medium   |

### 4.14 Build & Deploy Integrity

| Check                                                                      | Severity    |
| :------------------------------------------------------------------------- | :---------- |
| `Dockerfile` uses non-root user (`USER node`)                              | 🔴 High     |
| `.dockerignore` excludes `.env*`, `.git`, `node_modules`, `.next`, secrets | 🔴 Critical |
| Production build does not emit source maps to public output                | 🔴 High     |
| `bun.lock` integrity verified at deploy (no `--ignore-lockfile`)           | 🔴 High     |
| Standalone build verified — no dev dependencies shipped                    | 🟡 Medium   |

### 4.15 Manual Verification

After all checks pass, manually verify the deployed/staging build:

1. **CSP**: Load site in browser DevTools → Console must show zero CSP violations
2. **Headers**: `curl -I https://<staging-url>` → confirm all 6 critical security headers present
3. **Source maps**: Network tab in production → no `.map` files served
4. **Cookies** (if any): DevTools → Application → Cookies → all show `HttpOnly`, `Secure`, `SameSite`
5. **Bundle inspection**: `bunx @next/bundle-analyzer` → verify no server-only modules in client chunks
6. **TLS**: `curl -v https://<url>` → TLS 1.3 negotiated, no weak ciphers

---

## Step 5: Accessibility & Performance

Landing page is public-facing — failure here is user-visible. Skip if the diff contains no `.tsx` or no UI/style changes.

### 5.1 Accessibility (a11y)

For any change touching `.tsx` files, **invoke `/a11y-audit`** on the affected paths and incorporate findings into the final report.

Additional auto-flag checks:

| Check                                                                                             | Severity    |
| :------------------------------------------------------------------------------------------------ | :---------- |
| All `Image`/`<img>` have meaningful `alt` text (or `alt=""` if purely decorative)                 | 🔴 Critical |
| Interactive elements (`button`, `a`, custom) have accessible names (text content or `aria-label`) | 🔴 Critical |
| Form fields have associated `<label htmlFor>` or `aria-labelledby`                                | 🔴 Critical |
| Focus visible on all interactive elements — no `outline: none` without replacement                | 🔴 Critical |
| No keyboard traps; all interactions reachable via Tab / Shift+Tab                                 | 🔴 Critical |
| `<html lang>` set and updates with active locale (next-intl)                                      | 🔴 Critical |
| Semantic HTML used (`<nav>`, `<main>`, `<section>`, `<article>`) — not all `<div>`                | 🔴 High     |
| Animations respect `prefers-reduced-motion`                                                       | 🔴 High     |
| Color contrast ≥ 4.5:1 body text, ≥ 3:1 large text (manual check flagged)                         | 🔴 High     |
| Heading hierarchy is linear (no h1 → h3 jumps) and a single `<h1>` per page                       | 🔴 High     |

### 5.2 Performance

| Check                                                                                             | Severity    |
| :------------------------------------------------------------------------------------------------ | :---------- |
| `next/image` used everywhere — no raw `<img>` tags                                                | 🔴 Critical |
| `next/image` always has explicit `width` + `height` (CLS prevention)                              | 🔴 Critical |
| Above-the-fold images use `priority` prop                                                         | 🔴 High     |
| Fonts loaded via `next/font` — no direct `<link>` to Google Fonts or third-party CDN              | 🔴 Critical |
| Server Components by default — `'use client'` only when needed (hooks, browser APIs)              | 🔴 High     |
| Heavy components dynamically imported via `next/dynamic` with skeleton fallback                   | 🔴 High     |
| Third-party scripts loaded via `next/script` with `strategy="afterInteractive"` or `"lazyOnload"` | 🔴 High     |
| No client-side data fetching for above-the-fold content (prefer RSC / SSR)                        | 🔴 High     |
| Bundle size delta < 10% vs main — run `bunx @next/bundle-analyzer` if uncertain                   | 🟡 Medium   |
| No barrel imports from large packages (`import { x } from 'lodash'` → `import x from 'lodash/x'`) | 🟡 Medium   |

### 5.3 Core Web Vitals targets

Verify on staging via Lighthouse (mobile):

| Metric                          | Target  | Severity if missed |
| :------------------------------ | :------ | :----------------- |
| LCP (Largest Contentful Paint)  | ≤ 2.5s  | 🔴 High            |
| INP (Interaction to Next Paint) | ≤ 200ms | 🔴 High            |
| CLS (Cumulative Layout Shift)   | ≤ 0.1   | 🔴 High            |
| FCP (First Contentful Paint)    | ≤ 1.8s  | 🟡 Medium          |
| TTFB (Time to First Byte)       | ≤ 600ms | 🟡 Medium          |

---

## Step 6: Testing Check

Scope: `src/hooks/` and `src/lib/` — unit tests with Vitest.

### 6.1 Run all tests

```bash
bun test
```

**Block** if any test fails.

### 6.2 Coverage thresholds

```bash
bun test --coverage
```

Block if any metric below threshold:

| Metric     | Minimum |
| :--------- | :------ |
| Statements | 80%     |
| Branches   | 75%     |
| Functions  | 80%     |
| Lines      | 80%     |

### 6.3 Test file presence

For each **new** hook in `src/hooks/` or utility in `src/lib/`:

- Corresponding test file MUST exist: `useXxx.ts` → `useXxx.test.ts`
- **Block** any new exported function without a test file

### 6.4 Test quality

| Check                                                                                           | Severity    |
| :---------------------------------------------------------------------------------------------- | :---------- |
| No trivial assertions: `expect(true).toBe(true)`, lone `toBeDefined()`, lone `not.toThrow()`    | 🔴 Critical |
| `describe` + `it` titles read as full sentences ("returns null when input is empty")            | 🔴 High     |
| Edge cases covered: empty input, `null`/`undefined`, min/max length, invalid format             | 🔴 High     |
| Error paths tested: invalid input → expected error thrown or returned                           | 🔴 High     |
| Mocks minimal — mock external boundaries only (`fetch`, Resend, BE SDK); not internal utilities | 🔴 High     |
| Tests deterministic — no `Date.now()` / `Math.random()` without seeding or fake timers          | 🔴 Critical |
| Async tests properly `await` or use `expect.assertions(n)` to catch missed assertions           | 🔴 Critical |
| No `test.skip` / `it.skip` / `describe.skip` without TODO comment + ticket reference            | 🔴 High     |
| No `console.log` left in test files                                                             | 🟡 Medium   |

Output format: `⚠ Missing test: src/hooks/useXxx.ts` · `⚠ Trivial test: src/hooks/useXxx.test.ts:42`

---

## Step 7: Documentation Check

Scope: exported functions in `src/hooks/`, `src/hooks/api/`, and `src/lib/`. Feeds TypeDoc → Nextra docs site.

### 7.1 JSDoc presence

Every exported function/hook MUST have a JSDoc block above its declaration.

### 7.2 JSDoc quality

| Check                                                                     | Severity  |
| :------------------------------------------------------------------------ | :-------- |
| Description is meaningful — not one word, not restating the function name | 🔴 High   |
| First line ends with period, < 80 chars (TypeDoc summary line)            | 🟡 Medium |
| All parameters documented: `@param name - description` (TS provides type) | 🔴 High   |
| Return value documented with `@returns description` when non-trivial      | 🔴 High   |
| Errors documented with `@throws {ErrorType} condition` if hook can throw  | 🔴 High   |
| Side effects documented (e.g., "Triggers analytics event on submit")      | 🔴 High   |
| Complex hooks include `@example` block with realistic usage               | 🟡 Medium |
| `@deprecated` tag includes replacement guidance + removal date            | 🔴 High   |
| Cross-references use `{@link OtherHook}` for related symbols              | 🟡 Medium |

### 7.3 Example of a passing JSDoc

```typescript
/**
 * Submits the contact form to BE Learning Management System and triggers a success notification.
 *
 * @param data - Validated contact payload from React Hook Form.
 * @returns Mutation state including isPending, isSuccess, and error.
 * @throws {ApiError} When the BE responds with a non-2xx status.
 *
 * @example
 * const { mutate, isPending } = useContactSubmit();
 * mutate({ name: 'Alice', email: 'a@b.com', message: 'Hi' });
 */
export function useContactSubmit() { ... }
```

Output format:

- `⚠ Missing JSDoc: src/hooks/useXxx.ts — exported but undocumented`
- `⚠ Poor JSDoc: src/hooks/useXxx.ts:12 — description too vague: "fetches data"`

---

## Step 8: Generate Review Report

### 8.1 Severity definitions

- **🔴 Critical** = exploitable / broken now, no preconditions. **Blocks merge.**
- **🟠 High** = exploitable under conditions, or violates a core Golden Rule. **Blocks merge.**
- **🟡 Medium** = defense-in-depth, code quality, non-blocking improvement.

### 8.2 Required output structure

Always output in this exact order:

````markdown
# /review Report — {feature or branch name}

## Status: {✅ LGTM | ⚠️ Requires Changes | ❌ Blocked}

**Severity Summary**

- 🔴 Critical: {N}
- 🟠 High: {N}
- 🟡 Medium: {N}

**Quality Gates**

| Gate                 | Status  |
| :------------------- | :------ |
| `bun fl`         | ✅ / ❌ |
| `bun type-check` | ✅ / ❌ |
| `bun test`       | ✅ / ❌ |
| Coverage thresholds  | ✅ / ❌ |
| `bun audit`          | ✅ / ❌ |

---

## Blocking Issues

> [!CAUTION]
> **{Title}** — `{file:line}`
> {Description}
> **Fix:** {Concrete fix instruction}

> [!WARNING]
> **{Title}** — `{file:line}`
> {Description}
> **Rule violated:** AGENTS.md Rule {N}

---

## Suggestions

> [!TIP]
> **{Title}** — `{file:line}`
> {Description}

```diff
- old code
+ new code
```

---

## Coverage Summary

- Statements: X% (target: 80%)
- Branches: X% (target: 75%)
- Functions: X% (target: 80%)

---

## Files Reviewed

{N} files, +{additions} / -{deletions} lines
````

---

## Step 9: User Approval & Action

Present three options to the user:

1. **Apply all blocking fixes** — automatically resolve Critical + High issues
2. **Walk through issue-by-issue** — show each one, decide together
3. **Skip — I'll handle it manually** — exit, user fixes on their own

Default recommendation: **option 1** when all issues are unambiguous; **option 2** when any architectural or product decision is involved.
