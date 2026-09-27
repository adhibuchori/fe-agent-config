---
description: Creates a local safety commit of this session's changes, by pathspec, with an ISO timestamp, before a risky change. Commits only; never pushes.
---

<!-- Command: /checkpoint [description] -->
<!-- Source: _workflow-source/checkpoint.md -->
<!-- Run before any change that would be painful to unwind by hand -->

# /checkpoint — Safety Commit

1. On `dev`, `prod` or the default branch, stop and offer to branch to `internal/{scope}` first (the
   branch model in CLAUDE.md § Branching).
2. List what changed with `git status --short` (with RTK installed, `rtk proxy git status --short`:
   every path is needed), then stage the paths this session wrote, by name:
   `git add -- <paths>`. Never `git add -A`: staging everything is `/ship`'s alone, because only
   `/ship` runs the guards that make it safe. Name any changed file you did not write and leave it
   out. Never stage a `.env*` file other than an `.example` template.
3. Commit those paths only, with the message `chore: checkpoint — {description} [{ISO timestamp}]`:
   `git commit -m "<message>" -- <paths>`. Let the pre-commit hook run; never skip it.
4. Output the commit hash and the files it carried.

A checkpoint is unreviewed work in progress: it is never pushed from here. `/ship` reviews and
pushes.
