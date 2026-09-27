# A smooth scroll started before a layout-shifting state change gets visually undone

**Applies to:** Any `scrollTo({ behavior: 'smooth' })` triggered by an event that also changes the
scrolled container's height (loading states, skeleton swaps, accordion/collapse toggles)
**Status:** Permanent (browser behavior, not a bug to fix upstream)

## Symptom

A "scroll to X on click" feature appears to do nothing, or scrolls partway and snaps back — even
though the click handler unambiguously calls `scrollTo`. Manual testing in isolation (calling
`scrollTo` directly, no state change alongside it) works fine, which makes the bug look
intermittent or environment-specific.

## Root cause

`behavior: 'smooth'` animates over several frames. If the container's `scrollHeight` changes
**while that animation is still running** — e.g. a skeleton placeholder swaps back to real content
with a different measured height — the browser's scroll position is computed against the new
layout, and the in-flight animation gets visually overridden mid-flight. The `scrollTop` value
read _after_ the animation settles can be correct while the _visual_ motion the user saw was
wrong, which is why this is easy to miss in a quick manual check and easy to catch by sampling
`scrollTop` at multiple timestamps.

A paginated card grid shows both ways to get the timing wrong:

1. `scrollTo` called synchronously in the pagination click handler, before React commits the next
   render. The grid's height changes twice in quick succession (real cards → skeleton → real
   cards), and the animation is still running when the second change lands.
2. Firing the call only **after** the skeleton settles avoids the race, but scrolls the page only
   after the loading placeholder has already disappeared — the opposite of the intended "scroll
   while loading" feel, since the skeleton and the final grid are the same height by design.

## Fix

Trigger the scroll in a `useLayoutEffect` keyed off the loading flag turning **true** (not false),
in the same frame the skeleton mounts — not synchronously in the click handler, and not after the
skeleton unmounts:

```ts
useLayoutEffect(() => {
  if (!isLoading) return;
  if (!shouldScrollOnSettle.current) return;
  shouldScrollOnSettle.current = false;
  scrollContainerRef.current?.scrollTo({ top: targetTop, behavior: 'smooth' });
}, [isLoading]);
```

This works only because the skeleton is deliberately pinned to the same height as the real content
(a shared `CARD_HEIGHT` constant used by both the card and its skeleton). The scroll target computed
against the skeleton's layout stays valid once the real cards swap back in, so nothing shifts
underneath the animation.

Also compute the scroll target with `getBoundingClientRect()` deltas against the _scroll
container's own box_, not `element.offsetTop` — `offsetTop` is relative to the nearest positioned
ancestor, which silently gives the wrong number the moment the target element sits inside an extra
wrapper `<div>` (two screens that share a grid but differ by one wrapper layer get different
`offsetTop` values for the same target, and only one of them is right).

## How to catch it

A single `scrollTop` read after the fact proves nothing — it can read correct even when the
animation was visually wrong. Sample it at multiple timestamps spanning the whole loading window
and check both the trajectory and the final resting value:

```js
// pseudocode: sample every ~100ms across the loading window, log alongside
// whether the loading/skeleton flag is still true
for (const t of [60, 150, 300, 450, 600, 1000]) {
  await sleep(delta);
  console.log(t, container.scrollTop, isSkeletonStillMounted());
}
```

A working animation shows a monotonic trajectory toward the target _while the skeleton is still
mounted_, settling before or as the skeleton unmounts. A broken one shows the value snap back
toward the pre-click position right around when the skeleton is replaced.

## Scope

Any "auto-scroll to X" paired with a loading/skeleton state. Pin the skeleton's height to the
real content's height first (as in the card example above) — without that invariant, this fix
doesn't apply and the layout-shift race is unavoidable by construction.
