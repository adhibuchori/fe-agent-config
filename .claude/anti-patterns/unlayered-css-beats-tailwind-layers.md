# One unlayered rule beats every Tailwind utility

**Applies to:** Tailwind v4 plus any hand-written CSS in a global stylesheet
**Status:** Permanent (CSS cascade layers)

## Symptom

`<Skeleton className="size-9 rounded-full" />` renders a rounded **square** beside the circular
avatar it stands in for. `rounded-full` is in the class list, spelled correctly, on the element.

## Root cause

Tailwind v4 emits its utilities into `@layer utilities`. **Unlayered CSS wins against any cascade
layer, regardless of specificity.** That is what layers are for, and it is the opposite of the
intuition specificity trains.

```css
/* globals.css, unlayered */
.skeleton {
  border-radius: 8px; /* wins */
}
```

```html
<div class="skeleton rounded-full"><!-- loses, silently --></div>
```

Two single-class selectors, identical specificity, and the unlayered one wins every time. DevTools
shows `rounded-full` struck through only if you go looking for the winner.

## Fix

Put component CSS in the layer it belongs to, so utilities sort after it:

```css
@layer components {
  .skeleton {
    background: var(--skeleton-base);
    border-radius: 8px;
  }
}
```

Verify by reading the computed value back in the browser, not by reasoning about the cascade.

## The rule that follows

**A class meant to be overridden by utilities must be layered.** If a component takes a
`className` at all, it promises the caller can shape it, and only `@layer components` keeps that
promise. Leave a rule unlayered only when it must beat every utility, and say so in a comment: the
next reader will assume specificity.

## How to catch it

A Tailwind utility present in the DOM that has no effect, while a hand-written class in the global
stylesheet styles the same property. The winning rule's specificity looks equal or lower.

## Scope

Every hand-written rule in a stylesheet that also loads Tailwind. The opposite case, a utility that
is never emitted at all, is [tailwind-raw-var-without-theme-mirror.md](tailwind-raw-var-without-theme-mirror.md).
