# Better Auth's account endpoints are gated in ways the client does not show

**Applies to:** Account-security screens built on the Better Auth client: linked accounts,
sessions, passwords
**Status:** Permanent (deliberate library design; re-check on a major upgrade)

## Symptom

A settings screen works in development and fails for real users, in one of two shapes:

- **Works, then stops.** Unlinking a provider right after sign-in works; an hour later it answers
  `403 SESSION_NOT_FRESH`. Nobody meets this while developing, because developers test right after
  signing in.
- **Never works.** The client has no method for an endpoint that is server-only; setting a first
  password for an account that only ever used a social sign-in is the usual one.

## Root cause

Endpoints carry different guards, visible only in the library source: some take any session, some
require a *fresh* session (signed in within `session.freshAge`), and some are server-only and have
no client path at all. Listing linked accounts also strips the credential's password field, so the
list cannot answer "does this account have a password", which is exactly what an unlink guard asks.

## Fix

Wrap a gated endpoint in a backend route and call the server API (`auth.api.*`) from there. Read
state the endpoint cannot answer from the database through a repository; write through
`auth.api.*` wherever the library keeps its own state (sessions mirrored in a secondary store must
never be deleted by hand). Raising `freshAge` to make a client call work weakens every sensitive
operation; asking for the password first is stronger.

## How to catch it

Before designing a UI around a client call, read that route's middleware list in the installed
package (`node_modules/better-auth/dist/api/routes/`). A fresh-session middleware or a server-only
declaration means the browser path does not exist for the flow you are about to build.

## Scope

Every Better Auth plugin endpoint a UI calls directly.
