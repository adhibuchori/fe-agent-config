---
description: Separation of Concerns audit — run the gates, then move what they find out of the presentation layer into hooks, lib and the constants homes.
---

<!-- Command: /review-soc [path] -->
<!-- Source: _workflow-source/review-soc.md -->
<!-- Run before a commit that touches components, or when a screen has started to feel heavy -->

# /review-soc — Separation of Concerns Audit

The binding rules are `.claude/rules/web/separation-of-concerns.md` (SOC, S1–S11) and `AGENTS.md`
Rules 6, 7 and 32. This command runs them, then decides what to do with what they report. Do not
audit by reading the diff and judging: a category with no command is a category nobody checks.

---

## 1. Run the gates

```bash
bun run check:soc        # S1–S11: state, refs, helpers, dates, reshaping, browser, await, handlers, literals
bun run fl               # includes the no-restricted-imports layer boundaries in oxlint.json
bun run type-check
bun run check:hooks      # hook placement and the src/testing/ mirror, which is where a fix must land
bun run check:reexport   # a move is never finished with a re-export
bun run check:tailwind   # canonical classes, dead classes, conflicting classes
```

`check:soc` prints a per-category count after the findings. Use it as the worklist and quote it in
the report: the shape of the count says more than the total does. A repo with no `src/components/`
has no presentation layer to audit; `check:soc` says so and exits 0.

## 2. Triage each finding

Every finding names a destination. Take it; do not invent a third place.

- `react-state-in-component` (S1) → `useFlag()` / `useDisclosure()` for a boolean; otherwise a
  named hook, one per concern.
- `unbound-ref` (S2) → the hook that owns the behaviour the ref was bookkeeping for.
- `function-in-component-file` (S3) → `src/lib/`, called by the hook; not a second component file.
- `date-logic` (S4) → `src/lib/`, with the time zone in one place.
- `data-reshaping` (S5) → `src/lib/` as a pure function, called from the hook that fetched the
  data.
- `browser-api` (S6), `async-in-component` (S7) → a named hook that also owns the cleanup.
- `compound-domain-condition` (S8) → `src/lib/` as a named predicate (`canEditPost(post, role)`),
  so two call sites cannot drift apart.
- `handler-in-component` (S10) → one named action on the hook that owns both steps; the JSX binds
  it.
- `domain-literal-comparison` (S11) → the `LiteralMap` constant in `src/lib/constants/<domain>/`.
- `no-restricted-imports` on a component → a view model in `src/types/`, mapped in the hook.
  **Never a re-export.**
- State that unrelated components share → a store in `src/store/`, read through a named hook
  (Rule 8). Server data never goes there: it belongs to TanStack Query.

## 3. Placement will block you if you get it wrong

`.claude/rules/web/file-organization.md` is enforced by `check:hooks`:

- Nothing loose in `src/hooks/` — no hook, and no barrel (`check:reexport` refuses re-exports).
- `src/hooks/` mirrors `src/components/`, app namespace included.
- `src/testing/hooks/` mirrors `src/hooks/` exactly, in the same commit. An orphaned test stops
  running without failing anything, so count test files before and after.
- Hook filenames are globally unique; the docs generator keys on the basename.
- One JSDoc block per export, in the form `.claude/rules/typescript/conventions.md` gives.

## 4. What is not a violation

Check these still pass after a fix. A gate that forbids the normal way to write a component is a
gate people route around:

- `.map()` whose callback returns JSX. Mapping to render is rendering.
- A ternary choosing between two values the hook already returned.
- `cn()` / `cva()` composing classes.
- A `useRef` passed to a JSX `ref=` in the same file.
- A presentation prop compared to a literal (`layout === 'grid'`): only a `src/types/` union is a
  domain value.
- `transition-colors duration-200`, `text-sm leading-relaxed`: a utility overriding another
  utility's default is the documented Tailwind idiom, not a conflict.

## 5. Report

```text
## Status: {LGTM | Requires Changes | Blocked}

### check:soc
{the per-category count, verbatim}

### Moved
- {file} → {destination} ({which S rule})

### Left in place, with reason
- {file}:{line} — {why it is presentation, not logic}

### Exemptions added to scripts/check/soc.allow.json
- {path} / {check} — {reason}. "Pre-existing" is not a reason.

### Gates
{one line per command in step 1, pass or fail, verbatim}
```

Stop and ask rather than guessing when a fix would change rendered output, when a finding sits in
generated code, or when the destination does not exist yet and inventing it would create a layer.
