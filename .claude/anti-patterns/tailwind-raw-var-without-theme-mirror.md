# A Tailwind v4 colour class can name a token that has no `@theme` mirror

**Applies to:** Tailwind v4 projects that declare colour tokens as raw custom properties in `:root`
and dark-theme blocks, and expose them to utilities through `@theme`
**Status:** Permanent (how Tailwind v4 resolves theme utilities)

## Symptom

A colour utility is spelled correctly, sits in the DOM, and styles nothing: no error, no lint
warning, no rule in DevTools to strike through. The element renders with its **inherited** colour.
Typical cases: a class copied from another project or another part of the app, a badge whose fill
and label colour vanish, a chip that is a plain outline in one theme.

## Root cause

The palette is declared twice:

```css
:root {
  --accent-soft: #e0e7ff; /* raw alias: what `var(--accent-soft)` reads */
}
@theme {
  --color-accent-soft: var(--accent-soft); /* mirror: what `bg-accent-soft` resolves against */
}
```

A utility resolves only against the `@theme` mirror. The raw alias can be present, correct and
themed, and `bg-accent-soft` still does not exist, so Tailwind emits no CSS for it. The class is not
wrong; it is wrong **in a stylesheet that lacks the mirror**.

An audit of which tokens lack a mirror fails the same way the bug does when the names are
**retyped**: a hand-typed list of "the colour tokens" leaves out whole families (`*-tint`,
`*-line`, `*-text`), and those are exactly the ones in use.

## Fix

Add the mirror, pointing at the raw alias so the utility follows the theme the alias follows:

```css
@theme {
  --color-accent-soft: var(--accent-soft);
}
```

Where the project's mirrors hold literal values instead of `var()`, give the new one its dark value
in the dark-theme block too, or the utility stops flipping with the theme.

Do not rewrite the class to `bg-(--accent-soft)` to get past it. That form works, and it is how the
theme vocabulary stops being shared: the next reader cannot tell which tokens the theme defines.

## How to catch it

`bun run check:tailwind` fails on a class that compiles to nothing (`AGENTS.md` Rule 33), which
catches a new use. To audit the stylesheet itself, derive the names from the file and never retype
them:

```bash
f=src/styles/globals.css
comm -23 \
  <(grep -oE '^\s*--[a-z0-9-]+:' "$f" | grep -v -- '--color-' | tr -d ' :' | sed 's/^--//' | sort -u) \
  <(grep -oE '^\s*--color-[a-z0-9-]+:' "$f" | tr -d ' :' | sed 's/^--color-//' | sort -u)
```

That prints every raw alias with no `--color-*` twin. Shadows, fonts, widths and animation tokens
in the output are fine; colours are the hazard. Pipe those names straight into a source grep for
`\b(bg|text|border|ring|fill|stroke|outline|decoration)-(<names>)\b`.

## Scope

Every Tailwind v4 stylesheet with raw aliases. The opposite failure, where the utility **is**
emitted and loses to an unlayered rule, is
[unlayered-css-beats-tailwind-layers.md](unlayered-css-beats-tailwind-layers.md). Tell them apart in
DevTools: absent here, present and struck through there.
