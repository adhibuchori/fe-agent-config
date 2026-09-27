# A revoked session keeps working until its cookie cache ages out

**Applies to:** Better Auth with `session.cookieCache` enabled on the backend, and the frontend's
"session ended" flow
**Status:** Permanent (how a signed cookie cache works)

## Symptom

Every session of an account is revoked (or the user is banned). The "session expired" dialog
appears, but its **Sign in** button leaves the person on the dashboard. A minute later it works.

## Root cause

Two things combine:

1. **The cookie cache answers `getSession` from a signed cookie and consults no store.** A deleted
   session or a ban stays valid for the cache's `maxAge`, both in the API's guard and in the
   frontend's server-side session read.
2. **The dialog sends the person to a bare `/login`.** The dead cookie is still in the browser, and
   a proxy that only checks that a session cookie is present bounces `/login` straight back.

## Fix

- Backend: `cookieCache: { enabled: false }` wherever revocation or bans must take effect at once.
  With sessions in a fast store the cost is one read per request. A shorter `maxAge` narrows the
  window; it does not close it.
- Frontend: acknowledging a session end goes to a login URL that is marked (for example
  `?session=expired`), and the proxy deletes every session cookie (the cache cookie too) on that
  mark. An ordinary "sign in" link stays unmarked, so it never deletes a live session's cookie.

## How to catch it

- Proxy half, with no real user: send a bogus session cookie and its cache companion to the marked
  login URL; the response must delete both.
- Cache half, with a probe account only: sign in, revoke its sessions, and request a protected page
  within the cache window. With the cache off, sign-in sets no cache cookie at all.

Never run the revoke step against an account someone is using.

## Scope

Every repo that reads Better Auth sessions, backend and frontend. Related:
`session-rows-are-a-mirror-not-the-session.md` (backend).
