> Rationale and worked examples behind `.claude/rules/web/dialog-content.md`, which holds the binding rules. Loaded on demand, never automatically.

# DESC — Dialog Description Standard

Every dialog states what it is about, in words that tell the reader something they did not
already know from the title, and that statement is announced to assistive technology.

Enforced by `bun run check:dialog-desc`, which runs in pre-commit and in
`.github/scripts/quality-gate.sh`. It blocks. There are no warning-only rules here.

## Why this exists

Two failures, and both are common in hand-built dialogs:

- Descriptions were written but never announced. A dialog built on the native `<dialog>` element
  with only `aria-labelledby` renders its description as a `<p>` with no `id`, so
  `aria-describedby` has nothing to point at — a screen reader announces the title and the focused
  control, and nothing else.
- Descriptions that existed were inconsistent — some stated consequences precisely, others were
  `"Are you sure you want to delete this note? This action cannot be undone."`, which restates the
  title and adds nothing.

## The rules

**1. Every dialog has one.** Title _and_ description, wired through `aria-labelledby` and
`aria-describedby`. The only exception is rule 8.

**2. State the consequence, do not ask for confirmation again.** The description says what will
happen when the confirm button is pressed. The title already asked the question.

**3. Banned openers.** `Are you sure`, `Warning!`, `Please note`, `Oops`, `Sorry`, and
`This action cannot be undone` as a sentence of its own. Material Design: _"Avoid apologies,
ambiguity, or questions, such as 'Warning!' or 'Are you sure?'"_. Irreversibility belongs inside
the consequence sentence, not bolted on after it.

**4. Name the object.** Interpolate `{name}`, `{email}`, `{project}`. Never "this item".

**5. Say what is _not_ affected**, for anything destructive. This is the most commonly missing
half, and the one that actually stops a mistaken click.

**6. Shape.** One or two sentences, ≤ 200 characters, sentence case, ending in a full stop. Never
identical to the title.

**7. Buttons are verbs** that match the consequence — `Ban account`, not `OK`.

**8. Opting out, explicitly.** The APG advises omitting `aria-describedby` _"if the dialog content
includes semantic structures, such as lists, tables, or multiple paragraphs, that need to be
perceived in order to easily understand the content"_ — announcing a flattened blob of a table is
worse than announcing nothing. For those, write:

```tsx
{/* desc-exempt: the body is a table of sessions; flattening it into one announcement
    loses the per-row structure the reader needs. */}
<Modal titleId={titleId} onClose={onClose}>
```

Silence is not an opt-out. A dialog with neither `descriptionId` nor a `desc-exempt` comment fails
the check.

## Naming

Description keys end in **`Description`**. Never `Desc`, never `subtitle`. The check finds
descriptions by name, so a key it cannot recognise is a description it cannot validate.

## Worked examples

|     |                                                                                                         |
| --- | ------------------------------------------------------------------------------------------------------- |
| ✅  | `"{name} ({email}) will be signed out and blocked from signing in again. Their past invoices are kept."` |
|     | Consequence, named object, and what survives. This is the shape to copy.                                |
| ✅  | `"The circle is what everyone else sees. Anything outside it is cropped away when you save."`           |
|     | States the irreversible part without a scare sentence.                                                  |
| ❌  | `"Are you sure you want to delete this note? This action cannot be undone."`                            |
|     | Banned opener, restates the title, and the second sentence is rule 3's exact case.                      |
| ❌  | `"Adjust reading comfort settings"`                                                                     |
|     | Fragment, no full stop, describes a category rather than a consequence.                                 |
| ❌  | `"Something went wrong. Please try again."`                                                             |
|     | Names neither what failed nor whether anything changed.                                                 |

## Implementation

Give the shared dialog hook a `descriptionId` beside its `titleId`, and let the shared dialog
components wire it, so any dialog built on them complies once it passes a `description`.

For a dialog built by hand, either pass `description` and `descriptionId` to its header, or keep
your own `<p>` and give it `id={descriptionId}`. Both are fine — the second is preferable when the
existing paragraph has its own type scale you do not want to change.

Both ids come from `useId()`. Never a module-level string constant: a dialog mounted twice would
then emit duplicate ids, and `aria-describedby` would resolve to whichever came first.

## Sources

- [W3C ARIA APG — Dialog (Modal)](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/)
- [Material Design — Dialogs](https://m2.material.io/design/components/dialogs.html)
- [NN/g — Confirmation Dialogs Can Prevent User Errors](https://www.nngroup.com/articles/confirmation-dialog/)
- [Apple HIG — Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
