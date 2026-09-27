# Writing both `backdrop-filter` forms can leave only the `-webkit-` one

**Applies to:** Stylesheets compiled by Tailwind v4, which runs Lightning CSS
**Status:** Toolchain behaviour; re-check after a Tailwind or Lightning CSS upgrade

## Symptom

A glass surface (a translucent fill with `backdrop-filter: blur(…)`) shows its tint in Chromium
browsers, but nothing behind it blurs. The source CSS looks right.

## Root cause

The source declared both forms:

```css
backdrop-filter: blur(16px);
-webkit-backdrop-filter: blur(16px);
```

Lightning CSS manages vendor prefixes itself and treats the pair as one property. In the observed
build it kept the prefixed declaration and dropped the unprefixed one, which Chromium ignores.

## Fix

Write the unprefixed property once and let the toolchain add `-webkit-` for the browser targets
that need it:

```css
backdrop-filter: blur(16px);
```

## How to catch it

A hand-written `-webkit-backdrop-filter` in a stylesheet, or a blur that "does nothing". Read the
compiled CSS before looking for a missing backdrop root: grep the build output for
`backdrop-filter` and count both forms.

## Scope

Any property Lightning CSS prefixes for you: write the standard form only.
