---
description: Full promotion pipeline — internal branch to dev to prod, with CI, review triage, and deploy verification.
---

<!-- Command: /promote -->
<!-- Source: _workflow-source/promote.md -->
<!-- Run to take finished work all the way to production -->

# /promote — Promote To Production

Takes work from `internal/{scope}` through `dev` to `prod`, and does not report success until
production has actually changed.

**This repo's deploy target:** Dokploy application **<app-name>** (`<app-id>`) — https://<app-host>

**Quality gate for this repo:**

```bash
bun fl          # oxfmt (format) + oxlint (lint)
bun type-check  # TypeScript strict — tsc --noEmit
```

---

## Phase 1 — PR to `dev`

### 1.1 Create or locate the PR

```bash
git branch --show-current
gh pr list --head "$(git branch --show-current)" --base dev --json number,url,title
```

If none exists, run `/create-pr` (base `dev`) rather than duplicating that logic here.

Push every commit **before** opening the PR. Each push to a branch with an open PR triggers a
fresh CI run, so batching is a direct saving of Actions minutes.

### 1.2 All GitHub Actions green

```bash
gh pr checks {PR} --watch
```

If a command wrapper is in play, bypass it for this one. A filtered summary shifts between
calls and cannot be trusted for a pass/fail decision.

If anything is red: **investigate the cause and fix it.** Do not re-run a failed job hoping it
passes. Read the log:

```bash
gh run view {RUN_ID} --log-failed
```

Repeat until every check is genuinely green. A skipped or neutral check is not green — say which
it is.

### 1.3 No conflicts

```bash
gh pr view {PR} --json mergeable,mergeStateStatus
```

`CONFLICTING` → resolve by merging `dev` into the branch locally, fixing the conflict, and
pushing. Never resolve by force-pushing a rewritten branch; that invalidates every review comment
already anchored to a line.

### 1.4 Triage reviews — and always reply

Fetch both inline and summary reviews:

```bash
gh api "repos/{owner}/{repo}/pulls/{PR}/comments" --paginate
gh api "repos/{owner}/{repo}/pulls/{PR}/reviews" --paginate
```

Judge each suggestion yourself against `AGENTS.md` and this repo's rules. Apply the ones that are
genuinely right; a reviewer bot is often confidently wrong about project-specific conventions.

**Reply to every review thread, including the ones you decline** — that is the point of this
step. A declined suggestion gets a reply saying what it proposed and why it does not apply here.
Silence reads as "missed it", and the next reviewer re-raises it.

```bash
gh pr comment {PR} --body "<what was applied, what was declined, and why>"
```

Re-run the quality gate after applying any fix.

### 1.5 Merge to `dev`

```bash
gh pr merge {PR} --squash --delete-branch
```

`--delete-branch` is correct **here** — the head is a disposable `internal/…` branch. Confirm
that first:

```bash
gh pr view {PR} --json headRefName
```

---

## Phase 2 — PR `dev` → `prod`

### 2.1 Open the promotion PR

```bash
gh pr create --base prod --head dev --title "chore: promote dev to prod" --body "<summary>"
```

Never write the skip-CI marker anywhere in the title or body — not even while explaining it in
prose. The pattern matches anywhere in the message and cancels every workflow in the run,
including the production deploy.

### 2.2 Green and conflict-free

Same checks as 1.2 and 1.3.

### 2.3 Merge — never with `--delete-branch`

```bash
gh pr view {PR} --json headRefName    # will be: dev
gh pr merge {PR} --merge
```

The head of a promotion PR **is `dev` itself**. `--delete-branch` here deletes the shared branch
from the remote. This is not hypothetical: it happened, and it cascaded into
`strip-ai-on-pr.yml`'s back-merge failing with `fatal: couldn't find remote ref dev`. Recovery
only worked because a local checkout still held the ref.

Record the merge timestamp — Phase 3 compares against it.

---

## Phase 3 — Verify production actually changed

### 3.1 Wait for the workflow run to finish

```bash
gh run list --branch prod --limit 3
```

### 3.2 Confirm the deployment exists

```
mcp__dokploy-mcp__deployment-all  applicationId=<app-id>
```

The first element is the newest. Confirm its `createdAt` is **after** the merge timestamp from
2.3, and that its status is `done`.

Do not read the `deployments` array returned by `application-one` instead — it is unsorted and
truncated, and has already caused a stale deployment to be reported as the current one.

If no deployment appeared, the trigger failed silently. Deploy manually and then find out why:

```
mcp__dokploy-mcp__application-deploy  applicationId=<app-id>
```

**A green Actions run is not evidence that production changed.** Three backend promotions once
merged within nine seconds of each other: two deployed, one recorded no deployment at all, and
all three runs were green. Verify this repo specifically; another repo's success proves nothing
about this one.

### 3.3 Smoke test the live URL

Check the real endpoint, not just that the container is up.

For anything touching CORS, test with the **actual frontend origin**. A request from
`evil.example` being rejected proves nothing — an unset `CORS_ORIGINS` silently falls back to
`http://localhost:3000`, which rejects that origin too while also breaking every real browser.
That combination caused a one-hour production outage.

### 3.4 Clean up

Offer `/branch-cleanup` to remove the merged `internal/…` branches.

---

## Report

State plainly, per phase: what merged, what the CI status was, which reviews were applied versus
declined, and the deployment ID plus timestamp proving production changed. If any step was
skipped, say which and why — do not let it pass silently.
