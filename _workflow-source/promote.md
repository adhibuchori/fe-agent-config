---
description: Full promotion pipeline — takes internal/{scope} through a PR into dev and a promotion PR into prod, audits the production env and migrations, and verifies the deployment by timestamp. Merges PRs with merge commits, deletes the internal head by name, and posts review replies on GitHub.
---

<!-- Command: /promote -->
<!-- Source: _workflow-source/promote.md -->
<!-- Run to take finished work all the way to production -->

# /promote — Promote To Production

Takes work from `internal/{scope}` through `dev` to `prod`, the branch model in CLAUDE.md
§ Branching, and does not report success until production has actually changed.

**Merge with `--merge`, never `--squash`**, into `dev` and into `prod` alike, and keep squash
merging turned off in the repository settings. A merge commit keeps every commit and its own date;
squash folds the branch into one commit dated the merge day, and leaves the merged branch "ahead"
of `dev`, so `/branch-cleanup` can never prove it merged.

**Pushes to `dev` and `prod` are the user's.** The safety hook refuses them from the agent,
however they are asked. Where this command needs one, ask the user to type `! git push …` in the
prompt, and wait for its output.

---

## This repo's deploy target

Fill once per repo. Phases 2 and 3 use every value.

| Field    | Value                     |
| -------- | ------------------------- |
| Platform | `<deploy platform>`       |
| App      | `<app-name>` (`<app-id>`) |
| Live URL | `https://<app-host>`      |

**Deploy adapter.** The operations this command needs, as this repo runs them. The
`deploy-platform` MCP server (`.claude/mcp/deploy-platform.example.json`, loaded on demand) usually
covers `latest`, `trigger` and `backup`; the platform's API or CLI covers `read-env` when the MCP
server redacts env values, which it should.

- `read-env <file>`: `<command>`. Writes the live production configuration (runtime env and build
  arguments) to `<file>`, one `KEY=VALUE` per line, or one bare `KEY` per line where the platform
  shows names only. Prints nothing.
- `latest`: `<command>`. Prints the newest deployment's id, status and created-at timestamp
  (ISO 8601).
- `trigger`: `<command>`. Starts a deploy of `prod`, and exits non-zero when the platform declines
  it.
- `backup`: `<command>`. Takes a manual database backup and prints where it landed.

**Quality gate for this repo:**

<stack-block name="promote-gates">

```bash
bash scripts/check/gates.sh   # every gate in CLAUDE.md § Quality Gates
bun run build                 # the production build: the gates never run it
```

</stack-block>

---

## Phase 1 — PR to `dev`

### 1.1 Create or locate the PR

```bash
git branch --show-current
gh pr list --head "$(git branch --show-current)" --base dev --json number,url,title
```

If none exists, run `/create-pr` (base `dev`) rather than duplicating that logic here.

Push every commit **before** opening the PR. Each push to a branch with an open PR triggers a fresh
CI run, so batching is a direct saving of Actions minutes.

### 1.2 All GitHub Actions green

```bash
gh pr checks {PR} --watch
bash scripts/ops/pr-ready.sh {PR}
```

`pr-ready.sh` reads the PR's checks, mergeability, unresolved review threads, and whether its head
is the branch its base expects, in one call; it exits 0 only when the PR can be merged. Read both
whole: `pr-ready.sh` is a script, which RTK never rewrites, and with RTK installed run `gh pr checks`
and the `gh run view` below as `rtk proxy gh …`, because a filtered summary shifts between calls
and cannot be trusted for a pass/fail decision.

If anything is red: **investigate the cause and fix it.** Do not re-run a failed job hoping it
passes. Read the log:

```bash
gh run view {RUN_ID} --log-failed
```

Repeat until every check is genuinely green. A skipped or neutral check is not green — say which it
is. `pr-ready.sh` names each one and exits 1; once the user confirms that every one is expected to
skip (a job that skips itself by design), `bash scripts/ops/pr-ready.sh --allow-skipped {PR}`
accepts them.

### 1.3 No conflicts

The mergeability row of `pr-ready.sh` (1.2) answers this.

`CONFLICTING` → resolve by merging `dev` into the branch locally, fixing the conflict, and pushing.
Never resolve by force-pushing a rewritten branch; that invalidates every review comment already
anchored to a line.

### 1.4 Triage reviews — and always reply

Fetch both inline and summary reviews:

```bash
gh api "repos/{owner}/{repo}/pulls/{PR}/comments" --paginate
gh api "repos/{owner}/{repo}/pulls/{PR}/reviews" --paginate
```

With RTK installed, run both as `rtk proxy gh api …`: every comment and its `id` are needed for the
replies. Judge each suggestion yourself against this repo's rules (`AGENTS.md` where it has one, and
`.claude/rules/`). Apply the ones that are
genuinely right; a reviewer bot is often confidently wrong about project-specific conventions.

**Reply to every review thread, including the ones you decline** — that is the point of this step.
A declined suggestion gets a reply saying what it proposed and why it does not apply here. Silence
reads as "missed it", and the next reviewer raises it again.

```bash
gh pr comment {PR} --body "<what was applied, what was declined, and why>"
```

Re-run the quality gate after applying any fix.

### 1.5 Merge to `dev`

```bash
gh pr view {PR} --json headRefName -q .headRefName   # must print internal/<scope>
gh pr merge {PR} --merge
git push origin --delete internal/<scope>            # the name printed above, nothing else
```

Delete the head by name, never with `--delete-branch`: the safety hook refuses that flag because it
cannot see the head, and on a promotion PR the head is `dev` itself. A long-lived scope branch the
user keeps is not deleted; fast-forward it after Phase 3 instead (`.claude/OPERATIONS.md` § GitHub
and CI).

---

## Phase 2 — PR `dev` → `prod`

### 2.1 Open the promotion PR

```bash
gh pr create --base prod --head dev --title "chore: promote dev to prod" --body "<summary>"
```

Never write GitHub's skip-CI marker anywhere in the title or body, not even while explaining it in
prose. The pattern matches anywhere in the text and cancels every workflow in the run, including the
production deploy.

### 2.2 Green and conflict-free

Same checks as 1.2 and 1.3.

### 2.3 Production env and schema are ready

CI checks neither, and both are how a green promotion breaks production: a database whose
migrations were never applied, a frontend whose API origin was never set and quietly fell back to a
local address. Each surfaces only when a real request hits it.

**Env against the template.** Compare the live configuration's keys, build arguments included, to
`.env.production.example` and to every variable the code's env schema reads. A code-side fallback
turns a missing key into a quiet wrong address rather than a crash, so a key that is absent, empty,
still a placeholder, or holding a development value counts as missing. The live values include
every secret in clear, so they go to a file that is removed on exit, and only key names with a
verdict reach the transcript. A repo without `.env.production.example` cannot be audited this way:
write it first (every key, placeholder values only), or report the audit as not run.

```bash
live="$(mktemp)"
trap 'rm -f "$live"' EXIT
<read-env command> "$live"   # the adapter's read-env: writes the file, prints nothing
python3 - "$live" .env.production.example <<'PY'
import re, sys

# Add this project's development-only hosts and ports to DEV.
DEV = re.compile(r"localhost|127\.0\.0\.1|0\.0\.0\.0|-dev[.:/]")
LINE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)(?:=(.*))?$")

def parse(path):
    found = {}
    for raw in open(path, encoding="utf-8", errors="replace"):
        match = LINE.match(raw.rstrip("\n"))
        if match and not raw.lstrip().startswith("#"):
            value = match.group(2)
            found[match.group(1)] = None if value is None else value.strip().strip("'\"")
    return found

live, template = parse(sys.argv[1]), parse(sys.argv[2])
for key in sorted(set(template) | set(live)):
    if key not in live:
        verdict = "MISSING"
    elif key not in template:
        verdict = "NOT IN TEMPLATE"
    elif live[key] is None:
        verdict = "PRESENT (value not readable)"
    elif live[key] == "":
        verdict = "EMPTY"
    elif "PLACEHOLDER" in live[key] or live[key].startswith("<"):
        verdict = "PLACEHOLDER"
    elif DEV.search(live[key]):
        verdict = "DEV VALUE"
    else:
        verdict = "set"
    print(f"{key}\t{verdict}")
PY
```

Every verdict other than `set` is a finding to resolve before the merge. A key added to the template
in this promotion is added to the platform before the deploy lands, as a read-modify-write
(`.claude/OPERATIONS.md` § Deploys): read the whole configuration, write it back with the new key,
and compare the variable count before and after.

**Migrations before the deploy lands.** A deploy that does not migrate on boot reaches the new
schema only when someone runs the migration, and the migration lands before the new code does, so
it must stay backward-compatible with the code still running.

1. List what this promotion adds:
   `git diff --name-only origin/prod...origin/dev -- <migrations-dir>` (with RTK installed,
   `rtk proxy git diff …`: its rewrite prints a line even when nothing changed).
   Nothing listed: skip to 2.4.
2. Take a manual backup with the adapter's `backup`, and confirm the file exists where it says.
3. Hand the migration to the user. It runs as the database owner role, from their shell, with the
   production connection string they hold; the agent's database role has no DDL rights and must
   not get them. Ask them to type `! <migrate-command>` and wait for its output.
4. Verify through `db-prod`, read-only: `<applied-migrations-query>` must show every migration file
   on `prod` as applied. For a tool that records a count of applied files (drizzle) compare the
   count; for one that records only the head revision (Alembic's `version_num`) compare that head
   with the newest revision on `prod`, never a count.

A repo that owns no schema depends on its backend's: before this deploy lands, confirm the backend's
production migrations match its own `prod` branch, and promote the backend first if they do not.

<stack-block name="migrations">

| Placeholder                  | This stack                              |
| ---------------------------- | --------------------------------------- |
| `<migrations-dir>`           | none: this frontend owns no schema      |
| `<migrate-command>`          | none                                    |
| `<applied-migrations-query>` | none                                    |

This frontend owns no schema, so skip the migration steps; the paragraph above about a repo that
owns no schema applies, and the backend it reads is checked instead.

</stack-block>

**Browser pass for what jsdom cannot prove.** When this promotion changes sign-in, sessions, or
another flow that only a browser shows, walk it against `dev` with a test account (never a real
person's), in every locale the app ships, before merging. Report each step as passed, failed or not
run. The usual list: a one-time code never appears in the URL; a reset link opened in a fresh tab
offers a new code; signing out and pressing Back lands on the sign-in page; pressing Pay twice
raises one payment; a stopped backend shows an error, not a spinner; the flow works with the
keyboard alone and with reduced motion on. After a change to third-party sign-in, start it on the
deployed site: it must reach the provider's account chooser, not a redirect-URI error.

### 2.4 Merge — never with `--delete-branch`

```bash
gh pr view {PR} --json headRefName    # will be: dev
gh pr merge {PR} --merge
gh pr view {PR} --json mergedAt -q .mergedAt   # the merge timestamp, UTC
```

The head of a promotion PR **is `dev` itself**. `--delete-branch` here deletes the shared branch
from the remote, and the strip workflow's back-merge then fails with `couldn't find remote ref dev`.
Recovery depends on some local checkout still holding the ref.

Record that merge timestamp — Phase 3 compares against it.

---

## Phase 3 — Verify production actually changed

### 3.1 Confirm the deployment

Run the adapter's `latest`. Count only a deployment whose created-at is **after** the merge
timestamp from 2.4, and whose status is done without an error. Deployment lists are not guaranteed
sorted: pick the newest by created-at, never by position.

- Still building → wait once, sized from this app's own recent build times, then read it again.
- Nothing newer than the merge → not finished, never success.
- Failed → read the platform's build log before anything else.

A status field may not separate "building" from "healthy": a `/health` 200 during a build is the
previous container answering.

### 3.2 When no deployment appeared

The trigger failed silently: a webhook that never fires leaves no failed deployment behind, only an
absence. Run the adapter's `trigger`, confirm a new deployment appears in `latest`, and then find
out why the automatic one did not.

**A green Actions run is not evidence that production changed.** Promotions merged seconds apart can
each show a green run while one of them recorded no deployment at all. Verify this repo
specifically; another repo's success proves nothing about this one.

### 3.3 Smoke test the live URL

Check `https://<app-host>` and exercise the change itself, not just that the process is up.

For anything touching CORS, test with the **actual frontend origin**. A request from
`evil.example` being rejected proves nothing: an origin allowlist that is unset and falls back to a
development origin rejects that too, while breaking every real browser.

After an auth change, start each third-party sign-in on the live site: it must reach the provider's
account chooser, not a redirect-URI mismatch page.

### 3.4 Clean up

Offer `/branch-cleanup` to remove the merged `internal/…` branches.

---

## Report

State plainly, per phase: what merged, what the CI status was, which reviews were applied versus
declined, the env verdicts and migrations run, and the deployment id plus timestamp proving
production changed. If any step was skipped, say which and why — do not let it pass silently.
