---
paths:
  - '**/*.tsx'
  - 'src/messages/**'
---

# DESC — Dialog Description Standard

Every dialog states what it is about, in words the title did not already say, and that statement
is announced. Enforced by `bun run check:dialog-desc` in pre-commit and the quality gate — it
blocks. Background, worked examples and sources: `.claude/docs/standards/dialog-content.md`.

Optional module: a repo that does not adopt it deletes this file, its standard and its
`gates.list` line together.

## Rules

1. Every dialog has a title **and** a description, wired through `aria-labelledby` and `aria-describedby`. The only exception is rule 8.
2. The description states the consequence of the confirm button; the title already asked the question.
3. Banned openers: `Are you sure`, `Warning!`, `Please note`, `Oops`, `Sorry`, and `This action cannot be undone` as a sentence of its own.
4. Name the object: interpolate `{name}`, `{email}`, `{project}`. Never "this item".
5. For anything destructive, say what is **not** affected.
6. One or two sentences, ≤200 characters, sentence case, ending in a full stop, never identical to the title.
7. Buttons are verbs that match the consequence: `Ban account`, not `OK`.
8. Opt out only explicitly, when the body is structure a flattened announcement would destroy (a table, a list, several paragraphs):
   `{/* desc-exempt: <why> */}` directly above the dialog. Silence is not an opt-out.

## Naming and wiring

- Description keys end in `Description` — never `Desc`, never `subtitle`; the check finds them by name.
- The dialog hook returns `descriptionId` beside `titleId`, and the shared dialog components wire it once a `description` is passed.
- A dialog built by hand passes `description` and `descriptionId` to its header, or keeps its own `<p id={descriptionId}>`.
- Both ids come from `useId()`, never a module-level constant: a dialog mounted twice would emit duplicate ids.

Shape to copy: `"{name} ({email}) will be signed out and blocked from signing in again. Their past
invoices are kept."`
