> This file extends [common/coding-style.md](../common/coding-style.md) with web-specific frontend content.

# Web Coding Style

> File Organization and design token structure are project-specific. See SSOT.md §4.3 (folder structure) and §5 (design tokens) as the canonical reference.

## Animation-Only Properties

Prefer compositor-friendly motion:

- `transform`
- `opacity`
- `clip-path`
- `filter` (sparingly)

Avoid animating layout-bound properties:

- `width`
- `height`
- `top`
- `left`
- `margin`
- `padding`
- `border`
- `font-size`

## Semantic HTML First

```html
<header>
  <nav aria-label="Main navigation">...</nav>
</header>
<main>
  <section aria-labelledby="hero-heading">
    <h1 id="hero-heading">...</h1>
  </section>
</main>
<footer>...</footer>
```

Do not reach for generic wrapper `div` stacks when a semantic element exists.

> Naming conventions are defined in CLAUDE.md §Naming Conventions and SSOT.md §4.2 as the project authority.
