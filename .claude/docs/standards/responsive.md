> Rationale and worked examples behind `.claude/rules/web/responsive.md`, which holds the binding rules. Loaded on demand, never automatically.

# RESP — Responsive Layout Standard

A layout is responsive when the width it is read at is an input, not an assumption. A codebase
that assumed one width and never said which gets no warning when a screen breaks at another. This
standard names the breakpoints, says which values are allowed to be fixed, and makes the difference
checkable.

Enforced by `bun run check:responsive`, which runs in pre-commit and in
`.github/scripts/quality-gate.sh`. It blocks. There are no warning-only rules here.

## Why this exists

Three failures that tend to arrive together:

- **Breakpoint systems that do not know about each other.** Tailwind utilities at the stock
  640/768/1024, hand-written media queries at pixel literals `767`/`1023`/`640`, and `clamp()`.
  `767` happens to be `md - 1`, so they agree — by luck, not by construction. Nothing catches them
  drifting apart.
- **Responsive CSS with nobody to apply it.** Viewport media queries whose classes (`app-grid-4`,
  `app-stack-mobile`, `app-scroll-x`) have a rule and no element carrying them. The inverse exists
  too — a class applied in JSX with no CSS rule anywhere. Both are silent.
- **Overflow that looks fine.** `body { overflow-x: clip }` turns a broken layout into a quiet one:
  content is cut off instead of scrollable, so a screen that fails at 375px looks correct.

## The rules

**Rule R1 — Media queries read breakpoints by name, never as a pixel literal.**
`@media (width < theme(--breakpoint-md))`, not `@media (max-width: 767px)`. Tailwind v4 resolves
`theme()` inside a media condition — custom properties are invalid there, which is why `theme()`
still exists in v4. Range syntax is also more correct than the `max-width: N-1` idiom: `767px`
leaves a dead zone at `767.5px` under browser zoom, and `width < …` does not.

**Rule R2 — The `--breakpoint-*` tokens are declared in `@theme`, in rem.**
`40rem / 48rem / 64rem / 80rem` — the stock values, restated. This is functionally a no-op and that
is fine: its job is to give the numbers a name and to be the anchor R1 points at. Declare them in
rem, not px; mixing units across breakpoints corrupts Tailwind's utility sort order.

**Rule R3 — No class inside a width media query without a consumer in JSX.**
A responsive rule nobody applies is a claim the layout does not make. Delete it or wire it. This is
how a stylesheet comes to describe a phone layout that has never rendered.

**Rule R4 — No project-prefixed class in JSX without a rule behind it.**
The inverse of R3, and it fails more quietly: the element simply has no styling, and looks like a
spacing bug rather than a missing rule.

A rule may live in its own sheet under `src/styles/`, and the check reads every sheet that
`globals.css` `@import`s. A sheet it does not import fails the check instead of counting: it never
reaches the browser, so its classes would pass here and render unstyled.

**Rule R5 — An inline dimension of 200px or more carries a fluid guard.**
`width: 'min(300px, 100%)'`, not `width: 300`. Below 200px you are describing content — an avatar,
an icon, a hairline — and it should stay fixed. At or above it you are describing layout, and
layout that cannot shrink is layout that overflows. `maxWidth` is exempt at every value: a ceiling
cannot overflow anything.

**Rule R6 — A grid track of 280px or more is wrapped in `min()`.**
`repeat(auto-fill, minmax(min(330px, 100%), 1fr))`. Without the `min()`, a 330px floor inside a
300px container overflows rather than collapsing to one column. This single change is the
highest-value edit in the whole standard: it needs no breakpoint, no media query and no class, and
it fixes the card grid and its skeleton at the same time.

**Rule R7 — Every shell and screen root is responsive by some mechanism.**
Any of: a Tailwind variant, a class that a width media query reaches, or `clamp()`/`min()`/
`minmax()`/`vw`/`dvh`. Deliberately plural — a shell whose behaviour lives in CSS can be the most
responsive component in the repo and contain not one `md:`. A checker that only greps for prefixes
would call it broken.

**Rule R8 — A scroll container is the containing block of what it scrolls.**
Give every `overflow: auto` wrapper `position: relative`. An absolutely positioned descendant —
Tailwind's `sr-only` is one — resolves against its nearest positioned ancestor, not its nearest
scroller. With a static scroller it escapes the scroll, widens the document to wherever it sits, and
a phone zooms the whole page out to fit: a 1px label in a table's last column is enough to stretch a
phone-width page several times over. `body`'s `overflow-x: clip` does not stop it; mobile zoom reads
the document's scroll width, not what is painted. Not enforced by `check:responsive` — measure
`document.documentElement.scrollWidth` at a phone width over CDP.

**Rule R9 — A machine value is one line that scrolls sideways; it never wraps.**
Generated passwords, backup codes, tokens, keys: `white-space: nowrap`, `overflow-x: auto` with
the scrollbar hidden, and `min-width: 0` on the flex item so the scroll happens inside the row
rather than on the page. `break-all` is not a fix for overflow here — a secret broken across two
rows reads as two values, and the row's height starts depending on the length the reader picked.

## Converting a fixed value: decide by class and magnitude, not case by case

Do not weigh each number on its own — that is how two thousand declarations become two thousand
decisions. Find the property's class, then its magnitude.

| Class                                                       | ≤24  | 25–63             | 64–199            | ≥200                 |
| ----------------------------------------------------------- | ---- | ----------------- | ----------------- | -------------------- |
| **Inert** — `borderRadius`, `zIndex`, `marginTop`, `rowGap` | keep | keep              | keep              | keep                 |
| **Spacing** — `gap`, `padding`, `marginLeft`                | keep | keep              | `clamp()` from 32 | `clamp()`            |
| **Type** — `fontSize`                                       | keep | `clamp()` from 20 | `clamp()`         | `clamp()`            |
| **Dimension** — `width`, `minWidth`, `flexBasis`            | keep | keep              | inspect           | **`min(Npx, 100%)`** |
| **Cap** — `maxWidth`, `maxHeight`                           | keep | keep              | keep              | keep                 |
| **Grid** — `gridTemplateColumns`                            | —    | —                 | keep              | `min()` or a class   |

**Most of the corpus is left alone, and that is the point.** A 12px gap is 12px at 320px and at
2560px by design; converting it produces churn and no behaviour change. Shrinking a 13px label is
an accessibility regression, not a responsive win.

**Lift to a class only for three triggers.** The value must change at a breakpoint (`clamp()`
cannot say "three columns, then one"); the same literal appears three or more times across two or
more files, making it a token; or a skeleton must agree with its real component.

## Skeletons wear the real component's class

A skeleton pinned to a constant height is correct at exactly one width. When the real row rewraps,
the placeholder does not, and the page shifts on arrival — the failure the skeleton standard exists
to prevent, reintroduced one viewport over.

The fix is not a second set of media queries. Put the **real component's class** on the placeholder
and let it inherit every rule the real element has: a list skeleton that carries
`className="app-list-row"` instead of reproducing the row's geometry follows the viewport, including
rules written after the skeleton.

This does not soften the skeleton standard. Height is still derived and still commented; what
changes is that the derivation is inherited rather than transcribed.

## Drawers use `inert`, not a focus trap

A drawer that covers the page must take the page out of the tab order. Set `inert` on the content
behind it and on the panel while closed. Do **not** write a focus-trap hook: it is roughly sixty
lines of cycle, shift-tab and initial-focus branches, all of which land inside the 100% coverage
threshold on `src/hooks/**` — a day of tests for what the platform now does in an attribute.

Recorded here so the next person does not "fix" it by adding the trap.

## Testing: assert structure, never pixels

jsdom has no layout engine and `matchMedia` is stubbed to `matches: false`, so a test that claims
to measure a breakpoint is measuring nothing. Three things are real in jsdom and all three are
worth asserting: which class strings exist, which elements exist, which attributes are set.

- **Structural parity** — render the real component and its skeleton, assert the class strings
  match. Two renders that agree on every box cannot lay out differently.
- **Class contract** — the panel carries `.app-sidebar-panel`; `open` appears after the trigger is
  pressed. This is the honest way to test a media query here: it catches the regression that
  matters — someone deletes the class — without pretending to measure.
- **Hook behaviour** — every branch, because these hooks sit inside the coverage threshold. A
  `matchMedia` mock that actually dispatches `change` is required; a setup stub that returns a
  fresh `vi.fn()` per call can never fire a listener registered against it.

`mockWindowDimensions` is only for hooks that genuinely read `window.innerWidth`. Reaching for it
to test a CSS media query is how a test comes to assert nothing at all — changing `innerWidth` does
not re-evaluate a stylesheet in jsdom.

**What no jsdom test covers, stated plainly:** real overflow, computed widths, whether
`min(320px, 85vw)` resolves. That needs a browser — one manual pass at 320/375/768/1024 with
`overflow-x: clip` temporarily off, recorded in the PR body.

## Worked examples

|     |                                                                                          |
| --- | ---------------------------------------------------------------------------------------- |
| ✅  | `@media (width < theme(--breakpoint-md)) { .app-sidebar-panel { position: fixed } }`     |
|     | Named breakpoint, and the range form has no fractional dead zone.                        |
| ✅  | `gridTemplateColumns: 'repeat(auto-fill, minmax(min(330px, 100%), 1fr))'`                |
|     | Collapses to one column on its own. No breakpoint, no class, no media query.             |
| ✅  | `<div className="app-list-row">` on the skeleton                                         |
|     | Inherits every rule the real row has, including ones written after the skeleton.         |
| ❌  | `@media (max-width: 767px)`                                                              |
|     | Agrees with `md` by luck. Nothing catches it drifting.                                   |
| ❌  | `style={{ width: 300 }}` on a rail                                                       |
|     | Cannot shrink. At 375px it takes 80% of the viewport and the content gets what is left.  |
| ❌  | `.app-stack-mobile { … }` with no element carrying the class                             |
|     | A phone layout that has never once rendered.                                             |
| ❌  | `expect(el).toHaveStyle({ width: '300px' })` after `mockWindowDimensions(375)`           |
|     | jsdom applied no stylesheet. The assertion passes and means nothing.                     |

## The checker

`scripts/check/responsive.ts` reads every sheet through `scripts/lib/stylesheets.ts`. Change the two
together, in one commit. The class prefixes it treats as hand-written CSS (R3, R4) are the `OWNED`
list at the top of the checker: `app-` ships, so list your own there.
