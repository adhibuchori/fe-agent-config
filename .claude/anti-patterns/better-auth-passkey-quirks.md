# Passkeys: a dismissed prompt is an error, and user verification is not enforced

**Applies to:** `@better-auth/passkey`, backend configuration and frontend cancellation handling
**Status:** Permanent until the plugin changes; re-check both items on every upgrade

## Symptom

1. Pressing Escape on the browser's own passkey prompt shows "Something went wrong" to someone who
   simply changed their mind. A unit test asserting "a dismissed prompt resolves with `undefined`"
   keeps passing: it encodes the assumption, not the library.
2. A security key with no PIN completes sign-in, and the session counts as two factors.

## Root cause

1. The client catches the WebAuthn abort and returns `{ data: null, error: { code: … } }` with a
   cancellation code (such as `ERROR_CEREMONY_ABORTED`), shaped exactly like a real failure. A guard
   written as `if (!result) return` never runs.
2. The plugin asks browsers for `userVerification: 'preferred'` and verifies responses without
   requiring user verification. A passkey is credited as two factors because the authenticator is
   unlocked by a biometric or a PIN; without that check it is possession only, silently standing in
   for two factors past any guard that trusts a "second factor enabled" flag on the user.

## Fix

1. Check the error `code` against a small list of cancellation codes before the generic error
   branch; keep the `undefined` check too, for versions that answer that way.
2. Configure `authenticatorSelection: { userVerification: 'required' }` for registration, and add
   the plugin's `afterVerification` hooks for registration and authentication that refuse a
   response whose `userVerified` is false. The server-side hook is the real gate: the
   authentication challenge may still ask for `preferred`.

## How to catch it

Log the resolved shape of a dismissed prompt once, on the installed version, before trusting a
comment about it. Test sign-in with a key that has no PIN: it must be refused.

## Scope

Every passkey flow, frontend and backend.
