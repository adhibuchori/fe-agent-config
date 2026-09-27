# An inline `maxWidth` on `<dialog>` removes the browser's edge gutter

**Applies to:** Any native `<dialog>` given a width or height cap
**Status:** Permanent (user-agent stylesheet behaviour)

## Symptom

Every dialog is fine on desktop and runs edge to edge on a phone, touching both sides of the
screen. Nothing in the dialog's own code mentions the viewport. A tall dialog also runs under the
mobile browser's address bar and bottom toolbar.

## Root cause

The user-agent stylesheet gives a modal `<dialog>` `max-width: calc(100% - 6px - 2em)`, and the same
for `max-height`. That is the gutter. A design width passed as `maxWidth: 440` does not add to it; it
**replaces** it. Below 440px nothing caps the dialog any more, and `width: 100%` fills the screen.

The height side is the same trap on the other axis: without a `max-height` of its own, a tall dialog
is taller than the visible viewport.

## Fix

Cap by the viewport as well as the design width, and do it in the stylesheet (see
[jsdom-min-in-inline-style-breaks-getbyrole.md](jsdom-min-in-inline-style-breaks-getbyrole.md) for
why not inline):

```css
dialog.app-modal {
  max-width: min(var(--modal-max, 360px), calc(100% - 32px));
  max-height: calc(100dvh - 32px - env(safe-area-inset-top) - env(safe-area-inset-bottom));
  overflow-y: auto;
  overscroll-behavior: contain;
}
```

`dvh`, not `vh`: on a phone `100vh` is the height with the toolbars retracted. The same mistake on
an app shell (`height: 100vh` with `overflow: hidden`) hides its bottom edge.

## How to catch it

Anything that sets a width or height cap on `<dialog>` without a `min()` or `calc()` against the
viewport. Check at 375px with the device toolbar, not by shrinking a desktop window.

## Scope

Every dialog, drawer and sheet built on `<dialog>`. The responsive rules are
`.claude/rules/web/responsive.md`.
