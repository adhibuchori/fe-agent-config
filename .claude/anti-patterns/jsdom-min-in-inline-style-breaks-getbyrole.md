# jsdom throws on `min()` in an inline style, and every `getByRole` in that tree fails

**Applies to:** Any component rendered in a Vitest (jsdom) test whose inline `style` puts a CSS
math function on a length property
**Status:** Recheck after a major jsdom upgrade

## Symptom

A styling-only change turns component tests red with an error that names no CSS:

```text
TypeError: object null is not iterable (cannot read property Symbol(Symbol.iterator))
 ❯ resolveLengthInPixels  node_modules/jsdom/lib/jsdom/living/css/helpers/font-sizes.js
 ❯ window.getComputedStyle  node_modules/jsdom/lib/jsdom/browser/Window.js
 ❯ isSubtreeInaccessible  node_modules/@testing-library/dom/dist/role-helpers.js
```

The tests that fail assert nothing about style. Reverting only the style line makes them pass,
which is the fastest way to confirm this trap.

## Root cause

`getByRole` checks accessibility by calling `getComputedStyle` on every ancestor. jsdom resolves
length properties itself and cannot parse `min()` / `max()` / `clamp()` there, so it throws instead
of ignoring the value. Stylesheets are not loaded in the test environment, so the same expression
written in CSS is never seen.

## Fix

Keep the math in the stylesheet and pass only a plain value inline, through a custom property:

```tsx
<dialog className="app-modal" style={{ ['--modal-max' as string]: `${maxWidth}px` }} />
```

```css
dialog.app-modal {
  max-width: min(var(--modal-max, 360px), calc(100% - 32px));
}
```

This is also what `AGENTS.md` Rule 11 asks for: a value from props goes through `style`, and a CSS
custom property is the way to hand it over.

## How to catch it

A diff that only touches an inline `style` breaks tests that assert nothing about style, and the
stack runs through `getComputedStyle`. Grep the diff for `min(`, `max(`, `clamp(` inside `style={{`.

## Scope

Every inline length in a component that a jsdom test renders.
[dialog-inline-maxwidth-drops-ua-gutter.md](dialog-inline-maxwidth-drops-ua-gutter.md) is the usual
reason someone reaches for `min()` inline in the first place.
