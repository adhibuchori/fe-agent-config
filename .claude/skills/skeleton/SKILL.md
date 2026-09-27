---
name: skeleton
description: Use when building, fixing or checking a loading skeleton or placeholder in this frontend, or when a skeleton is said to be off, to jump, or not to match its screen ("skeleton", "loading state", "placeholder", "layout shift", IS_SKELETON_SHOWN). Derives heights from the real component, wires the preview switch, and measures the pair at four widths until they differ by at most half a pixel.
---

# Skeleton

Optional module: this skill belongs to [the skeleton rule](../../rules/web/skeletons.md) and is
deleted with it when a repo does not adopt skeletons.

The binding rules are [that rule's S1–S16](../../rules/web/skeletons.md), which load once a skeleton
file is open. The derivations and worked examples are in
[the skeleton standard](../../docs/standards/skeletons.md), and the ways a height drifts in practice
are in [the skeleton-height anti-pattern](../../anti-patterns/skeleton-height-drifts-from-real-row.md).
This is the order of work, so the measuring happens before the claim, not after the complaint.

1. **Read the real component as the screen configures it** (S7): the props the screen passes, the
   branch the seeded data takes once every request has answered (S4), every box's padding, gap,
   border, margin and radius, and each text's `font-size × line-height`. A text that can wrap
   decides the height at phone width.
2. **Build the skeleton from those numbers.** Repeat each box verbatim (S1); pin each bar to one line
   box with its derivation in a comment (S2, S3, S12); give a stretched container no height (S8);
   wear the real component's class where it has one; `aria-hidden` on the root, and announce the
   wait on the live region (S6). Text that can wrap is the real words with their ink hidden (the
   component's own muted variant), never a bar pinned to one line. A whole screen whose data has
   not arrived is best drawn as that screen itself, muted, over stand-in data, so a block added to
   the screen is a block added to its placeholder.
3. **Wire the switch.** `IS_SKELETON_SHOWN` folds into the loading flag, never replaces it
   (S13–S16), and is `false` again before the work is committed.
4. **Measure the pair.** Where the repo has a measuring harness (a dev-only page rendering the real
   component from fixtures beside its skeleton, run by `bun run measure:skeletons`), register the
   pair there. Otherwise measure in the running dev server with Playwright or the DevTools protocol:
   the real component with its data loaded, then the skeleton with the switch on, reading each
   box's `getBoundingClientRect()` at 375, 768, 1024 and 1440 wide. A side-by-side layout measures as
   its taller column, so the shorter one (a rail) gets a pair of its own inside the screen's layout
   class.
5. **Measure until exact**, within 0.5px at every width. A difference is one of four things: a text
   that wraps on one side only, a box not repeated verbatim, a fixture in a different state from the
   skeleton's, or a pair measured at the wrong root. Fix the cause, not the number; sometimes the
   real component is what changes. To prove it on a screen behind sign-in, hold the request the
   loading flag waits on with Playwright's `page.route()` rather than flipping the switch in a shared
   checkout: one page load measures the placeholder, and releasing the request measures the answer.
6. **Report the table as measured**, per width, and name what was not measured: states other than the
   one S4 names, and any width that was skipped.
