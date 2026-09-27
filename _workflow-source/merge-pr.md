---
description: Checks a PR's readiness, confirms the merge, merges it on GitHub with a merge commit, and deletes an internal/* head branch by name afterwards. Never deletes dev, prod, the default branch or any other long-lived head.
---

<!-- Command: /merge-pr [PR number or URL] -->
<!-- Source: _workflow-source/merge-pr.md -->
<!-- Run when a PR is approved and ready to merge -->

# /merge-pr — Merge Pull Request

**Merge commits only.** Squash merging is turned off in the repository settings: a merge commit
keeps every commit and its own date, and it is what lets `/branch-cleanup` prove a branch merged.
`/promote` carries the full reasoning.

## Step 1: Collect the PR

Take the PR number or URL from the arguments; ask only if none was given. For a bare number in a
checkout of the same repository, `gh` resolves the repository itself; otherwise ask for
`owner/repo`.

## Step 2: Check readiness

```bash
bash scripts/ops/pr-ready.sh {PR}
gh pr view {PR} --json title,url,state,headRefName,baseRefName,reviewDecision,additions,deletions,changedFiles
```

`pr-ready.sh` reads the checks, mergeability, unresolved review threads and head/base shape in one
call, and exits 0 only when the PR can be merged. Read both outputs unfiltered.

**Block and report** if: the PR is not `OPEN`, it is `CONFLICTING`, the review decision is
`CHANGES_REQUESTED`, any required check is failing, or a review thread is unresolved. A skipped or
neutral check is not a pass — name it as what it is. `pr-ready.sh` lists each one on its checks row
and exits 1. Show the user that list; only once they confirm that every listed check is expected to
skip (a job that skips itself by design), run `bash scripts/ops/pr-ready.sh --allow-skipped {PR}`
and go on when it exits 0.

## Step 3: Check the head branch

```bash
gh pr view {PR} --json headRefName -q .headRefName
```

- Head matches `internal/*`, a scope branch in the branch model in CLAUDE.md § Branching → it is
  deleted by name after the merge (Step 5), unless the user says it is a long-lived scope branch;
  then it is kept, and fast-forwarded after the next promotion (`.claude/OPERATIONS.md` § GitHub
  and CI).
- Head is `dev`, `prod`, the default branch, or any other long-lived branch → it is **never**
  deleted. On a promotion PR the head is `dev` itself; deleting it removes the shared branch from
  the remote and breaks the strip workflow's back-merge.

## Step 4: Confirm and merge

Show the summary before executing:

```
PR:       {title}
Branch:   {headRefName} → {baseRefName}
Strategy: merge commit
Changes:  +{additions} / -{deletions} across {changedFiles} files
Head:     {deleted after merge | kept: long-lived}
```

Ask: **"Confirm merge? (Yes / No)"**. On **No**, stop without merging. On **Yes**:

```bash
gh pr merge {PR} --merge
```

Never add `--delete-branch`: it cannot see which head it deletes, and the safety hook refuses it.
Never add `--auto` either: with checks pending it only queues the merge, and deleting the head
afterwards closes the PR unmerged. If `gh` refuses because checks are still running, wait for them
and start again at Step 2.

## Step 5: Delete an `internal/*` head by name

Only when Step 3 printed an `internal/*` head the user is not keeping, only that name, and only
after the merge is confirmed: `gh pr view {PR} --json state -q .state` must print `MERGED`. Anything
else means stop and delete nothing.

```bash
git push origin --delete internal/<scope>
```

## Step 6: Report

Output the merge result, the PR URL, and whether a head was deleted. For a promotion into `prod`,
continue with `/promote` Phase 3 to verify that the deployment actually happened.
