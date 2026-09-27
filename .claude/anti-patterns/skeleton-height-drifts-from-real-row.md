# A skeleton's height drifts from the component it replaces

**Applies to:** Any loading skeleton pinned to a real component's height (optional module:
`.claude/rules/web/skeletons.md`)
**Status:** Permanent (each trap below is CSS or process, not a bug to wait out)

A skeleton exists to stop layout shift, so one with the wrong height is worse than none: it moves
the page twice instead of once, silently. Every trap below produces a skeleton that looks right on
its own and disagrees with the component it stands in for.

## Symptom

The skeleton looks correct, and the page still jumps a little when the data lands, often by the
same small amount per row, scaling with the row count. Or a bar pokes past its card, only at narrow
widths and only in the skeleton.

## Trap 1 — a font-size utility may or may not set a line-height

Tailwind's **named** sizes ship a paired line-height; **arbitrary** ones do not.

| Class           | font-size | line-height             | one line box |
| --------------- | --------- | ----------------------- | ------------ |
| `text-2xl`      | 24px      | 2rem (from the utility) | **32px**     |
| `text-[24px]`   | 24px      | inherited `1.5`         | **36px**     |
| `text-[11.5px]` | 11.5px    | inherited `1.5`         | 17.25px      |

The inherited `1.5` is preflight's `html { line-height: 1.5 }`. Two cards whose markup reads as
identical, one with `text-2xl` and one with an inline `fontSize: 24`, differ by 4px per heading.

**Fix:** never carry a line box from another component or project. Recompute it as font-size × the
line-height that element actually resolves, and check whether the utility supplied one.

## Trap 2 — sizing from the richest branch when the data never takes it

A row component has two shapes: a completed row with a status badge that sets the title row's
height, and a pending row without one. The skeleton is derived, correctly, from the completed
shape. The store seeds an empty list, so until the first item completes every visible row is the
pending shape, a few pixels shorter.

**Fix:** before pinning a height, read what the store or fixture actually seeds and size against
the branch that renders in the state the screen reaches (rule S4). A component with two row shapes
needs the common one, not the tallest.

## Trap 3 — `max-width: 100%` does nothing inside a centred column

Below a breakpoint a header stacks and centres (`align-items: center` / `justify-items: center`),
so its column shrinks to its widest child. A bar with `width: 340px; max-width: 100%` resolves 100%
against a column that is itself 340px wide, so the cap never engages and the bar runs past the
card. Real text does not show this: prose wraps, so its min-content is one word. Only a fixed-width
placeholder has a min-content as wide as its width.

**Fix:** stretch the column that holds the bars (`justify-self: stretch`, or `w-full` below the
breakpoint) and centre the bars inside it. Centring the column is the mistake.

## Trap 4 — derivations written from memory and never measured

A skeleton written with a tidy derivation comment beside every bar can still draw the component as
it was a month earlier: a list of options the screen no longer has, a line height the component no
longer uses, one-line hints where the screen wraps. When nothing measures it, the comments are the
only evidence, and they can be wrong.

**Fix:** read the component the screen renders before the first bar. Draw text that can wrap as the
real words with their ink hidden (the component's own muted variant), and let a measurement say the
skeleton is right, not the comment (rule S5).

**Signal:** a comment that names a number the component does not contain, or a list in the
skeleton whose ids are not in the constants it stands in for.

## Trap 5 — a pair that only measures its taller column

A screen with a form column and a side rail: the form is taller at desktop widths, so a pair over
the whole body passes there while the rail is tens of pixels short. A pair's height is the taller
of two side-by-side columns.

**Fix:** give the shorter column a pair of its own, wrapped in the screen's layout class so it takes
the width the screen gives it.

## The method that holds

1. **Repeat the real component's box verbatim**: same padding, gap, border, margin classes. Then
   the only numbers you own are the text line boxes.
2. **Pin each bar to one line box**, derived as font-size × resolved line-height, with the
   derivation in a comment. A number with no derivation is unarguable and unmaintainable.
3. **Verify in the browser, not on paper.** Flip `IS_SKELETON_SHOWN` and read both boxes in
   DevTools at 375, 768, 1024 and 1440, or register the pair in a measuring harness where the repo
   has one. That is the only way the few-pixel drifts above get caught.
4. `1lh` (`h-lh`) makes a bar track its own typography where type is set by utilities; pin pixels
   with a derivation only where type is set inline.

## Scope

Every skeleton in the repo while the skeleton module is adopted. The rules are
`.claude/rules/web/skeletons.md`; the rationale is `.claude/docs/standards/skeletons.md`.
