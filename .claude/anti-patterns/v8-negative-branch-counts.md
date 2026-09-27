# v8 coverage reports a negative branch count for an `if` whose body exits

**Applies to:** `@vitest/coverage-v8`
**Status:** Tooling artifact: recheck after a major `@vitest/coverage-v8` upgrade

## Symptom

A 100% branch threshold fails on a file that is fully exercised, and the report shows an impossible
count for one `if`:

```text
src/lib/encode-image.ts   |   100 |   87.5 |   100 |   100 | branch counts [4, -1]
```

Both sides of the condition have tests. The negative number is the tell: a hit count cannot be below
zero, so this is not "a branch you did not cover".

## Root cause

v8 counts branches by subtracting the taken path from the enclosing block's total. When the `if` body
**leaves the block** (`return`, `continue`, `break`, `throw`), the implicit else has no range of its
own, so the subtraction runs against a total that already excluded the exits and can go negative.

```ts
for (const quality of LADDER) {
  const blob = await encode(canvas, quality);
  if (blob && blob.size <= CEILING) return blob; // ← implicit else is unattributable
}
```

## Fix

Restructure so both outcomes are values rather than one being an exit. Move the decision into a
helper that returns `null`, and let the caller branch on the returned value:

```ts
async function encodeWithin(canvas: HTMLCanvasElement, quality: number): Promise<Blob | null> {
  const blob = await encode(canvas, quality);
  return blob && blob.size <= CEILING ? blob : null;
}

for (const quality of LADDER) {
  const result = await encodeWithin(canvas, quality);
  if (result) return result; // a plain conditional over a returned value
}
```

**Do not reach for `/* v8 ignore */` here.** It would suppress a real measurement to work around a
counting bug, and it stays in the file after the bug is gone, silently hiding a branch that then
really is uncovered. A defensive branch nothing can reach is a different failure with ordinary,
non-negative counts: [unreachable-guard-vs-100-percent-branches.md](unreachable-guard-vs-100-percent-branches.md).

## How to catch it

A negative number in the report's uncovered-lines column, on a line whose `if` body returns,
continues, breaks or throws.

## Scope

Every file under the coverage threshold. After a major coverage-provider upgrade, check whether the
negative counts are gone; the helper is still the clearer code and stays either way.
