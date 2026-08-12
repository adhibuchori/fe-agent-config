---
description: Check PR readiness, confirm merge strategy, and merge a GitHub PR — with optional branch cleanup.
---

<!-- Command: /merge-pr -->
<!-- Source: _workflow-source/merge-pr.md -->
<!-- Run when a PR is approved and ready to merge -->

# /merge-pr — Merge Pull Request

## Step 1: Collect PR Input

Ask the user for:

- **PR URL or PR Number** — e.g., `https://github.com/owner/repo/pull/42` or just `42`

If the user provides only a number, also ask:

- **Repository** — `owner/repo` format

---

## Step 2: Check PR Readiness

Run the following to assess merge readiness:

```bash
# Fetch PR state, reviews, and CI status
gh pr view {PR_NUMBER} --repo {OWNER/REPO} \
  --json title,url,state,headRefName,baseRefName,mergeable,reviewDecision,statusCheckRollup,additions,deletions,changedFiles
```

Evaluate and report:

| Check           | Status                                         |
| :-------------- | :--------------------------------------------- |
| PR state        | Open / Closed / Merged                         |
| Mergeable       | Mergeable / Conflicting / Unknown              |
| Review decision | Approved / Changes requested / Review required |
| CI checks       | All passing / Failing / Pending                |

**Block and report if any of the following are true:**

- PR state is not `OPEN`
- `mergeable` is `CONFLICTING` — instruct user to resolve conflicts first
- Review decision is `CHANGES_REQUESTED`
- Any required CI check is failing

If all checks pass → proceed to Step 3.

---

## Step 3: Confirm Merge Strategy

Ask the user: **"Which merge strategy would you like to use?"**

| Option                   | Description                                                       |
| :----------------------- | :---------------------------------------------------------------- |
| **Squash** (recommended) | Squash all commits into one — keeps main history clean            |
| **Merge commit**         | Preserve all commits with a merge commit                          |
| **Rebase**               | Rebase commits onto base branch — linear history, no merge commit |

Default recommendation: **Squash** — best for feature branches.

---

## Step 4: Confirm & Merge

Show a summary before executing:

```
PR:       {title}
Branch:   {headRefName} → {baseRefName}
Strategy: {chosen strategy}
Changes:  +{additions} / -{deletions} across {changedFiles} files
```

Ask: **"Confirm merge? (Yes / No)"**

- **No** → Exit without merging.
- **Yes** → Run:

```bash
# Squash
gh pr merge {PR_NUMBER} --repo {OWNER/REPO} --squash --auto

# Merge commit
gh pr merge {PR_NUMBER} --repo {OWNER/REPO} --merge --auto

# Rebase
gh pr merge {PR_NUMBER} --repo {OWNER/REPO} --rebase --auto
```

---

## Step 5: Post-Merge Cleanup

After a successful merge, ask: **"Delete the source branch `{headRefName}`? (Yes / No)"**

- **Yes** →
  ```bash
  gh api repos/{OWNER}/{REPO}/git/refs/heads/{headRefName} -X DELETE
  ```
- **No** → Done.

Output the merge result and the URL of the merged PR.
