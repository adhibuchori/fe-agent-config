# A `position: fixed` pop-up inside a contained or transformed ancestor lands offset

**Applies to:** Any menu, popover or tooltip positioned with `position: fixed` from
`getBoundingClientRect()` and rendered inside a screen rather than portalled
**Status:** Permanent (CSS containing-block rules)

## Symptom

The pop-up opens offset from its trigger by exactly the size of the chrome around the screen: a top
bar's height below it, and a sidebar's width to one side when the sidebar is open. The coordinates
it was given are correct; logged, they match the trigger's rectangle.

## Root cause

`position: fixed` is relative to the viewport only while no ancestor forms a containing block for
it. `contain: paint` (or `layout`), any `transform` (an identity `translate(0)` left behind by an
entry animation counts), `filter`, `perspective` and `will-change: transform` all make that ancestor
the containing block. Viewport coordinates from `getBoundingClientRect()` are then applied from the
ancestor's corner.

## Fix

Portal the pop-up to `document.body` (`createPortal(node, document.body)`, or the portal target the
app's UI primitives already use). Removing the `contain` or the transform instead trades this bug
for the paint or animation behaviour they exist for.

## How to catch it

A `position: 'fixed'` element under `src/components/**` that is not inside a `createPortal`. In
DevTools, the offset parent of the misplaced element is the ancestor with the property, not `body`.

## Scope

Every floating element positioned from viewport coordinates. Library primitives that portal by
default (dialog, popover components) are safe; hand-rolled ones are where this appears.
