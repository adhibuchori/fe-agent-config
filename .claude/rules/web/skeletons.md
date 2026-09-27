---
paths:
  - '**/*-skeleton.tsx'
  - '**/*-skeleton-bits.tsx'
  - '**/loading.tsx'
  - 'src/lib/constants/ui/*-preview.ts'
---

# SKEL — Loading Skeleton Standard

A skeleton exists to stop layout shift: height first, appearance second. These are the binding
rules; derivations, failure stories and worked examples are in
`.claude/docs/standards/skeletons.md`.

Optional module: a repo that does not adopt it deletes this file, its standard, the `skeleton`
skill, the preview switches, `check:skeleton-switch` (and the measuring harness, where it was
added) and their `gates.list` lines together.

## The debug switch

- `IS_SKELETON_SHOWN = false` lives in `src/lib/constants/ui/skeleton-preview.ts`. Wiring a new skeleton to it is part of building it; `grep IS_SKELETON_SHOWN src/` shows which screens are wired.
- A wired screen reads it twice: `isLoading: IS_SKELETON_SHOWN || …` and `isError: !IS_SKELETON_SHOWN && …`, so a failed request cannot pre-empt the preview. A screen with no async source returns the skeleton early.
- A screen that gains a **new** waiting state wires the switch to that one too: the old wiring keeps holding the state it was written for, so the preview shows a placeholder nobody flipped it to see.
- The vitest setup pins the module to `false`; a suite covering the held branch mocks it `true` in its own file, and the constant's own test reads it through `vi.importActual`.
- It is `false` on every promoted branch; `check:skeleton-switch` refuses a commit where it is not.
- It cannot hold a `loading.tsx`: verify a route placeholder by throttling the network or with a shared-box unit test.
- A loader (a spinner, an animated figure) that stands in for a single fetch inside a screen reads its twin, `IS_LOADER_SHOWN = false` in `src/lib/constants/ui/loader-preview.ts`, under the same rules: folded into the flag, pinned `false` by the vitest setup, `false` on every promoted branch.
- An error state reads the failure twin, `IS_ERROR_SHOWN = false` in `src/lib/constants/ui/error-preview.ts`, under the same rules. It outranks the skeleton switch: `isError: IS_ERROR_SHOWN || (!IS_SKELETON_SHOWN && …)` and `isLoading: !IS_ERROR_SHOWN && (IS_SKELETON_SHOWN || …)`.

## Which state a screen shows

- **S13** A screen whose list is fetched shows the placeholder until the request answers, and reaches its empty state only on an empty answer. "Nothing yet" over a list still in flight tells someone who has data that they have none.
- **S14** The placeholder stands in for everything the answer decides, not only the rows: a banner that may not appear, and filter chips whose counts are unknown, wait with it rather than rendering empty and rearranging under the reader.
- **S15** A placeholder stands in for data that has not arrived, never for arriving. A screen opened from the menu with its data already cached renders at once: no skeleton, and no timed hold to make every screen feel alike. A list only that screen reads shows its skeleton on a first visit, not on a return inside the cache window; a list the shell already holds never shows one. A timed beat belongs only to an instant swap the reader asked for, a filter or a page.
- **S16** The loading flag covers every async source the placeholder stands in for, with `IS_SKELETON_SHOWN` folded into it, never used instead of it. A skeleton only the switch can reach, on a screen that fetches, never shows: the screen falls through to its empty state, which S13 forbids. The switch alone is right only where everything the screen renders is already in hand: a server-passed session, device settings.

## Height is derived, never guessed

- **S1** Repeat the real component's box verbatim: padding, gap, border, margin, radius.
- **S2** Pin each bar to one line box (`font-size × resolved line-height`) and write the derivation in a comment. Text that can wrap is not a bar: draw the real words with their ink hidden (the component's own muted variant).
- **S3** Tailwind's named sizes ship a line-height; arbitrary sizes (`text-[24px]`) inherit 1.5. Never carry a line box between projects.
- **S4** Size against the branch the seeded data takes, not the tallest one, in the state the screen reaches once every request has answered: a live count that includes the viewer shows 1, never the empty header before the first poll lands.
- **S5** Verify in the browser, never on paper. Where the repo ships a measuring harness (`src/app/[locale]/dev/measure/page.dev.tsx`, run by `bun run measure:skeletons`), register the skeleton there beside its real component, fed the state S4 names; it fails over 0.5px at 375, 768, 1024 and 1440. Elsewhere, look with the switch on. A derivation comment is not a measurement. A harness that compares heights only passes a hand-built row of bars at 0px with every x and width off, so a fixed-height row (a header, a toolbar) is the real component drawn muted, not bars placed by eye.
- **S6** `aria-hidden="true"` on the root; announce the wait on the container's live region. `inert` also takes the placeholder out of hit testing, so the devtools picker lands on its parent: where the muted part draws no reachable control, mute it without `inert`.
- **S7** Derive against the component as the screen configures it (the props it passes), not against the primitive it wraps.
- **S8** A box the screen stretches (`flex-1`) has no height to pin: pin the bars, fill the container.
- **S12** A bar bounded by a fixed neighbour (a 36px avatar or icon button) pins pixels under that neighbour, even where bars otherwise use `h-lh`; the comment derives against the neighbour.

Use the repo's one skeleton primitive and its height idiom: `h-lh` bars where type is set by
utilities, pinned pixels with a derivation comment where type is set inline. Bars shared across a
feature go in `*-skeleton-bits.tsx`. Files stay under the 150-line limit.

## Route placeholders

- **S9** A `loading.tsx` sits beside its own `page.tsx`, never on a segment above it. A `redirect()`-only page needs none.
- **S10** It is not a cruder copy of the screen's loading state: it reserves the chrome too, and shares every box with that state, built from the real parts.
- **S11** A table placeholder repeats the column grid — widths **and** alignment — from data the table itself reads.
- Enforce S9 with a test that walks the route tree, after asserting the walk found the routes it expected.
