---
description: Promote internal branch to prod without a PR, deploying directly when CI minutes are exhausted.
---

<!-- Command: /promote-dokploy -->
<!-- Source: _workflow-source/promote-dokploy.md -->
<!-- Fallback promotion for when GitHub Actions or Blacksmith minutes are gone -->

# /promote-dokploy — Promote Without Relying On CI

Same destination as `/promote`, different assumption: **CI cannot be trusted to run.** Use this
only when GitHub Actions is blocked (spending limit) or Blacksmith minutes are exhausted, so the
usual green-checks-then-merge flow would block forever.

**Prefer `/promote`.** This command trades away every automated gate. Reach for it when the
alternative is production going stale, not to save a few minutes.

**This repo's deploy target:** Dokploy application **<app-name>** (`<app-id>`) — https://<app-host>

**Quality gate for this repo:**

```bash
bun fl          # oxfmt (format) + oxlint (lint)
bun type-check  # TypeScript strict — tsc --noEmit
```

---

## What this skips, and what replaces it

| `/promote` relies on           | Here instead                               |
| ------------------------------ | ------------------------------------------ |
| CI running the quality gate    | `quality-gate.sh` locally, Phase 1         |
| PR review + bot review         | Nothing. State this plainly in the report. |
| `strip-ai-on-pr` cleaning prod | The same scripts, run by hand — Phase 2.3  |
| Deploy triggered by `ci-cd`    | Direct deploy, Phase 3                     |
| Green checks as merge evidence | Local gate output as merge evidence        |

Both merge commits carry the skip-CI marker, so no workflow run is created at all. This command
therefore costs **zero runner minutes** — which also means nothing runs to catch a mistake.
Everything in the right-hand column above is yours to actually do.

---

## Phase 0 — Confirm CI is genuinely unavailable

Do not skip this. If CI works, stop and use `/promote`.

```bash
gh run list --limit 5 --json name,status,conclusion,createdAt
```

Two signatures worth telling apart:

- **Spending limit** — job dies in ~3 seconds with no steps. The reason is in the check-run
  annotation, not the run log: `gh api repos/{owner}/{repo}/check-runs/<id>` → look for
  _"recent account payments have failed or your spending limit needs to be increased"_.
- **Runner minutes exhausted** — job is created but never starts; `started_at` stays far behind
  `created_at` and `runner_name` is empty.

A job queued for hours is not the same as a job that cannot run. Queue time costs nothing —
wait it out rather than bypassing the gates.

### 0.1 Open the run log

Every use of this command leaves a record. Create it **now**, before any change, so an abandoned
promotion is still visible:

```bash
mkdir -p promote-dokploy-logs
LOG="promote-dokploy-logs/$(date -u +%Y-%m-%dT%H%M)-$(git branch --show-current | tr / -).md"
```

Two lists, and they are settled at different times. The first you tick as you go. The second is
**debt owed to CI** — things only a runner can do — and it stays open until the runner is back.

```markdown
# promote-dokploy — <scope>

- **Started (UTC):** <timestamp>
- **Reason CI unavailable:** <spending limit | minutes exhausted> + evidence from Phase 0
- **Promoted commit:** `<prod sha>`
- **Settled:** <blank until every box below is ticked>

## Done by hand during the promotion

- [ ] Phase 1 — quality-gate.sh passed (paste the last lines)
- [ ] 2.1 — merged to dev — `<sha>`
- [ ] 2.2 — merged to prod — `<sha>`
- [ ] 2.3 — strip-ai.sh / back-merge-prod.sh / verify-strip.sh all passed
- [ ] 3.1 — deployed
- [ ] 3.2 — deployment verified — id `<id>`, `createdAt` after 2.2
- [ ] 3.3 — smoke test

## Owed to CI — settle when the runner is back

Each of these ran for every other commit on prod, and not for this one.

- [ ] Re-run the quality gate on a clean runner, against `prod`
- [ ] Build and push the ghcr image — the tag is stale for `<prod sha>`
- [ ] DeepSeek Code Review — this change was never machine-reviewed
- [ ] react-doctor
- [ ] Docs changelog — confirm it fired, or dispatch it

## Skipped, and why

<PR review and bot review were skipped by definition — say what else was, and why.>
```

`promote-dokploy-logs/` is stripped from `prod` like the rest of the dev-only files, so the
record lives on `dev` where it belongs.

### Settling the debt later

When runners are available again, find every promotion still carrying open items:

```bash
grep -rl '^- \[ \]' promote-dokploy-logs/
```

Work each file down to zero unticked boxes, then fill in **Settled**. A log with open boxes is a
commit in production that nothing has ever checked — that is the whole reason the file exists.

---

## Phase 1 — Run the gate locally

```bash
.github/scripts/quality-gate.sh origin/dev
```

That script runs the checks `quality-gate.yaml` runs — format, lint, types, comment style and
length, the base-ref security scans, the secret scan, tests, and the production build — against
the base you pass it. It exits non-zero on the first real failure, so it enforces rather than
suggests.

It is **not yet** the workflow's own source; `quality-gate.yaml` still carries its own copy.
Until those are merged, treat a difference between them as a bug in the script, not a licence
to skip a check.

Two things it cannot fully reproduce, and you should know which:

- **gitleaks** runs from the same pinned version, but a different build for your platform. Same
  rules, different binary.
- **JSDoc presence** and **AI rule drift** are reported as warnings in CI too — they never block
  there either.

If anything fails, fix it and re-run. A promotion that skips the gate _and_ skips review has
nothing left checking it at all.

---

## Phase 2 — Merge without a PR

### 2.1 `internal/{scope}` → `dev`

```bash
git fetch origin
git checkout dev && git pull --ff-only origin dev
git merge --no-ff internal/{scope} -m "feat: <what landed> [skip ci]"
git push origin dev
```

`--no-ff` keeps the branch's history visible. Without a PR there is no squash and no
auto-generated merge commit, so this message is the only record of what shipped — write it as
carefully as you would a PR title.

The skip-CI marker is deliberate. Every push to `dev` and `prod` would otherwise start a run,
and on `prod` that run **deploys** — giving you a second deploy racing the one Phase 3 performs.
With the marker GitHub never creates the run at all, so this whole command costs zero runner
minutes whether or not your quota is healthy.

That marker matches anywhere in a commit message. Never write it in prose in an ordinary commit:
it would cancel a legitimate production deploy.

If the merge conflicts, resolve it here and re-run Phase 1 before pushing. A conflict resolution
is new code that nothing has checked.

### 2.2 `dev` → `prod`

```bash
git checkout prod && git pull --ff-only origin prod
git merge --no-ff dev -m "chore: promote dev to prod [skip ci]"
git push origin prod
```

Record the push timestamp — Phase 3 compares against it.

Never delete `dev` afterwards. It is the shared branch, not a disposable one.

### 2.3 Strip the AI config — not optional

`strip-ai-on-pr.yml` triggers on a **merged pull request**. This flow has no PR, so it never
fires. Skip this and `prod` keeps `.claude/`, `.mcp.json`, `AGENTS.md`, `CLAUDE.md` and the
rest — including `.claude/DATABASE.md`, which carries the Postgres topology, ports and role
names. That is a leak, not untidiness.

Run what CI would have run — the same three scripts the workflow itself calls:

```bash
.github/scripts/strip-ai.sh          # remove from prod, commit, push
.github/scripts/back-merge-prod.sh   # merge prod back into dev, re-instating the config
.github/scripts/verify-strip.sh      # assert prod lost them and dev kept them
```

Because both routes call the same scripts, the resulting `prod` tree is byte-identical to what
a PR merge would have produced.

`verify-strip.sh` is the one that matters. The strip's historical failure mode was **silence**:
once it was cancelled by a shared concurrency group and nobody noticed, and once `dev` lost its
entire AI config because only half the operation ran. Both assertions exist because of those.
A green run without them proves nothing.

---

## Phase 3 — Deploy, because nothing else will

### 3.1 Deploy directly through Dokploy

```
mcp__dokploy-mcp__application-deploy  applicationId=<app-id>
```

That is the same action the webhook would have triggered, minus GitHub Actions. It builds from
git source on the Dokploy box, so it needs nothing from the CI runner.

If the MCP server is unavailable, the repo's own webhook script does the same job from your
machine:

```bash
DOKPLOY_WEBHOOK_URL='<from repo secrets>' .github/scripts/trigger-deploy.sh refs/heads/prod
```

Do not replace that script with a bare `curl`. Dokploy reads the branch from a push payload;
without the `x-github-event` header it answers 301 "Branch Not Match", deploys nothing, and
still looks like a success.

### 3.2 Confirm the deployment is real

```
mcp__dokploy-mcp__deployment-all  applicationId=<app-id>
```

The first element is the newest. Its `createdAt` must be **after** the push in 2.2, and its
status must be `done`.

Do not read the `deployments` array from `application-one` instead — it is unsorted and
truncated, and has already caused a stale deployment to be reported as current.

### 3.3 Smoke test

Check https://<app-host> and exercise the change itself, not just that the process is up.

For anything touching CORS, test with the **actual frontend origin**. Rejecting `evil.example`
proves nothing — an unset `CORS_ORIGINS` falls back to `http://localhost:3000`, which rejects
that origin too while breaking every real browser. That combination caused a one-hour outage.

---

## Phase 4 — Pay back the skipped gates

This promotion carries unreviewed code. Close the gap:

1. Finish the run log opened in Phase 0.1: fill in every unticked box with what actually
   happened, and complete the "Skipped, and why" section. That file is the audit trail.
2. Re-run the gate against what actually landed. Nothing re-ran it after the strip commit,
   and no workflow in this repo accepts a manual trigger:

   ```bash
   git checkout prod && git pull --ff-only origin prod
   .github/scripts/quality-gate.sh origin/prod
   ```

3. If anything in Phase 1 was skipped rather than passed, open an issue for it now.
4. Commit the run log — an uncommitted one helps nobody:

   ```bash
   git checkout dev
   git add promote-dokploy-logs/
   git commit -m "docs: log promote-dokploy run [skip ci]"
   git push origin dev
   ```

Offer `/branch-cleanup` for the merged `internal/…` branches.

---

## Report

State plainly: that this bypassed PR review entirely, the local gate output that stood in for
CI, the merge commits for both hops, and the deployment ID plus timestamp proving production
changed. Name every check that was skipped rather than passed — silence here is how an
unreviewed regression reaches production unnoticed.
