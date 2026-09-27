# A parity guard that compares a proxy sees nothing

**Applies to:** Any two renderers held to the same layout: a route `loading.tsx` against the screen
it hands over to, a skeleton against the row it replaces, a ported component against its original
**Status:** Permanent (a property of what a test measures)

## Symptom

A defect is visible on screen, a test exists whose stated purpose covers exactly that defect, and
the test is green. Example: table columns drift between the column definitions and the shape list
the route placeholder reads, and every guard written for that drift passes.

## Root cause

The guards compare **stand-ins for the thing that matters**:

| Guard compares                | Why it is blind                                          |
| ----------------------------- | -------------------------------------------------------- |
| the `<td>` class names        | the class is on the cell; the drift is in its contents   |
| the count of skeleton nodes   | an actions cell and a text cell are both one bar         |
| a hand-written column fixture | it cannot see a drift in the real table's columns at all |

A 36px circle and a 16px text bar are indistinguishable under the first two metrics, and 20px apart
on screen.

## Fix

Compare the rendered output of one renderer against the other's **source of truth**, in the most
complete form available:

```tsx
/* the reference, rendered from the column definition alone */
const expected = (col: Column) =>
  render(<SkeletonCell shape={col.skeleton} align={col.align} actions={col.actions} />).container
    .innerHTML;

/* the real table, in its loading state */
expect(loadingCells(renderRealTable())).toEqual(columns.map(expected));
```

Comparing `innerHTML` is normally a smell. Here it is the point: shape, alignment and control count
are all in that string, and **a property nobody has thought of yet is covered the day it is
added**. Choose it when the assertion is "these two must be identical", not "this looks about
right". Render the real component, never a fixture that resembles it.

## The discipline that prevents this

**Prove the guard red before trusting it.** Revert the fix, run the test, watch it fail with a
message that names the real defect, then restore the fix. A parity test written after the fix and
never seen failing asserts that the current code equals itself.

## How to catch it

When a test is green and the defect is visible, read what the test compares before reading anything
else, and check whether it renders the real component or a stand-in.

## Scope

Every parity or snapshot-style guard. [bodiless-request-is-an-empty-stream.md](bodiless-request-is-an-empty-stream.md)
is the same family on the server side.
