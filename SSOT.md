# SSOT.md — <Project Name> FE

**Version:** 1.0.0
**Owner:** `<owner>`
**Status:** `<current stage — be specific; "active development" tells an agent nothing>`
**Last verified against repo:** `<YYYY-MM-DD>`

> Single Source of Truth for architectural decisions, data patterns, and technical contracts.
> Read the relevant section before starting any task.

> **How this file differs from the other two.** `CLAUDE.md` routes and `AGENTS.md` forbids; this
> file **describes**. It is the only one of the three that goes stale on its own, because it makes
> claims about a codebase that keeps moving. That is what the "Last verified" date above is for —
> if it is months old, treat this file as a lead, not as authority.
>
> §1 and §2 below are scaffolding: they describe a product, and yours is a different one. Replace
> them. §3 through §7 are the transferable part and can be edited in place.

---

## 1. Product Context

### 1.1 What Is This Repository

`<One paragraph: who uses this app and what it does. Then a table of the route groups or top-level
surfaces, so an agent can place any file it opens.>`

| Route group | Path | Contents |
| ----------- | ---- | -------- |
| `<group>`   | `<path>` | `<what lives here>` |

### 1.2 Scope of This Repository

`<State the boundary as a set of negatives — those are what an agent actually needs. "No auth
server, no CMS, no database" stops a whole class of wrong plans before they start. A scope written
only as positives does not.>`

### 1.3 Current Implementation Stage

`<Read this section before touching data.>`

`<The single most valuable section in this file, and the one most often missing. Say plainly what
is wired and what is not. If screens render from fixtures rather than the API, say so here and name
the fixture files — otherwise every agent rediscovers it, and some will "fix" the fixtures by
deleting them.>`

`<Also state what to build toward, and in what order. Example shape: create the service hook layer
before wiring any screen; never let a component reach the generated client directly; never delete a
fixture until its screen is fully migrated.>`

---

## 2. Ecosystem Overview

### 2.1 The Subsystem This Repo Lives In

`<An ASCII diagram of just the slice this repo touches — the backends it calls, what those own,
what writes to the same database. Keep it small. The value is in the arrows that do NOT exist.>`

```
┌─────────────────────────────────────────────────────────────┐
│  <SUBSYSTEM>                                                │
├─────────────────────────────────────────────────────────────┤
│  <this repo>                                                │
│    └── data  → <backend>                                    │
│    └── auth  → <auth owner>                                 │
│                                                             │
│  <backend>                                                  │
│    └── content → <cms>                                      │
│    └── store   → <database>                                 │
└─────────────────────────────────────────────────────────────┘
```

**Critical rule:** `<the one boundary that must never be crossed, stated as a rule and not as a
description — e.g. "this app must never query the CMS directly; all data flows through the
backend">`

### 2.2 The Wider Platform

`<Optional. Include only if this repo is one of several sharing infrastructure. If it stands alone,
delete this whole subsection rather than filling it with "N/A".>`

`<If you do fill it in, mark how much to trust it. A table assembled from directory layout is
orientation; a table maintained by whoever owns the platform is authority. Say which one this is —
an unmarked table gets cited as fact within a week.>`

---

## 3. Tech Stack Decisions

| #    | Choice                      | Version                                            | Why                                          | Key Constraint                                                                  |
| ---- | --------------------------- | -------------------------------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------- |
| 3.1  | Next.js + React Compiler    | 16.2.x                                             | App Router, RSC, image optimization          | React Compiler (`babel-plugin-react-compiler` 1.0) — no speculative memoization |
| 3.2  | React                       | 19.2.x                                             | Latest stable, concurrent features           | Do not use legacy patterns (class components, legacy context)                   |
| 3.3  | TanStack Query              | v5                                                 | Server state management                      | staleTime/gcTime set globally in `src/app/providers.tsx`                        |
| 3.4  | next-intl                   | v4                                                 | i18n for en/id locales                       | All strings via `useTranslations` — zero hardcoded UI text                      |
| 3.5  | Orval                       | v8                                                 | Auto-generates API hooks from `openapi.json` | `src/lib/api/generated/` is read-only — regenerate with `bun generate:api`      |
| 3.6  | Zod                         | v4                                                 | Schema validation + type inference           | Used in `src/lib/validations/` only                                             |
| 3.7  | Zustand                     | v5                                                 | Global UI state only                         | Two stores: `ui-store.ts`, `lms-store.ts`. Server state → TanStack Query        |
| 3.8  | Tailwind CSS                | v4                                                 | Utility-first styling                        | `@import "tailwindcss"` not `@tailwind` directives                              |
| 3.9  | Framer Motion               | v12                                                | Animations                                   | Shared variants live in `src/lib/animations.ts`                                 |
| 3.10 | Oxlint + Oxfmt              | 1.x/0.6x                                           | Linting and formatting (not eslint/prettier) | `bun fl` = format + lint; `bun type-check` = tsc                                |
| 3.11 | TypeScript                  | 6.x                                                | Strict type checking                         | `tsc --noEmit` must pass before any task is done                                |
| 3.12 | React Hook Form + resolvers | v7                                                 | Form state for auth + contact forms          | Pair with Zod schemas from `src/lib/validations/`                               |
| 3.13 | Vitest + Testing Library    | v4 / v16                                           | Unit tests (jsdom)                           | Tests live in `src/testing/`, mirroring `src/` — not colocated                  |
| 3.14 | Resend + React Email        | v6 / v1                                            | Transactional email                          | Server-side only, `src/lib/email/`                                              |
| 3.15 | Sonner                      | v2                                                 | Toasts                                       | Always through the `src/lib/toast.ts` wrapper                                   |
| 3.16 | Icons                       | lucide-react v1 + `@hackernoon/pixel-icon-library` | Two deliberate sets                          | Pixel icons carry the brand accent; lucide covers the rest                      |
| 3.17 | Husky                       | v9                                                 | Git hooks                                    | `prepare` script installs them on `bun install`                                 |

Dependency pinning: `overrides` in `package.json` pins transitive packages flagged by audits
(`undici`, `sharp`, `postcss`, `dompurify`, …). Do not remove an override without re-checking why
it was added.

---

## 4. Architecture

### 4.1 Layer Map

| Layer      | Location               | Responsibility                              | Rationale                                          |
| ---------- | ---------------------- | ------------------------------------------- | -------------------------------------------------- |
| UI         | `src/components/`      | JSX, styling, rendering only                | No logic, no async, no effects with behavior       |
| Logic      | `src/hooks/`           | Behavior, effects, complex state            | One hook = one concern, named after concern        |
| Global UI  | `src/store/`           | Shared UI state (`ui-store`, `lms-store`)   | Only state shared by multiple unrelated components |
| Data       | `src/lib/api/`         | Orval-generated client + `mutator.ts`       | Generated output is read-only                      |
| Service    | `src/hooks/api/`       | TanStack Query wrappers over generated API  | **Not created yet** — see §1.3                     |
| Validation | `src/lib/validations/` | Zod schemas + inferred types only           | No logic, no imports from components or hooks      |
| Fixtures   | `src/lib/constants/`   | Typed static content + app constants        | Interim data source until API wiring — see §1.3    |
| Types      | `src/types/`           | Shared interfaces (`courses`, `lms`)        | Only types used by more than one file              |
| Utilities  | `src/lib/`             | Pure functions, helpers, animation variants | No side effects, no imports from UI or hooks       |
| Email      | `src/lib/email/`       | Resend init + React Email templates         | Server-side only                                   |
| i18n       | `src/messages/`        | `en.json` + `id.json` translation files     | Both must be updated together                      |
| Tests      | `src/testing/`         | Vitest setup, helpers, and specs            | Mirrors `src/` structure — not colocated           |

### 4.2 File & Folder Naming

| Type        | File convention | Export convention  | Example                                          |
| ----------- | --------------- | ------------------ | ------------------------------------------------ |
| Components  | kebab-case      | PascalCase         | `catalog-screen.tsx` exports `CatalogScreen`     |
| Hooks       | camelCase       | camelCase          | `useCatalogFilter.ts` exports `useCatalogFilter` |
| Directories | kebab-case      | —                  | `src/components/lms/screens/`                    |
| Constants   | kebab-case      | SCREAMING or camel | `src/lib/constants/lms-courses.ts`               |
| Types       | kebab-case      | PascalCase         | `src/types/courses.ts`                           |

> Note: CLAUDE.md § Naming Conventions still shows `HeroSection.tsx` for component files. The
> repo is uniformly kebab-case for component filenames; follow the table above.

### 4.3 App Router Structure

```
src/
├── app/
│   ├── layout.tsx                        # Root layout
│   ├── providers.tsx                     # TanStack Query provider
│   └── [locale]/
│       ├── layout.tsx                    # Locale layout (next-intl)
│       ├── (marketing)/page.tsx          # Landing page
│       ├── (auth)/                       # login · register · forgot-password
│       │                                 # reset-password · verify-otp
│       └── (lms)/lms/                    # LMS app shell
├── components/
│   ├── auth/                             # Auth surfaces (+ screens/)
│   ├── lms/                              # LMS surfaces
│   │   ├── lms-app/                      # Shell: nav meta, screen router
│   │   ├── screens/                      # One file per LMS screen
│   │   ├── content/ · quiz/ · sidebar/   # Feature areas
│   │   └── shared/                       # Cross-screen LMS pieces
│   └── ui/                               # Primitives (cva + tailwind-merge)
├── hooks/
│   ├── lms/                              # LMS-specific behavior hooks
│   ├── api/                              # Service hooks — TO BE CREATED (§1.3)
│   └── index.ts                          # @documented barrel
├── i18n/                                 # next-intl config + navigation helpers
├── lib/
│   ├── api/
│   │   ├── generated/                    # READ-ONLY — Orval output
│   │   └── mutator.ts                    # customInstance fetch wrapper
│   ├── constants/                        # App constants + content fixtures
│   ├── email/templates/                  # Resend + React Email
│   ├── utils/                            # Domain helpers (lms-helpers.ts)
│   ├── validations/                      # Zod schemas
│   ├── animations.ts · toast.ts · utils.ts · password-utils.ts
├── messages/{en,id}.json                 # Translations — update together
├── store/                                # ui-store.ts · lms-store.ts
├── styles/                               # Global CSS
├── testing/                              # Vitest specs mirroring src/
└── types/                                # courses.ts · lms.ts
```

### 4.4 React Compiler

React Compiler is enabled. Do not add `useCallback`, `useMemo`, or `memo()` speculatively.

### 4.5 i18n Navigation

Always use locale-aware navigation helpers from `@/i18n/navigation`:

```typescript
// CORRECT
import { Link, useRouter, usePathname } from '@/i18n/navigation';

// WRONG
import { Link, useRouter } from 'next/navigation';
```

Key parity between `en.json` and `id.json` is enforced by `bun check:i18n`.

---

## 5. API Contract

### 5.1 Orval-Generated Client

`openapi.json` at project root is the source of truth for all API contracts (configured in
`orval.config.ts`; the client is `react-query` with the `customInstance` mutator from
`src/lib/api/mutator.ts`).

```
openapi.json change
  └── bun generate:api  → src/lib/api/generated/ (READ-ONLY)
```

Never edit `src/lib/api/generated/` manually — it is overwritten on the next generate, and
`.oxfmtrc.json` deliberately excludes it from formatting.

### 5.2 Service Hook Pattern (target shape)

```typescript
// src/hooks/api/useCourseListing.ts

/** Fetches the public course listing for the homepage. */
export function useCourseListing() {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: courseKeys.list(),
    queryFn: () => getCourses(),
  });
  return { data, isLoading, isError, error };
}
```

Rules:

- Query key factory in `src/lib/api/query-keys.ts` must exist before writing service hooks
- Always expose `{ data, isLoading, isError, error }`
- `staleTime`/`gcTime` set globally in `providers.tsx` — per-query overrides require a comment

### 5.3 Data Flow Rule

```
Component → service hook (src/hooks/api/) → generated hook (src/lib/api/generated/) → BE LMS
```

Components must not import from `src/lib/api/generated/` directly.

---

## 6. Environment Variables

| Variable              | Required | Description                                |
| --------------------- | -------- | ------------------------------------------ |
| `NEXT_PUBLIC_API_URL` | ✅       | Base URL for BE Learning Management System |
| `NEXT_PUBLIC_APP_URL` | ✅       | Public URL of this FE app                  |
| `RESEND_API_KEY`      | ✅       | Server-side transactional email (Resend)   |

Two env files, both gitignored: `.env.development` and `.env.production`. The committed
`.env.development.example` / `.env.production.example` templates hold no real values.

`scripts/env.ts` validates them — `bun env:init` scaffolds from the examples, `bun env:check`
verifies development, and `bun dev` / `bun build` run the check automatically (build uses
`--soft` so CI can build without a live BE). Never commit secrets.

---

## 7. Infrastructure

### 7.1 Deployment

Docker 3-stage build → GHCR → Dokploy webhook. Dokploy builds from git source, so the deploy
trigger fires in its own job rather than waiting on the image push.

Build args required: `NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_APP_URL`.

Dev server port: **3000**.

### 7.2 CI/CD

| Trigger                          | Workflow              | What it does                                                                                                                                                   |
| -------------------------------- | --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PR → `dev` or `prod`             | `quality-gate.yaml`   | Runs `.github/scripts/quality-gate.sh` — format/lint, type-check, security, tests, production build. `CI=true` makes an unrunnable check fail rather than pass |
| PR → `dev`, or `/ask-deepseek`   | `deepseek-review.yml` | AI review comment. `dev` only — a `dev → prod` diff re-adds the stripped AI config and exceeds GitHub's diff limit                                             |
| PR → `dev`/`prod`, push → `prod` | `react-doctor.yml`    | React security/perf/a11y/architecture checks — advisory, never fails                                                                                           |
| Push → `prod` (merged)           | `ci-cd.yaml`          | Dokploy deploy trigger + Docker build/push to GHCR + docs changelog                                                                                            |
| PR closed → `prod`               | `strip-ai-on-pr.yml`  | Remove AI config files from the prod branch                                                                                                                    |

`dev` is the review gate; `prod` re-runs the gate as a promotion safety net.

### 7.3 Local Commands

| Command                             | Purpose                                       |
| ----------------------------------- | --------------------------------------------- |
| `bun dev`                           | Dev server on port 3000 (env-checked)         |
| `bun dev:prod`                      | Dev server against `.env.production`          |
| `bun fl`                            | Format (oxfmt) + lint (oxlint) — quality gate |
| `bun type-check`                    | `tsc --noEmit` — quality gate                 |
| `bun test` / `:coverage`            | Vitest (80% coverage minimum)                 |
| `bun check:i18n`                    | en ↔ id translation key parity                |
| `bun generate:api`                  | Regenerate the Orval client                   |
| `bun sync:rules` / `sync:workflows` | Re-sync shared `.agents/rules` and workflows  |
