# AGENTS.md — <Project Name>

> Enforced guardrails. Read Rule 0 and 0b before touching any code.

<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

---

## ⚡ CRITICAL: Read Before Touching Any Code

### Rule 0 — Mandatory Reasoning Protocol

```
Phase 1 READ:    Identify all affected files. Use Serena MCP for .ts/.tsx — never Read/Grep/Glob for TypeScript.
                 Use Context7 MCP for library documentation lookups.
Phase 2 PLAN:    State what will change and why. If uncertain, ask first.
Phase 3 EXECUTE: Surgical changes only. Run quality gates before marking done.
```

Skipping Phase 1 or 2 is a disqualifying failure. No exceptions.

For Serena MCP availability rules and session-start requirements → see CLAUDE.md § Agent Tooling.

### Rule 0b — Pre-Task Checklist

```
[ ] Have I called mcp__serena__initial_instructions? (required before .ts/.tsx work)
[ ] Have I read the relevant SSOT.md sections for this task?
[ ] Are Serena MCP tools available? (see CLAUDE.md § Agent Tooling)
[ ] Have I found an existing pattern in the codebase to follow?
[ ] Do I know exactly which files I will touch?
[ ] Am I placing no logic inside a component?
[ ] If touching strings: will both en.json and id.json be updated?
[ ] If using a library API: have I checked Context7 for up-to-date docs?
```

---

## A. Behavioral Protocol

**Rule 1** — Think before coding. Read first, always. Do not write a single line before Phase 1 is complete.

**Rule 2** — Simplicity first. Minimal change that achieves the goal. Do not add abstractions that were not requested.

**Rule 3** — Surgical changes. Do not touch files or logic outside the scope of the task.

**Rule 4** — Goal-driven. If the approach is not working, stop and re-read. Do not push through with workarounds.

---

## B. Separation of Concerns

**Rule 5 — Layer Ownership**

| Layer      | Location               | Responsibility                             |
| ---------- | ---------------------- | ------------------------------------------ |
| UI         | `src/components/`      | JSX, styling, rendering only               |
| Logic      | `src/hooks/`           | Behavior, effects, complex state           |
| Global UI  | `src/store/`           | Shared UI state (theme, mobileMenuOpen)    |
| Data       | `src/lib/api/`         | orval-generated hooks + custom mutator     |
| Service    | `src/hooks/api/`       | TanStack Query wrappers over generated API |
| Validation | `src/lib/validations/` | Zod schemas + inferred types only          |
| Types      | `src/types/`           | Shared TypeScript interfaces               |
| Utilities  | `src/lib/`             | Pure functions, constants, helpers         |

**Rule 6 — Components (`src/components/`) — ALLOWED:**

- JSX and conditional rendering
- Calling custom hooks and spreading their return values
- Local presentation state: tooltip open/close, accordion expanded, hover
- Inline event handlers that are one-liners delegating to a hook function
- Component-scoped props interface (`interface XProps {}`)

**Rule 6 — Components — FORBIDDEN** (extract to `src/hooks/` or `src/lib/`):

_Lifecycle and platform — extract to `src/hooks/`:_

- `useEffect` with any logic beyond a trivial ref assignment
- `useState` that tracks behavior, data, or async state
- `useRef` used for DOM manipulation or timing
- `setTimeout`, `setInterval`, `requestAnimationFrame`
- `IntersectionObserver`, `ResizeObserver`, `MutationObserver`
- `window.*`, `document.*`, `navigator.*` calls
- Any async function or `await`
- `useCallback`, `useMemo` wrapping business logic
- Reading a store directly (`useUIStore(...)`) — always through a named hook, **however small the
  read**, so the store shape stays an implementation detail

_Domain computation — extract to `src/lib/`:_

- Traversing domain data: `.find` / `.filter` / `.reduce` / `.sort` / `.some` over any entity the
  app models
- Building a domain key by hand (`` `${projectId}:${taskId}` ``) — the builder lives once in
  `src/lib/`, and a second copy will drift
- Arithmetic that means something: percentages, totals, durations, date arithmetic
- Compound rules over more than one field (`status === 'pending' && !submitted`), which are
  exactly what breaks silently and cannot be tested without rendering

**Rule 6 — the line.** What decides it is not "is there a `const`" but **would this be wrong
if it were wrong somewhere else too?** A rule the app has to agree on belongs in `lib/`; a
choice about how _this_ element paints itself stays put. So these stay in the component:

- Equality against a prop for highlighting (`const isActive = activeScreen === key`)
- Picking a style variant from a field already present in the data
- Render-time paint decisions (which pixels to draw for the current colour map)
- Ephemeral interaction state — hover, focus, press — via `useFlag()` / `useDisclosure()`

```tsx
// WRONG — logic inside component
export function Nav() {
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => {
    const handler = () => setScrolled(window.scrollY > 50);
    window.addEventListener('scroll', handler);
    return () => window.removeEventListener('scroll', handler);
  }, []);
  return <nav className={scrolled ? 'bg-white' : ''}>...</nav>;
}

// CORRECT — logic extracted to hook
export function Nav() {
  const { scrolled } = useScrollPosition();
  return <nav className={scrolled ? 'bg-white' : ''}>...</nav>;
}
```

**Rule 7 — Hooks (`src/hooks/`)**

- One hook = one concern. Name it after that concern: `useScrollSpy`, `useContactForm`.
- Filename must match the export name: `useNavBehavior.ts` exports `useNavBehavior`. camelCase.
- Must not return JSX.
- Must not contain Tailwind classes or styling logic.
- May import from `src/lib/`, `src/store/`, and `src/types/`. Never from `src/components/` —
  a type needed by both layers belongs in `src/types/`. A hook reaching into a component for
  a type is usually also filed under the wrong feature; check the folder before the import.
- Lives in the folder of the feature it serves, mirroring `src/components/`. Never loose in
  `src/hooks/`. Enforced by `bun run check:hooks`; see Rule 30.

**Rule 8 — Store (`src/store/`)**

ALLOWED: Global UI state shared by multiple unrelated components (`theme`, `mobileMenuOpen`).

FORBIDDEN:

- Server state → use TanStack Query
- Auth session → read it from the auth client, never copy it into the store (if sign-in lives in
  another app, this repo holds no auth state at all)
- Per-component state → use local `useState` in a hook

**Rule 9 — Validations (`src/lib/validations/`)**

- One file per domain: `contact.ts`, `newsletter.ts`, etc.
- Zod schemas and inferred types only. No logic, no imports from components or hooks.

**Rule 10 — Types (`src/types/`)**

- Interfaces and types shared by more than one file.
- Component-local props interfaces stay in the component file.
- No runtime code — types and interfaces only.

---

## C. Styling Rules

**Rule 11 — `className` vs `style`**

| Case                                       | Use         |
| ------------------------------------------ | ----------- |
| Layout, spacing, typography, static colors | `className` |
| Values from props, state, or hooks         | `style`     |
| CSS custom properties (`--var`)            | `style`     |
| Animation with fixed values                | `className` |
| Animation delay/offset computed from index | `style`     |

**Rule 12 — FORBIDDEN styling patterns:**

- `style={}` for values expressible as a static Tailwind class
- The same property in both `className` and `style`
- Dynamic arbitrary Tailwind: ``className={`w-[${size}px]`}`` → use `style` instead

```tsx
// WRONG
<div className="text-white" style={{ color: 'white' }}>
<div className={`w-[${size}px]`}>
<div style={{ display: 'flex', padding: '16px' }}>

// CORRECT
<div
  className="absolute rounded-full bg-primary transition-transform"
  style={{ width: `${size}px`, animationDelay: `${index * 0.1}s` }}
>
```

---

## D. Data Fetching Rules

**Rule 13 — Services behind the backend must never be fetched directly from the FE.**

All data goes through <backend-service>. Whatever sits behind it — a content service, a database,
a third-party API holding server credentials — is invisible to the FE.
FORBIDDEN: `fetch()` or `axios` calls pointing at those services' URLs from anywhere in the FE.

**Rule 14 — Do not import from `src/lib/api/generated/` directly in components.**

Generated hooks are consumed via service hooks in `src/hooks/api/`. Components only know about service hooks.

**Rule 15 — Query key factory must exist before writing any service hook.**

Create `src/lib/api/query/query-keys.ts` first. No magic strings in `useQuery` calls.

**Rule 16 — Service hook naming:** `use{Domain}{Action}`

Examples: `useContentHero`, `useContactSubmit`, `useNewsletterSubscribe`.

**Rule 17 — Service hooks must always expose `{ data, isLoading, isError, error }`.**

Do not swallow errors silently.

**Rule 18 — `staleTime` and `gcTime` are set globally in `src/app/providers.tsx`.**

Per-query overrides require a comment explaining why.

---

## E. i18n Rules

**Rule 19 — Zero hardcoded user-facing strings.**

Even single-locale text in JSX is forbidden. All strings go through `useTranslations()` or `getTranslations()`.

**Rule 20 — Always scope to a namespace.**

```typescript
// CORRECT
const t = useTranslations('hero');
t('title');

// WRONG
const t = useTranslations();
t('hero.title');
```

**Rule 21 — Any PR that adds or changes a translation key must update both `en.json` and `id.json` in the same commit.** No exceptions.

**Rule 22 — Locale-aware navigation via `@/i18n/navigation`.**

```typescript
// CORRECT
import { Link, useRouter, usePathname } from '@/i18n/navigation';

// WRONG
import { Link, useRouter } from 'next/navigation';
```

---

## F. React Compiler Rules

**Rule 23 — Do not add `useCallback` or `useMemo` speculatively.**

React Compiler is active and handles memoization automatically. Exception: allowed only when
profiling proves it is necessary, with a comment explaining why the compiler pass was insufficient.

**Rule 24 — Do not add `memo()` wrappers speculatively.** Same reason as Rule 23.

---

## G. Analytics & Error Monitoring (Future)

**Rule 25 — Product analytics (not yet installed — pattern pre-defined, provider TBD):**

- Initialize in `src/lib/analytics/client.ts`
- All capture calls only from a custom hook (`useAnalytics`) — never inline in JSX
- Server-side events via the provider's server SDK in Server Actions

**Rule 26 — Sentry (not yet installed — pattern pre-defined):**

- Error boundary at layout level (`src/app/[locale]/layout.tsx`)
- `captureException()` only from hooks or server actions — not from the component render path

---

## H. Code Quality Rules

**Rule 27 — Max 150 lines per component file.**

If approaching the limit, extract a sub-component or custom hook.

**Rule 28 — No `oxlint-disable` comments.** Fix the underlying issue.

**Rule 29 — `src/lib/api/generated/` is read-only.** Never edit manually.

All changes come from running `bun generate:api` against `openapi.json`.

---

## I. Structure Rules

Rules added after the first release are appended here with the next free number; a number is never
reused or moved.

**Rule 30 — A component's folder names the feature it serves.** Feature folders are named after
the route segment they answer: `components/auth/forgot-password/` answers
`app/[locale]/(auth)/forgot-password/`. Inside a feature root, `shared/` is what two or more
sibling features import, and `shell/` is layout chrome that no feature imports — only the layout
does. **A part used from OUTSIDE the feature root does not belong to that root.** It moves to the
repo's cross-cutting home (`src/components/shared/<system>/` unless `SSOT.md` §4.3 names another),
never to `<root>/shared/`. Convert intra-root imports to `@/` before splitting a folder, as its own
commit — a relative import that escapes the folder breaks at build time, not at move time. Hooks
follow the same tree (Rule 7). Enforced by `bun run check:hooks`; the standard is
`.claude/rules/web/file-organization.md`.

**Rule 31 — No `any`.** No explicit `any` anywhere, tests included: not `: any`, `as any`,
`any[]`, `Record<string, any>`, nor a generic that defaults to it. External data is `unknown`,
narrowed with a type guard or parsed with Zod; a type that depends on the caller is a generic. No
`oxlint-disable` or `eslint-disable` to get past it. No double assertion through `unknown` either
(`x as unknown as T`): a test fake is a real object, a complete fixture, or a `Pick<...>`-narrowed
parameter. Enforced by oxlint `typescript/no-explicit-any` at `error` and by
`scripts/check/double-assertion.sh` in pre-commit and the quality gate. The rule file is
`.claude/rules/typescript/types.md`.

**Rule 32 — A component renders; it holds no logic.** No `useState`, `useEffect`,
`useLayoutEffect`, `useReducer`, `useMemo` or `useCallback` in a file under `src/components/`: a
boolean goes through `useFlag()` / `useDisclosure()`, a form value and every effect through a named
hook. No function declared beside the component, no handler with a block body (`close();
signOut.open();` is a sequence, and a sequence is one named action the hook exposes), no
`new Date` / `timeZone:`, no `.filter` / `.reduce` / `.sort` / `.flatMap` / `.some` / `.every` /
`.find`, no `.map` whose callback returns data rather than JSX, no `window` / `document` /
`localStorage` / timer / observer, no `await`, and no condition over more than one domain field. A
`useRef` stays only while it is passed to a JSX `ref=` in the same file. Behaviour goes to
`src/hooks/`, derivation to `src/lib/`, a server DTO to a hand-written view model in `src/types/` —
never to a re-export. Enforced by the `no-restricted-imports` overrides in `oxlint.json` and by
`bun run check:soc`, which is wired into pre-commit and the quality gate the moment a repo reads
clean; a repo still carrying residual findings runs it before every commit that touches components
and clears them by category, never by exemption. The standard is
`.claude/rules/web/separation-of-concerns.md`.

**Rule 33 — Tailwind classes are canonical.** `mt-[15px]` is `mt-3.75`, `h-[1lh]` is `h-lh`,
`bg-[var(--x)]` is `bg-(--x)`. An arbitrary value stays only when Tailwind's own canonicalizer
declines it — `text-[13px]`, `rounded-[10px]`, a measured `h-[39.5px]` — never because nobody
looked. No class interpolates a value into an arbitrary bracket: `w-[${n}px]` is never generated.
No class compiles to nothing, and no two classes in one list set the same properties. `--spacing`
stays undefined, because the whole fractional scale is computed from it. Enforced by
`bun run check:tailwind`, which calls `canonicalizeCandidates` from the installed tailwindcss, so
it cannot drift from the editor's own warning.

**Rule 34 — No re-exports.** A module exports only what it declares: no `export * from`,
no `export { x } from`, and no `import { x }` followed by `export { x }`. Import from the module
that declares the name. A barrel adds a second path to a binding without moving the dependency,
so a rename or a layer boundary has two places to keep in step. A `@documented` `index.ts` is a
marker the docs generator reads by name, and it exports nothing (`export {}`). Enforced by
`bun run check:reexport`, which parses every file under `src/` rather than grepping it.

---

## L. Documentation Auto-Discovery

The docs site (`<docs-repo>`) auto-discovers folders to document via a `@documented` JSDoc tag in `index.ts` — a marker file
that exports nothing (Rule 34). No changes to the docs repo are needed when adding new public folders.

### Opt-in: `@documented` tag

Any folder under `src/` whose public API should appear in the docs must have an `index.ts` with a `@documented <Label>` tag:

```ts
/** @documented Constants */

/* A marker, not a barrel: the generator lists the modules beside it. */
export {};
```

The tag is read as a **flag, not a label**. A docs generator that reads the `@documented` tag treats
it as a flag: it matches `/@documented\b/` and discards whatever follows, so the label reaches no
heading. Titles come from elsewhere: type pages are named after the source filename, and component
sections from a label map kept in the generator. Keep writing a label for human readers, but to
actually retitle a section you must edit the docs repo — changing the tag does nothing.

### Opt-out: `_` prefix

Files and folders prefixed with `_` are automatically skipped from docs generation. Use this for internal helpers that are not part of the public API.

### Folders that must have `@documented`

- `src/types/` — add tag to `index.ts`
- `src/store/` — add tag to `index.ts`
- `src/lib/validations/` — add tag to `index.ts`

For any new folder intended to be publicly documented: add the tag to its `index.ts`.

`src/hooks/` is deliberately absent from that list. The generator walks the hooks folder
unconditionally and never reads its `index.ts`, so every exported `use*` function is documented
whether a tag is present or not. The `_` prefix is the only opt-out that folder honours.

---

## K. Known Anti-Patterns

Lazy-loaded to keep this file lean. Before starting a task, check `.claude/anti-patterns/INDEX.md` and load only the file(s) matching your task's trigger keywords. Each entry is self-contained (symptom, root cause, fix, scope).

---

## J. Self-Review Gate

Required checklist before marking any task done:

```
[ ] MCP: mcp__serena__initial_instructions called at session start
[ ] MCP: Serena used for .ts/.tsx access (no built-in Read/Grep/Glob for TypeScript)
[ ] MCP: Context7 consulted for library API references
[ ] SoC: No logic in components, no JSX in hooks
[ ] Data: All fetches go through <backend-service>, no direct upstream-service calls
[ ] i18n: No hardcoded strings; both locale files updated if any key changed
[ ] Styling: No static values in style={}, no dynamic arbitrary values in className
[ ] Hooks: Filename matches export name, one concern per hook
[ ] Generated: src/lib/api/generated/ was not edited manually
[ ] Structure: feature folders, no any, no re-exports, canonical classes (Rules 30-34)
[ ] Quality gates passed: bash scripts/check/gates.sh
[ ] Line count: No component file exceeds 150 lines
[ ] Serena errors: Any failures logged to .claude/serena-errors.md
```
