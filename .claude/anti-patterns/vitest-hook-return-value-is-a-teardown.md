# A concise `beforeEach` arrow turns your mock into a teardown

**Applies to:** Vitest (and Jest, which has the same contract): any `beforeEach` / `afterEach`
written as a concise arrow whose expression evaluates to a function
**Status:** Permanent (the runner's documented hook contract)

## Symptom

```ts
beforeEach(() => fetchUsers.mockResolvedValue(PAGE)); // ← the trap
```

`expect(fetchUsers).not.toHaveBeenCalled()` then fails, reporting a call with **no arguments** that
nothing in the file makes. `mock.calls` reads `[[], [{ limit: 100 }]]`.

## Root cause

Every `mock*` setter (`mockResolvedValue`, `mockImplementation`, `mockReturnValue`) returns **the
mock itself**, for chaining. A concise arrow has an implicit return, so the hook hands that mock
back to the runner.

**Vitest treats a hook's return value as a teardown callback and calls it after the test.** So the
runner invokes your mock, with no arguments, and the call is recorded like any other.

## Fix

A block body. That is the whole fix:

```ts
beforeEach(() => {
  fetchUsers.mockResolvedValue(PAGE);
});
```

## Why it is worth an entry

The symptom points nowhere near the cause. A phantom zero-argument call reads as a leak from another
test, a stray import or an over-eager module mock, and all three are plausible enough to spend an
hour on. A rewrite that "fixes" it by switching setters usually changes the arrow to a block at the
same time, so the wrong explanation gets written down.

The stack trace settles it in seconds: the frame above the mock is the hook's own line, inside the
runner's teardown code, not any application code.

## Which concise hooks are safe

Only those whose expression is not a function:

```ts
beforeEach(() => vi.useFakeTimers()); // returns the vi object, not a function
afterEach(() => vi.clearAllMocks()); // same
```

The rule that needs no judgement: **a hook that sets up a mock gets a block body.**

## How to catch it

A `toHaveBeenCalledOnce` / `not.toHaveBeenCalled` assertion fails by exactly one call, and the extra
call's arguments are `[]`.

## Scope

Every test file under `src/testing/`.
