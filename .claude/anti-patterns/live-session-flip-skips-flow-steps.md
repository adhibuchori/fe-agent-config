# A live session refetch skips the auth flow's own steps

**Applies to:** Any screen that derives its state from a live session hook (`useSession()` or an
equivalent that refetches after auth calls) and also hosts a dialog or a final acknowledgement,
on a route guarded server-side
**Status:** Permanent (the session is right, the guard is right; the combination is the bug)

## Symptom

In a multi-step setup flow (enabling a second factor, confirming recovery codes):

1. The dialog showing one-time recovery codes closes itself the instant the code verifies, before
   the codes can be copied.
2. With that fixed, "I have saved them" can still go straight to the dashboard. The "You're all
   set" state and its button never appear.

jsdom suites stay green throughout; it shows on a real device.

## Root cause

The auth client refetches the session after each auth call, so a flag such as
`twoFactorEnabled` flips to `true` **while the dialog is still open**.

1. A screen that derives "done" from the session returns the success state early, which unmounts
   the dialog in the middle of its last step.
2. A dialog close handler that calls `router.refresh()` re-runs the server-side page guard, which
   now sees nothing owed and redirects before the client can render its success state.

Each piece is correct alone: the session is the truth, and the guard is right to redirect. The
combination skips a step the user needed.

## Fix

- Hold the derived "done" while the dialog is open: `isDone = !owesStep && !isDialogOpen`, in the
  hook that owns the flow (`AGENTS.md` Rule 32).
- Never `router.refresh()` in a dialog's close handler on a guarded page. Refresh once, on the way
  out: the final button refreshes, then navigates.

## How to catch it

Mock the session hook through a mutable variable, open the dialog, flip the variable, `rerender()`,
and assert the dialog is still mounted. Then close it and assert that neither `router.refresh` nor
`router.push` ran before the final button was pressed. Both assertions must fail on the old code:
run them against it before trusting them.

## Scope

Every flow whose later steps change the session it reads.
