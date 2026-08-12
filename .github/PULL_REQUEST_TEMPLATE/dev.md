## Summary

<!-- What changed and why, in 1-3 sentences. -->

## How to Verify

<!-- Steps to confirm this works: pages/routes touched, manual checks run, screenshots if UI changed. -->

## Checklist

`bun fl`, `bun type-check`, `bun test:coverage`, and the production build are already
enforced automatically by `quality-gate.yaml` on every PR — not repeated here.

- [ ] Tests added/updated for changed hooks or utils
- [ ] No hardcoded UI strings — all user-facing text added or changed goes through
      `en.json` / `id.json`. Run `bun check:i18n` (it only catches key drift
      between locales that already exist, not a string that was never turned
      into a key) — also spot-check the diff by hand for string literals in
      JSX text, `aria-label`, `alt`, or `title` that aren't wrapped in `t()`
- [ ] Any new/changed `aria-label`, `alt`, or `title` is translated too — and does not
      silently override an already-correct, already-translated visible `<label>` or
      text with English
