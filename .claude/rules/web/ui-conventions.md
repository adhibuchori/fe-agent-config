---
paths:
  - 'src/components/**/*.tsx'
  - 'src/app/**/*.tsx'
  - 'src/styles/**/*.css'
  - 'src/messages/*.json'
---

# UI — Conventions

How UI work is judged here. Taste that belongs to your product (colour meaning, motion budget,
density) goes in a section of its own at the end of this file.

## Measure, don't guess

- A screenshot localises a complaint; measure the element (CDP, computed styles) before any theory. Never read a colour off a scaled screenshot.
- Diff the computed values of the element **and** its container: "still a different colour" is often the ground, not the thing.
- A pixel value in a request points at an element: measure that element and use its real value (the button is 39.5px, not 39).
- Read the control's real label in `src/messages/*.json` before naming it in a diagnosis.
- Phone bugs: measure at phone size with `mobile: true`; `innerWidth` far above the viewport means the page zoomed out.
- An auth-gated component is reachable for CDP through a throwaway page that only `next dev` serves (`page.dev.tsx`); delete it in the same session.
- Lint and type-check never parse CSS. Prove a CSS change by compiling it or reading the inspector; a modifier written above its base rule loses on source order.
- Green gates say nothing about a visual change: name the surfaces the user should look at.
- A visual change to a component reports what its skeleton does, unasked: a skeleton that renders the real component muted follows it; one that copies the geometry needs the same edit.

## One component per role

- Every screen playing the same role (an empty list, a flow's final screen) uses the same component.
- A second renderer that produces the same pixels beside a shared primitive is a bug waiting to diverge.
- "Why does it look different?" can mean one side is unstyled: a fill of `rgba(0,0,0,0)` with a `currentColor` border is the tell.

## Components

- A native `<dialog>` modal keeps its children mounted while closed. Any field or toggle inside a step lives in state that the modal's close handler resets.
- An empty or error state component is for a region inside a page, never a flow's final full-page screen.
- A value that must flip per theme uses a shared token (`--surface-subtle`), never a token that only happens to be right in light mode.
- Waiting is a spinner, not "Loading X…" copy; the string stays as the spinner's `label`/`aria-label` in its live region.
- A toast is one actionable line; the title carries the what. Keep a toast rather than stacking a second dialog.
- Nothing moves under `prefers-reduced-motion`, and nothing animates on load.

## Copy

- Buttons are Title Case in every locale: capitalise every word except articles, conjunctions and prepositions of four letters or fewer, unless first or last. In Indonesian every preposition and conjunction stays lowercase (PUEBI), and a unit after a number stays an abbreviation; `check:i18n` refuses a button text that is not Title Case. Headings, descriptions, form labels, errors and `aria-label`s stay sentence case.
- Dates and times carry a label and a zone, formatted in the one date module with an explicit `timeZone`.
