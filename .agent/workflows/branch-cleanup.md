---
description: Delete merged internal/* branches after a promotion, leaving only dev and prod.
---

<!-- Command: /branch-cleanup -->
<!-- Source: _workflow-source/branch-cleanup.md -->
<!-- Run after a promotion has landed on prod -->

# /branch-cleanup — Leave Only `dev` and `prod`

Removes branches that have already been merged, so the remote keeps only the two promotion
stages. Everything here is reversible except the deletion itself, which is why steps 2 and 3
exist.

## Step 1: Refresh Local View

```bash
git fetch --prune
gh api "repos/{owner}/{repo}/branches" --paginate --jq '.[].name'
```

Work from the remote list, not from `git branch -a` — a stale local ref can name a branch that
no longer exists, or hide one that does.

## Step 2: Build the Protected Set

Never a deletion candidate, under any circumstance:

- `dev` and `prod`
- the repository default branch, whatever it is currently set to
- any branch that is the head of an **open** PR:
  ```bash
  gh pr list --state open --json headRefName --jq '.[].headRefName'
  ```

This is not a formality. A `dev → prod` promotion PR has `dev` itself as its head branch, so a
cleanup that treats "the branch this PR came from" as disposable will delete the shared branch.
That has happened for real: it broke the `strip-ai-on-pr.yml` back-merge, which failed with
`fatal: couldn't find remote ref dev`.

## Step 3: Verify Each Candidate Is Actually Merged

For every remaining branch, confirm it carries nothing that `dev` does not already have:

```bash
gh api "repos/{owner}/{repo}/compare/dev...{branch}" --jq '.ahead_by'
```

- `0` → fully merged, safe to delete.
- anything else → **report it, do not delete**. List these separately as "unmerged, kept".

Do not substitute `git branch --merged` for this check at this stage; it reflects the local
ref state, which may lag the remote.

## Step 4: Confirm

Show the plan before touching anything:

| Branch       | ahead_by | Open PR | Action               |
| :----------- | :------- | :------ | :------------------- |
| `internal/…` | 0        | no      | delete               |
| `internal/…` | 3        | no      | **keep** — unmerged  |
| `dev`        | —        | —       | **keep** — protected |

Ask: **"Delete the branches marked `delete`? (Yes / No)"**. On **No**, stop.

## Step 5: Delete

Remote first, then local:

```bash
gh api "repos/{owner}/{repo}/git/refs/heads/{branch}" -X DELETE
```

```bash
git branch --merged dev | grep -E '^\s+internal/' | xargs -r git branch -d
```

`git branch -d` (not `-D`) is deliberate: it refuses to delete anything unmerged, giving a second
independent guard against the case Step 3 is meant to catch.

## Step 6: Report

Print what was deleted, what was kept and why, and the final remote branch list. The final list
should be exactly `dev` and `prod` unless something was deliberately kept.
