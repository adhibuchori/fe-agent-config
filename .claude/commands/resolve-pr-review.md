---
description: Fetch PR review comments, triage them against the numbered rules, apply what holds up, then reply on each review thread and summarise on the PR.
---

<!-- Command: /resolve-pr-review -->
<!-- Source: _workflow-source/resolve-pr-review.md -->
<!-- Run after a PR has been reviewed to triage and apply fixes -->

# /resolve-pr-review — PR Review Resolver

## Step 1: Collect PR Input

Ask the user for:

- **PR URL or PR Number** — e.g., `https://github.com/owner/repo/pull/42` or just `42`
- **Reviewer** (optional) — filter by a specific reviewer username or bot (e.g., `gemini-code-assist`, `copilot`, or a GitHub username). Leave blank to include all reviewers.

If the user provides only a number, also ask:

- **Repository** — `owner/repo` format

---

## Step 2: Fetch PR Review Comments via `gh` CLI

```bash
# Fetch PR metadata
gh pr view {PR_NUMBER} --repo {OWNER/REPO} \
  --json title,url,headRefName,additions,deletions,changedFiles
```

```bash
# Fetch inline review comments (code suggestions)
gh api repos/{OWNER}/{REPO}/pulls/{PR_NUMBER}/comments --paginate \
  --jq '[.[] | {id: .id, user: .user.login, file: .path, line: .line, body: .body, created_at: .created_at}]' \
  > /tmp/pr_inline_comments.json
```

```bash
# Fetch PR-level review comments (summary reviews)
gh api repos/{OWNER}/{REPO}/pulls/{PR_NUMBER}/reviews --paginate \
  --jq '[.[] | {id: .id, user: .user.login, state: .state, body: .body, submitted_at: .submitted_at}]' \
  > /tmp/pr_reviews.json
```

If **reviewer** was specified, filter both files to only include comments from that username.

Parse each suggestion and extract:

- `file` — file path and line number (inline comments only)
- `reviewer` — who left the comment
- `type` — infer from keywords: `bug`, `security`, `performance`, `refactor`, `style`, `test`, `other`
- `summary` — first 1–2 sentences
- `detail` — full comment body

If **no review comments found**, inform the user and exit.

Fetch the review threads too; every inline comment belongs to one, and a thread already resolved
needs nothing:

```bash
gh api graphql -F owner={OWNER} -F repo={REPO} -F pr={PR_NUMBER} -f query='
query($owner: String!, $repo: String!, $pr: Int!) { repository(owner: $owner, name: $repo) {
  pullRequest(number: $pr) { reviewThreads(first: 100) { nodes {
    id isResolved path line comments(first: 1) { nodes { databaseId } } } } } } }'
```

Match each comment to its thread (the thread's first comment `databaseId` is the comment's `id`)
and skip the resolved ones.

---

## Step 3: Validate Against Project Rules

Before presenting suggestions to the user, cross-check each suggestion against **AGENTS.md** Golden Rules:

- If a suggestion **contradicts** a Golden Rule (e.g., recommends adding `useMemo` speculatively → Rule 23), flag it as `⚠ Conflicts with Rule {N}` and recommend dismissing it.
- If a suggestion **aligns** with a Golden Rule (e.g., recommends moving logic out of a component → Rule 6), flag it as `✓ Aligns with Rule {N}`.
- If unclear, mark as `—`.

---

## Step 4: Triage Table

Show a summary table of all suggestions found:

| ID  | File:Line     | Reviewer   | Type   | Rule Alignment | Summary   |
| :-- | :------------ | :--------- | :----- | :------------- | :-------- |
| 1   | {file}:{line} | {reviewer} | {type} | {✓ / ⚠ / —}    | {summary} |

Ask: **"Which suggestions would you like to apply? (e.g., 'All', '1, 3, 5', or 'None')"**

- **All** → Include all in the plan.
- **Specific IDs** → Include only those selected.
- **None** → Exit.

For selected suggestions, ask if there are any **custom notes** or specific approaches before generating the plan.

---

## Step 5: Prioritize

Group accepted suggestions by priority:

| Priority    | Types                                   |
| :---------- | :-------------------------------------- |
| 🔴 Critical | `security`, `bug`                       |
| 🟠 High     | `performance`, architectural violations |
| 🟡 Medium   | `refactor`, `style`, `maintainability`  |
| 🔵 Low      | Minor improvements, `other`             |

---

## Step 6: Generate Fix Plan

Output a structured plan following the `/plan` format:

```markdown
# PR Fix Plan: {PR Title}

**PR**: {PR URL}
**Branch**: {headRefName}
**Date**: {today}
**Changes**: +{additions} / -{deletions} across {changedFiles} files

## SCOPE

- Files to modify: [list unique files from accepted suggestions]

## TASKS

- [ ] [TAG] [verb] [File:Line] — {summary}
      [repeat for all accepted suggestions]

## RISKS

[flag only risks that could block execution]

## CONFIRMATION

[questions that need user answers before starting fixes]
```

---

## Step 7: Execute & Verify

Once the user approves the plan:

1. Apply fixes one by one, ordered by priority (Critical first).
2. After all fixes: run `/check-fix` — every gate must pass.
3. Reply on each thread, the declined ones included: a declined suggestion gets a reply saying
   what it proposed and why it does not apply here. Silence reads as "missed it", and the next
   reviewer raises it again. Post the outcome in each inline comment's own thread (its `id` from
   Step 2), then summarise on the PR:

   ```bash
   gh api -X POST "repos/{OWNER}/{REPO}/pulls/{PR_NUMBER}/comments/{COMMENT_ID}/replies" \
     -f body="<applied in <sha>, or declined and why>"
   gh pr comment {PR_NUMBER} --repo {OWNER/REPO} \
     --body "<what was applied, what was declined and why, and the gate status>"
   ```

4. Resolve each thread you answered, applied or declined with its reason, so the PR's readiness
   check and `/merge-pr` can pass; leave a thread open only when you asked the reviewer a question in
   it:

   ```bash
   gh api graphql -F id={THREAD_ID} -f query='mutation($id: ID!) { resolveReviewThread(input: { threadId: $id }) { thread { isResolved } } }'
   ```
