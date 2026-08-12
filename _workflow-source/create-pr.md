---
description: Auto-detect branch, generate PR title & description, then create the PR on GitHub — interactive, iterative, ready to ship.
---

<!-- Command: /create-pr -->
<!-- Source: _workflow-source/create-pr.md -->
<!-- Run when ready to open a new PR -->

# /create-pr — Create Pull Request

## Step 0: Auto-Detect Context

Run the following to gather context automatically:

```bash
git branch --show-current
git log main..HEAD --oneline
git diff main..HEAD --stat
```

- **Branch name**: infer scope from branch name (e.g., `feat/contact-form` → scope: `contact`)
- **Commits**: summarize what was done from the log
- **Diff stat**: understand which files changed

---

## Step 1: Collect Missing Input

Based on what was auto-detected, ask the user for anything still needed (all in one prompt):

- **Ticket ID** (optional) — e.g., `SER-42`
- **Feature Description** — one sentence describing what this change does (if not clear from commits)
- **Context** (optional) — breaking changes, related tickets, user impact

---

## Step 2: Generate Draft

Produce a **PR Title** and **PR Description** using the formats below.

**Title Format:**

```
feat(scope): [TICKET-ID] Integrate {Feature Description In Title Case}
```

- Keep under 70 characters
- Use Title Case for all words after the colon
- Omit `[TICKET-ID]` if none provided

**Description Format (use bold headings with emoji, no ## markdown):**

```
**📝 Description**
[What problem does this solve? What is the user impact?]

**🛠️ Technical Implementation**
[How was it built? Stack, architecture decisions, key files changed.]

**✅ Testing**
[Steps to verify manually or via unit tests.]

**📋 Checklist**
- [ ] Code review passed
- [ ] No TypeScript errors (`bun type-check`)
- [ ] Format + lint passed (`bun fl`)
- [ ] Tests added/updated for changed collections or utils
- [ ] `bun generate:types` run after any collection/global schema change
- [ ] JSDoc added/updated for all exported functions
- [ ] [Any migration, env var, or follow-up noted]
```

---

## Step 3: Preview & Confirm

Show the generated title and description in a fenced code block.

Ask: **"Does the title and description look correct? (Yes / No)"**

- **No** → Ask what to change, regenerate, return to Step 3
- **Yes** → Proceed to Step 4

---

## Step 4: Create PR

Run:

```bash
gh pr create --title "<generated title>" --body "<generated description>" --base main
```

Output the PR URL when done.

Ask: **"PR created successfully. Anything you'd like to change or add?"**
