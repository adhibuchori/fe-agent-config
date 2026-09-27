> Rationale and worked examples behind `.claude/rules/web/skeletons.md`, which holds the binding rules. Loaded on demand, never automatically.

# SKEL — Loading Skeleton Standard

A skeleton exists to stop layout shift. One whose height is wrong is worse than none: it moves
the page twice instead of once, and it does it silently. So the standard is about **height first**
and appearance second. The five ways a height drifts in practice, each with its fix, are in
`.claude/anti-patterns/skeleton-height-drifts-from-real-row.md`.

## The debug switch

The repo carries one constant, in one place, with one name:

```ts
// src/lib/constants/ui/skeleton-preview.ts
export const IS_SKELETON_SHOWN = false;
```

Flip it to `true` and the wired screens hold their loading state indefinitely, so the placeholder
can be compared against the real layout in DevTools without throttling the network. Flip it back
when you are done.

**It only holds screens that are wired to it.** It is not a global interceptor and cannot become
one — a module constant cannot reach a component that never reads it. Wiring a new skeleton to the
switch is part of building it (§ Wiring), not an optional extra. An unwired screen is silent about
being unwired: flipping the switch simply does nothing, which reads as a broken switch rather than
as a missing wire. So the first question when it "does not work" is which screens actually read it
— `grep IS_SKELETON_SHOWN src/` answers it in one line.

**It cannot reach a `loading.tsx` at all.** A route placeholder is a Suspense fallback the router
chooses, not a component that reads a constant, so nothing this file exports can hold one on
screen. See § Route placeholders for how to verify one instead.

**Flipping it must not redden the suite, and that takes a mock rather than good intentions.**
Asserting the constant's _type_ instead of its value is necessary and nowhere near sufficient: a
wired screen held on its placeholder fails every test that reads its loaded state, and
`IS_SKELETON_SHOWN ||` short-circuits straight through a 100% branch threshold. So the vitest
setup file pins the module to the value that ships:

```ts
vi.mock('@/lib/constants/ui/skeleton-preview', () => ({ IS_SKELETON_SHOWN: false }));
```

A suite that wants the held branch mocks the module to `true` in its own file, which wins over the
setup one — that is how the skeleton branches are covered at all, since the shipping value makes
them unreachable. A repo without the pin turns `bun run test` and the coverage gate into noise the
moment anyone previews: a dozen screen tests failing for a reason unrelated to the change in hand,
which is how people learn to ignore red. Read the constant through `vi.importActual` in the one
test that is about the constant itself, or it becomes a statement about the mock.

**It must still be `false` on any branch that gets promoted.** The pin protects the suite, not the
build; `check:skeleton-switch` protects the build, in pre-commit and the quality gate.

## Height is derived, never guessed

**Rule S1 — repeat the real component's box verbatim.** Same padding, gap, border, margin and
radius, copied from the component the skeleton replaces. Then the container's geometry cannot
drift, and the only numbers you own are the text line boxes.

**Rule S2 — pin each bar to one line box, and write the derivation in a comment.** A line box is
`font-size × the line-height that element actually resolves`. A pinned number with no derivation
is unarguable and unmaintainable; the comment is what lets the next person check it in ten
seconds instead of re-measuring.

**Rule S3 — check whether the font-size utility supplied a line-height.** Tailwind's _named_ sizes
ship one; _arbitrary_ sizes do not and inherit preflight's `1.5`.

| Class           | font-size | line-height             | one line box |
| --------------- | --------- | ----------------------- | ------------ |
| `text-2xl`      | 24px      | 2rem (from the utility) | **32px**     |
| `text-[24px]`   | 24px      | inherited `1.5`         | **36px**     |
| `text-[11.5px]` | 11.5px    | inherited `1.5`         | 17.25px      |

This is why two identity cards from markup that reads as identical can measure 4px apart. Never
carry a line box between projects — recompute it.

**Rule S4 — size against the branch the data actually takes, not the tallest one.** A component
with two row shapes needs the common one. Read what the store or the first answer seeds before
pinning: a list that starts empty renders its empty-row shape, not the taller shape a filled row
computes to.

**Rule S5 — verify in the browser, never on paper.** Flip the switch, then read the element's box
in DevTools. Paper arithmetic is how a few-pixels-per-row error ships looking correct.

**Rule S6 — a skeleton is decorative.** `aria-hidden="true"` on the root. It stands in for content
that is not there; announcing its shape tells a screen-reader user nothing. Where the wait itself
needs announcing, that is a live region on the container, not on the bars.

**Rule S7 — derive against the component as the screen CONFIGURES it, not against the primitive
it wraps.** A field measures 43px plus a 5px gap plus a 24px helper row only while the helper row
is actually rendered. A wrapper that passes `suppressHelper` and pins its own height makes all
three numbers wrong at once, and the arithmetic still reads as careful because every term in it
was once true. Read the props the call site passes, then read the primitive. A toolbar reserved at
72px against a bare `Input`, on screens that all render a 44px search field, is 28px of error that
the right file would have prevented.

**Rule S8 — a box the screen stretches has no height to pin.** Where the real element fills its
container — `flex-1` in a well with a definite height — the placeholder is `flex-1` too. A number
derived from the element's content is correct at exactly one viewport height and wrong at every
other, and it will look right on the machine it was measured on. This is the one case where S2's
"pin it" is the wrong instinct: pin the bars, fill the container.

## One primitive, one height idiom

A skeleton follows its repo's styling idiom; pick one primitive for the repo and record it in
`SSOT.md` §5.

`h-lh` makes a bar track its own typography, so a font-size change moves bar and text together —
available from Chrome 133, Safari 16.4, Firefox 120. It suits a repo that sets type through
utilities. A repo that sets type inline has no utility to inherit from, so it pins pixels and
carries the derivation in a comment instead.

**Rule S12 — a bar bounded by a fixed neighbour pins pixels, even where bars use `h-lh`.** `h-lh`
earns its keep where the type it stands in for can move. It earns nothing in a cell whose height is
already decided by something that is not type — a 36px avatar, a 36px icon button — and there it
costs something instead: a bar free to grow with its own font size is one more candidate for the
row's height, so which element decides the row stops being answerable without measuring.

Bound those bars under the fixed element and the question closes. A table cell whose bars are `h-4`
over `h-3` with `gap-1.5` (34px) sits deliberately under a 36px avatar and a 36px icon button
beside it. Those two already agree, so every row measures 36px plus its padding and border
whatever the column holds — a number statable without opening DevTools, which is the whole return
on the constraint.

This does not soften S2. The derivation still goes in a comment; what changes is that it is
derived against the neighbour rather than against a line box.

Where several skeletons in one feature share bars, rows and headings, extract them into a
`*-skeleton-bits.tsx` beside the components rather than repeating the boxes. Files stay under the
150-line limit like any other.

## Wiring

Two shapes, both acceptable. Pick by where the loading state already lives.

**Through a hook's loading flag** — preferred when the screen already has one. The component keeps
one branch and the hook owns the decision:

```ts
isLoading: IS_SKELETON_SHOWN || !mounted || isSessionLoading,
```

```tsx
if (isLoading) return <ProfileViewSkeleton />;
```

**A wired screen reads the constant TWICE.** Almost every screen checks `isError` before it checks
`isLoading`, and some rethrow to an error boundary rather than rendering a panel. Either way a
failed request pre-empts the very placeholder the switch was flipped to look at, so the error
branch is suppressed alongside the loading one:

```ts
isLoading: IS_SKELETON_SHOWN || query.isLoading,
isError:  !IS_SKELETON_SHOWN && query.isError,
```

That second line is what makes the preview work with the API down — which is exactly when someone
is most likely to be studying a loading state. Omit it only where the screen has no error branch.

**As an early return** — for a screen with no async source yet. Read the constant in the component
and return the skeleton before anything else:

```tsx
if (IS_SKELETON_SHOWN) return <ProfileSettingsSkeleton />;
```

The second shape is a placeholder for the first. When the screen gains a real loading state, the
constant moves into that flag and the branch stays where it is.

Chrome around the content — a tab bar, a shell header — stays live while the panel shows
placeholders. It is navigation, not data, and leaving it interactive is what lets each tab's
skeleton be reached and compared.

## Route placeholders (`loading.tsx`)

A `loading.tsx` is a second, earlier placeholder. The router shows it while a route's payload is
still in flight — before the screen mounts, and therefore before the screen's own loading state
exists at all. The two run back to back on every visit, so a route placeholder is held to the
screen's placeholder as well as to the loaded layout.

**Rule S9 — a placeholder stands in for ONE page, so it sits beside that page's `page.tsx`.**
Placed on a segment above, it silently becomes the fallback for every route beneath it, and
nothing objects: an inherited `loading.tsx` is legal and quiet. A dashboard-shaped placeholder at
a route group's root paints four KPI tiles and a trend chart over every other page in the group —
correct on exactly one route. A stub whose whole body is a `redirect()` never paints and needs
none.

**Rule S10 — it is not the screen's loading state, and must not be a cruder copy of it.** The
screen's own state keeps whatever is already final — header labels resolved from i18n, a live tab
strip — and skeletons only what is still arriving. The route placeholder runs before any of that
exists, so it reserves the chrome as well. What the two owe each other is every BOX: same card,
same header, same column grid, same row height. Build it from the real parts wherever they can be
reached — the same `StatTileSkeleton` the screen renders, the same row and cell class strings the
table body owns — rather than from numbers copied out of them. One shared placeholder serving
several sections is the shape to avoid: the sections differ, so it is wrong for all but one of
them, and the one it fits is a coincidence.

**Rule S11 — a table placeholder repeats the column grid: widths AND alignment.** Widths alone
leave every bar on the left of columns whose content arrives centred, so the placeholder settles
sideways when the rows land. Pass the grid as data that both the table and the placeholder read;
a hand-copy in the placeholder is one edit away from disagreeing with the table it precedes.

**Verifying one.** The debug switch cannot hold a route placeholder (§ The debug switch), so S5
has to be satisfied another way: throttle the network in DevTools and navigate, or assert the
shared boxes in a unit test — two renders that agree on every class cannot lay out differently.
The test is the cheaper guard and the only one that still works after the branch merges.

**Enforcing S9.** The framework will not complain, so a repo that wants this held needs a test
that walks its own route tree: every `loading.tsx` has a `page.tsx` beside it, and every
non-redirect `page.tsx` has a `loading.tsx` beside it. Assert first that the walk found the routes
it expected — a filesystem test that matches nothing passes by vacuum.
