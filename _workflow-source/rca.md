---
description: Reproduction-first debugging. Reproduces the bug at the lowest rung that shows it, finds the line that causes it, and fixes it with a test that fails without the fix. Ends with the fix and its test uncommitted in the working tree; no commit, no push.
---

<!-- Command: /rca [symptom] -->
<!-- Source: _workflow-source/rca.md -->
<!-- A prompt that says /debug means this command. -->

# /rca — Root Cause, Reproduction First

**Symptom:** $ARGUMENTS

A fix without a reproduction is a guess that happens to compile. This command reproduces first,
then finds the cause, then fixes it with a test that fails without the fix. It ends with the fix
and its test in the working tree, uncommitted: committing is `/ship`'s job.

---

## Step 0 — Check the stack

Before reading any code, confirm that everything the symptom passes through is up: the database and
cache answer (with the tunnel running, if the project uses one; see `.claude/DATABASE.md`), the dev
server responds, and each backend's health endpoint returns 200. If the repo ships a script that
checks these, run it first.

A symptom that passes through a service that is down or not running is not a code bug yet: say so,
get the service up, and check whether the symptom survives. Never point the app at a different
database, cache or backend to make a symptom go away.

Then scan `.claude/anti-patterns/INDEX.md` for the symptom's keywords: the trap may be recorded.

---

## Step 1 — Reproduce at the lowest rung that shows it

- **L0 — a unit test**, in the repo's own test runner. Shows logic: hooks, handlers, services,
  parsers.
- **L1 — no sign-in.** In a frontend, a page that only the dev server serves (for example a
  `page.dev.tsx` that `next.config` includes in `next dev` only), never a page production would
  ship. In a backend, a route test against the app in process. Shows rendering, layout, a route's
  contract.
- **L2 — the real screen**, signed in as a test account the user created for this. Shows the whole
  path, browser to database.
- **L3 — no reproduction.** Evidence from what already happened. Shows one past occurrence.

Rules for climbing:

- Start at L0 and climb only when the rung below cannot show the bug. Say why each skipped rung
  could not: "jsdom has no layout" is a reason; "it is faster in the browser" is not.
- A layout or visual bug is reproduced in a browser (L1 or L2), measured with the DevTools protocol
  or computed styles, never read off a screenshot.
- **L2 needs the user once.** The signed-in browser state is theirs to create: ask with the exact
  steps, and gather L3 evidence while waiting. Never sign in with the user's own account, never ask
  for a password in the conversation, never print a test account's credentials.
- **L3 reads only.** The response's request id leads to the service's log (read through the deploy
  platform) and to `SELECT`s on the dev or production database (`.claude/DATABASE.md`: production
  is read-only). Nothing at L3 writes, redeploys or restarts.

A claim is only as strong as the rung it was reproduced on. At L3, every conclusion carries the
label **not reproduced — hypothesis**, and ends with the one step that would confirm it, for the
user to run.

---

## Step 2 — Find the cause

1. **Instrument, don't theorise.** Log or inspect the data at each boundary it crosses: request,
   handler, service, query, response, hook, component. Name the first boundary where it is wrong.
2. **The cause is where it goes wrong, not where it shows.** Ask why until the answer is a line of
   code or config that can change. A cause that is "timing" or "sometimes" is not found yet.
3. **Check the evidence against the cause.** Every observed symptom must follow from it; one that
   does not means a second cause, or the wrong one.

---

## Step 3 — Fix it, and prove the fix

1. **Test first, at the lowest rung that holds it.** Even a bug reproduced at L2 usually has an L0
   form. Run it: it must fail, and for the reason Step 2 found.
2. **Smallest change that removes the cause.** No refactor rides along; offer one separately.
3. **Prove the pair.** The test passes with the fix. Revert the fix: it fails. Restore the fix.
4. **Remove the instrumentation**, then run the gates in CLAUDE.md § Quality Gates until they pass.

A bug that reached only L3 gets no speculative fix: report the hypothesis and its confirming step.

---

## Step 4 — Check the siblings

- A frontend bug: find the components that play the same role elsewhere in the app, and in any
  sibling app built from the same conventions, and check whether they share the cause.
- A backend bug that touches a contract (a response shape, an error code, a schema): check its
  consumers, the apps and services that call this API or read this schema.

Report each sibling as affected or not affected. Fixing one is a separate step the user approves.

---

## Step 5 — Report, then stop

1. **Symptom** and the rung it was reproduced on.
2. **Cause**, as `file:line`, with the evidence that ties it to every symptom.
3. **Fix** and **test**, with the fail-before and pass-after runs.
4. **Siblings**, each affected or not.
5. **Not verified**: anything checked only in jsdom, anything not seen in a browser, every L3
   hypothesis. Mark each claim measured or inferred.

Then stop. No commit and no push; the user runs `/ship` when they want the fix shipped.
