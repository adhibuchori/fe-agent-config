---
description: After a promotion, deletes every merged branch on the remote and locally except dev, prod, the default branch and open-PR heads, once the user confirms the list. Unmerged branches are reported and kept.
---

<!-- Command: /branch-cleanup -->
<!-- Source: _workflow-source/branch-cleanup.md -->
<!-- Run after a promotion has landed on prod -->

# /branch-cleanup — Leave Only `dev` and `prod`

Removes branches that have already been merged, so the remote keeps only the two promotion stages
of the branch model in CLAUDE.md § Branching; the `internal/…` scope branches are the ones it
clears. Everything here is reversible except the deletion itself, which is why Steps 2 and 3 exist.

## Step 1: Refresh the view

```bash
git fetch --prune
gh api "repos/{owner}/{repo}/branches" --paginate --jq '.[].name'
```

Work from the remote list, not from `git branch -a`: a stale local ref can name a branch that no
longer exists, or hide one that does.

## Step 2: Build the protected set

Never a deletion candidate, under any circumstance:

- `dev` and `prod`
- the repository's default branch, whatever it is currently set to
- any branch that is the head of an **open** PR:

  ```bash
  gh pr list --state open --json headRefName --jq '.[].headRefName'
  ```

- any long-lived scope branch the user names as kept

This is not a formality. A `dev` → `prod` promotion PR has `dev` itself as its head branch, so a
cleanup that treats "the branch this PR came from" as disposable deletes the shared branch, and the
strip workflow's back-merge then fails with `couldn't find remote ref dev`.

## Step 3: Verify each candidate is actually merged

For every remaining branch, confirm it carries nothing that `dev` does not already have:

```bash
gh api "repos/{owner}/{repo}/compare/dev...{branch}" --jq '.ahead_by'
```

- `0` → fully merged, safe to delete.
- Anything else → **report it, do not delete it**. List these separately as "unmerged, kept".

This test is exact because merges into `dev` are merge commits. A branch that was squash-merged
elsewhere still reads as ahead: report it and keep it; never delete on a guess.

Do not substitute `git branch --merged` for this check: it reflects the local refs, which may lag
the remote.

## Step 4: Confirm

Show the plan before touching anything:

| Branch       | ahead_by | Open PR | Action               |
| :----------- | :------- | :------ | :------------------- |
| `internal/…` | 0        | no      | delete               |
| `internal/…` | 3        | no      | **keep** — unmerged  |
| `dev`        | —        | —       | **keep** — protected |

Ask: **"Delete the branches marked `delete`? (Yes / No)"**. On **No**, stop.

## Step 5: Delete

Remote first, one branch at a time, only the names marked `delete`:

```bash
gh api "repos/{owner}/{repo}/git/refs/heads/{branch}" -X DELETE
```

Then local:

```bash
git branch --merged dev | grep -E '^\s+internal/' | xargs -r git branch -d
```

With RTK installed, start the pipe with `rtk proxy git branch --merged dev`: its rewrite reformats
the list, and the `grep` would then match nothing.

`git branch -d` (not `-D`) is deliberate: it refuses to delete anything unmerged, a second
independent guard against the case Step 3 is meant to catch.

## Step 6: Report

Print what was deleted, what was kept and why, and the final remote branch list. The final list
should be exactly `dev` and `prod`, unless something was deliberately kept.
