## Summary

<!-- What changed and why, in 1-3 sentences. -->

## How to Verify

<!-- The pages or routes touched, what a correct result looks like, and screenshots when the UI
     changed. "CI is green" is not a verification step. -->

## Checklist

`quality-gate.yaml` already ran the full gate on this PR. That file is the list; copying it here only
creates a second one to keep in step, and the copy is what goes stale. Nothing the gate decides is
repeated below — what follows is the part it cannot decide.

- [ ] No hardcoded UI text: every string added or changed in JSX, `aria-label`, `alt` or `title`
      goes through `t()`. The gate checks key parity between locales, not a string that was never
      turned into a key, so read the diff for literals by hand
- [ ] A new or changed `aria-label`, `alt` or `title` is translated too, and does not override an
      already-correct visible `<label>` or text with a different one
- [ ] A visual change was looked at in a browser at a phone width and a desktop width, and its
      loading skeleton still matches it (`.claude/rules/web/responsive.md`,
      `.claude/rules/web/skeletons.md`); jsdom measures no layout
- [ ] `.env.<target>.example` updated if a new env var was added, and `scripts/next/env.ts` still
      validates it

### If this PR regenerated the API client

Delete this block if `openapi.json` did not change.

- [ ] `openapi.json` is the backend's current copy, and `bun generate:api` was run from it
- [ ] Every new error code has a message in every locale (`check:error-codes` refuses the rest)
