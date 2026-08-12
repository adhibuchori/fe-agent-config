# Rationale

Why the odd-looking parts of this configuration are shaped the way they are.

Every entry below is something that cost someone real time to discover. Several look like clutter
and are load bearing — this file exists so you can tell which is which before you tidy anything.

**One rule while reading: if a pattern here looks needlessly complicated, do not simplify it.**
Each one is followed by what breaks when you do.

---

## 1. Comma-separated globs in one string

Rule files that scope themselves to file patterns write the list as a single comma-separated
string:

```yaml
globs: '**/*.tsx, next.config.ts, src/middleware.ts'
```

A YAML list looks tidier. Change it, and the rule stops matching **any** file.

No error, no warning, nothing in the logs. The rule is simply never applied, and everything
continues to look normal. This is the archetype for the whole file: the failure is silent, and
silence reads as success.

---

## 2. `PreToolUse` blocks; everything else only complains

The single most important thing to understand about hooks.

| Hook | Non-zero exit means |
| --- | --- |
| `PreToolUse` | **The tool call does not happen.** This is a real guardrail |
| `PostToolUse` | Reported, then ignored. The write already landed |
| `Stop` | Reported, then ignored |

So a rule that must not be violated belongs in `PreToolUse`. Put it in `PostToolUse` and you get a
guard that appears installed, logs complaints, and prevents nothing.

**Corollary: test a guard by triggering it.** A guard whose path pattern does not match your
directory layout never fires and never complains. Reading the script tells you what it intends;
only triggering it tells you what it matches.

---

## 3. `--check` mode, and why write mode cannot replace it

Mirror scripts run in two modes. Only one detects drift:

```bash
bash scripts/sync-workflows.sh           # write
bash scripts/sync-workflows.sh --check   # verify — this is the CI mode
```

A write-mode run **overwrites staleness before it can observe it**. Run it in CI and the mirrors
are always in sync, because the check just fixed them. Three commands went unlisted for months
behind exactly that.

`--check` catches four distinct things, and each was added after the previous version missed one:

1. A target file that no longer matches its source.
2. An **orphan** — a target with no source. This is the direction naive checkers forget.
3. `INDEX.md` drift, verified **both ways**: every command listed, and every listed command real.
4. Vendored third-party files, which are exempt — see §4.

---

## 4. Third-party installers leave legitimate orphans

A design or framework skill installed by its own tooling writes into `.claude/skills/`,
`.agents/skills/`, and drops a command shim into `.claude/commands/` — with **no counterpart** in
your source directory, by design. The installer owns their versioning.

A naive drift checker flags these as orphans and advises deleting them or moving them into the
source directory. Both suggestions break the next upgrade.

Hence the explicit `VENDORED` exemption list in `sync-workflows.sh`. If you add a drift checker of
your own, copy that pattern before you add the checker, not after it files its first false report.

---

## 5. `pull_request_target` runs with your secrets

The AI review workflow uses `pull_request_target` because it needs write access to post a comment,
which `pull_request` does not grant for forks.

**It therefore must never check out the pull request's code.** That trigger runs the workflow
definition from the base branch with full repository secrets in scope. Checking out and executing
PR code under it hands those secrets to anyone who opens a pull request.

Read the diff through the API. Never `actions/checkout` with the PR ref under this trigger.

Two smaller decisions in the same workflow, both deliberate:

- **No `synchronize` in the trigger types.** The action posts no sticky comment, so every push
  would add another review.
- **Base branch only, not the promotion branch.** A `dev → prod` diff re-adds the entire AI config
  that the strip pipeline removed, and the provider rejects a diff that size.

---

## 6. The strip pipeline: one list, both directions, merge not rebase

Three findings, each from a separate incident.

**One list, sourced — never copied.** `STRIP_PATHS` lives in `strip-paths.sh`; the other three
scripts source it. When it was duplicated, updating one copy and not the others made the strip
half-land: production kept part of the config, and nothing reported an error.

**Verify both directions.** Asserting that `prod` lost the files misses the failure where `dev`
lost them too. Only the second assertion catches that, and it is the one people leave out.

**Merge, never rebase, on the back-merge.** Rebasing rewrites the strip commit, and the branches
diverge permanently.

One more, from operating it: `git rm --cached` leaves the files present but untracked, which blocks
a subsequent rebase for reasons that look unrelated to the strip.

---

## 7. The skip-CI marker that disarms gates silently

A content-sync workflow stamped a skip-CI marker on its commit — correct on the production side,
where it prevents the workflow retriggering itself.

The same marker was copied onto the development-side commit. That workflow only triggers on pushes
to production, so on the development branch it prevented nothing. What it did do was disarm the
quality gate on **every** promotion opened from that commit.

**A pull request with no checks at all is not a slow queue.** Three causes, all of which report as
"pending" rather than as a failure, so they survive indefinitely:

1. A skip-CI marker on the head commit.
2. A conflicting pull request — the provider builds a merge commit to run `pull_request`
   workflows; a conflict means no merge commit, so nothing starts.
3. A gate whose trigger omits the review branch. `branches: [prod]` alone lets everything reach the
   development branch ungated.

Check `mergeable` and the head commit's message before concluding CI is slow.

---

## 8. CI script divergence between repos is usually correct

The tempting conclusion, on finding eight variants of a quality gate across a set of repos, is that
they have drifted and should be unified.

Check what the variance tracks first. If the gates cluster by **repo role** — applications, content
repos, documentation sites, each with a consistent shape — that is not drift. Documentation repos
do not need the same checks as applications; a backend does not need translation-key parity.

Unifying that deletes legitimate checks. Divergence by role is the correct design; the useful thing
to hunt for is divergence **within** a role.

---

## 9. Generated clients are invisible to symbol search

If your generated API client is gitignored and your symbol-search tool respects gitignore, the
client does not exist as far as symbol search is concerned. Searches for generated hooks or types
return nothing, even though the code is on disk.

This is the one case where an empty result does not mean "absent from the scope you searched" — the
files are filtered out before the search rather than rejected by it.

Use the committed API spec instead. Turning off the gitignore filter is not the fix: it also
exposes every `.env` file to symbol search and file reads.

---

## 10. Frontend-specific: text that is hostile to the docs generator

If you generate a documentation site from JSDoc, two classes of source text will break the build,
and both come from the source being *correct*:

**Multi-line destructured parameters inside a table cell.** The newline ends the inline-code span,
leaving an unbalanced `{` that the parser reads as an expression. Collapse whitespace and escape
the delimiters before the value reaches a table cell.

**Element names in prose.** A JSDoc line describing `<Foo>` parses as an unclosed tag. Escape `<`
before tag-shaped text in prose.

A brace-balance heuristic is the obvious detector and gives false positives on multi-line balanced
expressions. Escaping at render time is more reliable than detecting at write time.

---

## 11. Rule documents get longer as the risk gets quieter

Counter-intuitive, and worth stating so you do not "fix" it.

A backend rule document is typically **larger** than a frontend one, while its contract document is
**much smaller**. Security and data-access rules have to be spelled out — "validate input at system
boundaries" cannot be compressed into one actionable sentence; it needs the boundary list and the
failure behaviour. Meanwhile backend architecture is more uniform, so the contract states the shape
once.

The practical implication: **do not normalise document length across repos.** If your backend rule
document is as short as your frontend one, there are probably security rules that were never
written down.

---

## 12. State intentional absences explicitly

If an architectural layer does not exist yet, the contract document should say so in as many words:

```markdown
The service hook layer does not exist yet. All data fetching currently goes through the client.
This is deliberate and planned, not drift.
```

Without that sentence, the next audit reports it as a finding, and someone spends an afternoon
re-deriving that it was intentional.

**Every deliberate absence is worth one sentence in the contract.** This is the cheapest rule in
the file and the one most often skipped.

---

## 13. Count file-presence claims; do not infer them

A claim of the form "file X does not exist in repo Y" must be **counted**, not assumed.

An audit behind this configuration asserted that backend repos lacked a second-tool mirror
directory. Counting showed it present in every repo — what was actually frontend-only was a
different directory, put there by a skill installer rather than by any architectural decision.

Auditing file presence is far cheaper than auditing intent, and it is the kind of claim that gets
repeated once written down. Run the `ls`.
