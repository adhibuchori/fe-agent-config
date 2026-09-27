# React Doctor triage (`/react-doctor`)

Scan, decide what each finding is, fix the confirmed ones, prove the fixes, report. This workflow
edits the working tree only: it creates no branch, commit, pull request, label or issue. Committing
is a separate request (`/ship`, or the user's own). The outline follows the vendor's published
local-triage playbook; the text is this repo's own and is read here, never fetched.

Use one command for every step of a run, so every result comes from the same version and nothing
leaves the machine (`SKILL.md` § Keep scans local):

```bash
RD=(bunx react-doctor@0.9.14 --no-score --no-supply-chain)
```

## 1. Scope

Read `git status --porcelain=v1` first. Changes already in the tree belong to the user: never
overwrite, restore or reformat them.

| The user wants                  | Scope flags                                                      |
| ------------------------------- | ---------------------------------------------------------------- |
| What is uncommitted             | `--scope files --base HEAD --include-untracked`                  |
| What this branch changes        | `--scope changed --include-untracked --base <verified base ref>` |
| The whole project               | `--scope full`                                                   |

A scope the user names wins, even on a clean tree. Verify a base ref exists (`git rev-parse`)
before passing it.

## 2. Baseline

```bash
"${RD[@]}" --version                                             # must print 0.9.14
"${RD[@]}" --json --blocking none --yes <scope flags> > "$TMPDIR/rd-before.json"
```

- Stop if the version is not the pinned one, or the report's `schemaVersion` is not `3`, the shape
  this workflow reads. Read no other field first.
- The process may exit non-zero; parse the report anyway. It is usable only when it parses and
  `ok` is `true`. Otherwise report its error and stop.
- A scope with no supported source files is **skipped**, not clean. An empty diagnostic list is
  clean only when React was detected and nothing was skipped; otherwise report the scan as
  incomplete, with the reason.
- Run `bash scripts/check/gates.sh` before editing and write down every failing gate. A later
  failure counts against the edit only when it is new or worse.

## 3. Decide each finding

Read the diagnostics per project. An occurrence is a path, a rule key and a location; occurrences
that share a fix group get one root-cause fix.

For an unclear one, ask the tool rather than guessing:

```bash
"${RD[@]}" why <file>:<line>         # why the rule fired there
"${RD[@]}" rules explain <rule>      # the rule's rationale and its fix
```

Give every item exactly one outcome, with the evidence for it:

- **confirmed**: a real defect, fixed in step 4;
- **rejected**: a false positive, with the code that proves it;
- **needs evidence**: name what would settle it (a browser check, a profile, a measurement);
- **waived**: an exception the user authorised, scoped to that site; it is not a pass;
- **observation**: a preference, not a defect.

Design-tagged rules can be taste or real accessibility risk: never ship a taste change without the
user's decision. A performance finding is a hypothesis until it is measured; syntax alone never
proves slowness. Work confirmed errors first, then by security and correctness risk, never by count.

## 4. Fix

- The smallest change that removes the confirmed root cause, keeping behaviour, public interfaces,
  accessibility and the repo's rules (`AGENTS.md`).
- Never disable or suppress a rule to clear the report, and never add an `oxlint-disable`
  (Rule 28).
- React Compiler is active: do not add or remove memoisation without a measurement and a focused
  test (Rules 23-24).
- Touch `package.json` or the lockfile only when the confirmed fix is a dependency change.
- Undo only your own changes; never `git restore`, `git checkout --` or `git reset` in a tree that
  holds someone else's work.

## 5. Verify

A finding is fixed only when all of these hold:

1. A test covers the changed behaviour and fails without the fix.
2. `bash scripts/check/gates.sh` passes, apart from the failures written down in step 2.
3. A rescan with the same command and scope no longer reports it.
4. A scan of the affected files reports no new diagnostic in any category.
5. Any runtime, rendering, accessibility or performance claim has its evidence collected. Mark
   anything not collected **not run**; jsdom is not a browser.

## 6. Report

Leave the changes unstaged and report: the version and scope; the confirmed fixes; rejected
findings with their evidence; items still open and what would settle them; the diagnostic counts
before and after, by rule; files changed; checks run and checks not run.

Stop the run when the scan is incomplete or an edit would overlap the user's own changes.
Uncertainty about one item defers that item only; it never becomes a suppression, a fix or a pass.
