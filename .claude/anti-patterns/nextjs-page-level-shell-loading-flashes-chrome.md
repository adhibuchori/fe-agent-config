# A shell rendered by `page.tsx` turns every `loading.tsx` into a chrome flash

**Applies to:** Next.js App Router apps with a signed-in shell (sidebar, top bar)
**Status:** Permanent (App Router Suspense semantics)

## Symptom

Adding a route `loading.tsx` makes the sidebar and top bar disappear into the placeholder on every
navigation, then reappear with the page. The placeholder itself looks correct. Sidebar state (an
expanded group, a scroll position) also resets on every navigation.

## Root cause

`loading.tsx` is the Suspense fallback for the whole `page.tsx` beside it. When the page renders the
shell (`<AppShell title=…>{content}</AppShell>`), the fallback stands in for the shell too, and each
page mounts a fresh shell, which is why its state resets.

The shell usually ends up in the page for one reason: the top-bar title is a prop, and only a page
knows it.

## Fix

Render the shell once, in the route group's `layout.tsx`, and derive the title from the path so
nothing has to be passed down:

- `(app)/layout.tsx` → `<AppShell user={user}>{children}</AppShell>`
- a `titleKeyFor(pathname)` helper in `src/lib/constants/`, read by the top bar through
  `usePathname`
- pages return content only; `loading.tsx` then replaces the content well and nothing else

Then assert the placement with a test that walks the route tree: every `loading.tsx` sits beside
its own `page.tsx`, never on a segment above it (rule S9 in `.claude/rules/web/skeletons.md`), because
an ancestor `loading.tsx` is a legal, silent fallback for every route beneath it.

## How to catch it

Before adding any `loading.tsx`, grep the page for the shell component. If the page imports it,
move the shell first.

## Scope

Every route group that owns persistent chrome.
