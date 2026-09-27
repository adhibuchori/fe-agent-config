---
description: Stages every change in the working tree, runs /review and /security-review, fixes every Medium-or-higher and every security finding, re-runs the gates, then commits and pushes the current internal branch to origin. Refuses to run on dev or prod.
---

<!-- Command: /ship -->
<!-- Source: _workflow-source/ship.md -->
<!-- Run to take finished work from "written" to "pushed" in one pass -->

# /ship — Review, Fix, Commit, Push

Stages **every** change in the working tree, takes it through a full `/review` and
`/security-review`, applies every finding they raise, then commits and pushes the current
`internal/{scope}` branch (the branch model in CLAUDE.md § Branching).

This is the one-pass form of what would otherwise be `/review` → decide what to fix → `/commit` →
`git push`. The difference that matters: **`/ship` pre-answers that decision — CRITICAL, HIGH and
MEDIUM all get fixed.** Nothing is left on the table for the user to triage later.

**Scope is the whole working tree.** § 1.1 stages every modified, deleted and untracked file that
`.gitignore` lets through: running `/ship` is the user's go-ahead for that. Nothing joins the commit
unseen: Phase 5 lists what was added that way. Only three things stay out — the protected files in § 1.2, a nested repository, and
anything another session writes into this checkout while `/ship` runs (§ 4.3).

**Never runs on `dev` or `prod`.** § 4.2 refuses, and points at CLAUDE.md § Branching.

---

## Phase 1 — Establish the scope

### 1.1 Stage everything, then snapshot it

```bash
git branch --show-current
```

`dev`, `prod` or the default branch → stop here and go to § 4.2, before staging anything: a review
cycle on the wrong branch is wasted. Otherwise:

```bash
git status --short                  # before: what the user had and had not staged
git add -A
git diff --cached --stat
git diff --cached --name-only       # the scope snapshot — § 4.3 compares against it
```

> [!CAUTION]
> **`git add -A` is the one place this repo stages everything.** Everywhere else the rule is to
> commit by pathspec, because `git add -A` also takes files you did not write: a peer session's
> half-finished edit, a scratch file, a secret someone forgot to ignore. `/ship` accepts that on
> purpose, because finishing the work was the instruction, and it relies on three guards instead:
> the protected-file filter (§ 1.2), the nested-repository check below, and the snapshot compare
> before the commit (§ 4.3). Skip none of them. If another session is actively writing in this
> checkout, stop and commit by pathspec with `/commit` instead.

> [!CAUTION]
> **Read every diff unfiltered.** A command-output wrapper or filter can shorten a diff without
> leaving a marker, and a review of a silently truncated diff passes files it never read. If such a
> wrapper is installed, bypass it for every diff and for `gh pr checks`.

Do not stop to ask what belongs in the commit. A split that looks incomplete (a new file without its
test, a schema change without its migration) is not a question for the user any more; it is a
finding, and Phase 3 fixes it.

Two things still come back out of the index, and Phase 5 names both:

- **A nested repository.** `git add -A` warns `adding embedded git repository` for a clone or a
  worktree inside the checkout. Unstage it with `git rm --cached <path>`; it is never the change.
- **The protected files in § 1.2.** Staging everything is what makes that filter load-bearing
  rather than a formality, so it runs every time.

### 1.2 Reject anything protected

Never swept into a `/ship` commit, whoever staged them:

- `.env*`, the `.env.*.example` templates aside: secrets.
- `.claude/settings.json`: a permission or hook-wiring change is its own reviewed commit, landed
  together with the hooks it names.
- This stack's generated and hand-edit-protected paths:

<stack-block name="ship-protected">

- `src/lib/api/generated/` — only `bun generate:api`, re-run after `openapi.json` changed. It is
  gitignored, so a hit means someone forced it in.
- `openapi.json` — only a fresh copy of the backend's spec, never an edit made here.

```bash
git diff --cached --name-only | grep -E '^src/lib/api/generated/'
```

</stack-block>

```bash
git diff --cached --name-only | grep -E '(^|/)\.env[^/]*$' | grep -vE '\.example$'
git diff --cached --name-only -- .claude/settings.json
```

Any hit: unstage it with `git restore --staged <path>` and say so. A generated file is expected in
the index **only** when its own generator produced it in this change, never when it was edited by
hand.

---

## Phase 2 — Review and security review

Run **`/review`** against the staged changes. Follow it in full: do not re-derive its checklist
here, and do not skip its steps because the diff "looks small".

Carry `/review`'s report into Phase 3 as a worklist. Keep its CRITICAL / HIGH / MEDIUM / LOW
labels — they decide what § 3.2 is allowed to defer.

### Then `/security-review`

After `/review`, run the built-in **`/security-review`** over the same change, through the Skill
tool rather than by re-deriving it. It does not duplicate `/review`'s security step: that step is a
checklist of patterns, while `/security-review` reads the change for vulnerabilities an attacker can
actually reach — an authorization check a crafted request walks around, a user value that lands in
a query, a redirect or a shell. Each catches what the other misses.

Its scope is the branch's pending work, which can be wider than the index: commits not yet pushed
count too. A finding there is fixed in this commit like any other.

Merge its findings into the same worklist. It already drops low-confidence noise before it reports,
so **every finding it returns is fixed, whatever severity it carries** — § 3.1's MEDIUM floor does
not apply to a vulnerability.

### Neither report ends the turn

Both commands close with an instruction meant for when they run on their own. `/review` ends by
handing the user a verdict or a choice of what to fix. `/security-review` ends by asking for a final
reply that contains only its report, and read inside `/ship`, that sentence looks like an order to
stop. It is not. It governs the format of that command's report, not the end of this one: here the
report is a worklist for Phase 3, never a reply.

So do not wait on the verdict or the choice, do not post either report as the final message, and do
not end the turn. Go straight on to Phase 3. `/ship` stops in exactly three places — a § 3.2
decision, a § 4.2 refusal, and the Phase 5 report — and nowhere else. A turn that ends after the
review leaves fixed, reviewed work uncommitted in the index, which looks finished and is not.

---

## Phase 3 — Fix everything

### 3.1 Apply CRITICAL, HIGH and MEDIUM

`/review` ends by classifying findings. **`/ship` fixes everything down to MEDIUM.** A MEDIUM is not
a suggestion to file away — an unfixed file-length or missing-index finding is exactly the kind that
never comes back.

Fix the cause, never the symptom:

| Finding                                    | Fix                                             | Not                       |
| :----------------------------------------- | :---------------------------------------------- | :------------------------ |
| A lint rule fires                          | The underlying issue                            | A disable comment         |
| An async call is not awaited               | Await it, and check its siblings                | Cast the promise away     |
| A filtered or joined column lacks an index | Add the index, with its migration               | Note it for later         |
| A schema change has no migration           | Generate the migration, commit both together    | Ship the schema alone     |
| Logic duplicated across two places         | One helper both import                          | Keep them in sync by hand |
| Docs contradict the code                   | Verify against the source, then correct the doc | Hedge the wording         |
| Generated output edited by hand            | Fix the generator's input and re-run it         | Patch the output          |

### 3.2 When a finding is a decision, not a defect

Stop and ask if applying it would change a public contract (an API or response shape, a published
URL, a schema other code reads, a command-line flag), or pick between architectures the codebase has
no precedent for. Everything else — naming, extraction, dedup, indexes, error handling, file splits,
wording, links — is yours to apply: the user settled it by running `/ship`.

Deferring anything is allowed **only** with the user's explicit say-so, and it must be named in the
Phase 5 summary. Silently dropping a finding is the one outcome this command exists to prevent.

### 3.3 Re-run the gates until green

Every fix invalidates the previous run. Loop until all pass:

<stack-block name="ship-gates">

```bash
bash scripts/check/gates.sh --fix <your files>   # writes the format of the files you changed
bash scripts/check/gates.sh                      # every gate in CLAUDE.md § Quality Gates
bun run build                                    # the gates never build; a broken route fails only here
```

`bun run test` and `bun run test:coverage` are Vitest; bare `bun test` is Bun's own runner and
fails for the wrong reasons. A changed `openapi.json` means `bun generate:api` before the gates, and
a new error code in it needs a message in every locale before `check:error-codes` passes.

</stack-block>

Then stage the fixes the way § 1.1 staged the work, and re-run § 1.2 — a fix can create a file as
easily as it edits one:

```bash
git add -A
```

---

## Phase 4 — Commit

### 4.1 Message

Follow CLAUDE.md § Commit Format and `/commit`'s convention rather than restating them. Write the
body for someone reading `git log` in six months with no memory of this session: what changed and
why it was worth changing, not a list of files, which the diff already holds. When the commit
carries unrelated riders, give them their own paragraph rather than smuggling them into the subject.

Add whatever attribution trailer your harness or team requires. Never hard-code a model name in
this file: the harness knows which model is running, and a copied trailer goes stale.

### 4.2 Refuse the wrong branch

```bash
git branch --show-current
```

`dev`, `prod` or the default branch → **stop.** Offer to branch to `internal/{scope}`, as the branch
model in CLAUDE.md § Branching names it, and commit there. The safety hook refuses a push to those
branches anyway; promotion is `/promote`'s job, and it goes through a PR.

### 4.3 Commit, and read what the hook says

Before committing, compare the index with the § 1.1 snapshot:

```bash
git diff --cached --name-only
```

A path in neither the snapshot nor the set of files Phase 3 edited was written by something else
while `/ship` ran — another session sharing this checkout is the usual cause. Unstage it with
`git restore --staged <path>`, leave the file itself alone, and name it in the Phase 5 report.
Staging everything covers the work that was finished when `/ship` started, not whatever lands in the
checkout afterwards.

```bash
git commit -F - <<'MSG'
...message...
MSG
```

If the repo has a pre-commit hook, it runs the gates on the staged files and can flag something the
whole-project run passed over. A hook failure aborts the commit: fix it and re-run, never
`--no-verify` (the safety hook refuses it). If the repo has no pre-commit hook, Phase 3.3 was the
only gate before CI: say so in Phase 5.

---

## Phase 5 — Push and report

```bash
git push origin "$(git branch --show-current)"
```

New branch → add `-u`. Rejected as non-fast-forward → `git pull --rebase`, then re-run Phase 3.3
before pushing again; a rebase can break what passed before it.

Then report, in this order:

1. **Gate table** — every gate and its final state.
2. **What was auto-staged** — the paths § 1.1 added that the user had not staged, and anything
   § 1.1, § 1.2 or § 4.3 took back out, with the reason.
3. **What the review changed** — each `/review` and `/security-review` finding and the fix that
   landed, grouped by severity. This is the part with real information in it: the user did not
   watch the fixes happen.
4. **Anything deferred** — with the reason and the user's approval it carries. Empty is the
   expected case.
5. **Commit SHA, subject, branch, and file and line counts.**

State plainly if a gate is red or a finding was skipped. A run that fixed nine of ten findings and
says so is worth more than one that claims ten.

---

## Not this command

| Situation                          | Use           |
| :--------------------------------- | :------------ |
| Review only, decide fixes yourself | `/review`     |
| Commit already-reviewed work       | `/commit`     |
| Save work in progress, unreviewed  | `/checkpoint` |
| Find a bug's root cause first      | `/rca`        |
| Open a PR for the branch           | `/create-pr`  |
| Take a branch to production        | `/promote`    |
