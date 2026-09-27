---
description: Detect branch context, draft a PR title and a description from the repo's PR template, and open the PR into dev.
---

<!-- Command: /create-pr -->
<!-- Source: _workflow-source/create-pr.md -->
<!-- Run when ready to open a new PR -->

# /create-pr — Create Pull Request

## Step 0: Detect Context

```bash
git fetch origin
git branch --show-current
git log origin/dev..HEAD --oneline
git diff origin/dev...HEAD --stat
```

With RTK installed, run the `git log` and `git diff` lines as `rtk proxy git …`: its rewrite drops
merge commits from `--oneline` and reshapes `--stat`, and the PR body lists both.

The base branch is **`dev`**, never `main`: this repo promotes `internal/{scope}` → `dev` →
`prod` (CLAUDE.md § Branching). A promotion into `prod` is `/promote`'s job.

- **Branch name**: infer the scope from it (`internal/contact-form` → scope `contact`)
- **Commits**: summarise what was done from the log
- **Diff stat**: which files changed

## Step 1: Collect What Is Missing

Ask for anything still needed, in one prompt: a ticket ID (optional, e.g. `PROJ-42`), a
one-sentence description of the change if the commits do not make it clear, and any breaking change
or follow-up.

## Step 2: Draft

**Title:** `type(scope): [TICKET-ID] Description` in CLAUDE.md § Commit Format — under 70
characters, without `[TICKET-ID]` when there is none.

**Description:** `.github/PULL_REQUEST_TEMPLATE/dev.md`, filled in. Write the Summary and How to
Verify sections; tick or answer each checklist line; delete the conditional block this change does
not touch. Add nothing the quality gate already decides — `quality-gate.yaml` is the list, and a
second copy of it here is the part that goes stale.

## Step 3: Confirm

Show the title and body in a fenced block. Ask whether they are correct; if not, ask what to
change, redraft, and show them again.

## Step 4: Create

Push every commit first, in one push: each push to a branch with an open PR starts a fresh CI run.

```bash
git push -u origin "$(git branch --show-current)"
gh pr create --title "<title>" --body-file <filled template> --base dev
```

Output the PR URL.
