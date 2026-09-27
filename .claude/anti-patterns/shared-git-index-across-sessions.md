# One checkout, several sessions, one `.git/index`

**Applies to:** Any repo worked by more than one agent session at a time
**Status:** Permanent (git design: the index belongs to the worktree, not to the process)

## Symptom

You stage two files and `git diff --cached` shows six. Or a commit named for one concern lands
carrying someone else's half-finished work. Or `git status` reports a file staged while
`git diff --cached` comes back empty.

Each of these reads as "the tooling is lying": a pre-commit hook secretly re-staging, or a wrapper
returning stale output. Test that before arguing it; the usual cause is the index.

## Root cause

`.git/index` belongs to the **worktree**, not to the process. Sessions sharing a checkout share one
index. Every `git add` from every session accumulates there, and `git commit`, which commits the
index, sweeps up whatever the others put there. An apparent stale read is usually a race: another
session's commit landed between two reads, and both reads were correct when taken.

## Fix

**Pass a pathspec to `git commit`.** It commits those paths from the working tree and ignores the
rest of the index, so nothing another session staged rides along:

```bash
bash scripts/check/gates.sh --fix <your paths>   # format only your files, outside the hook
git add <any new files>                          # a pathspec never reaches untracked files
git commit -F message.txt -- <your paths>
git show --stat HEAD                             # then read the file list
```

Two caveats, both silent:

- **A pathspec commits only paths git already tracks.** A brand-new file still needs `git add`
  first, or the commit silently lands without it.
- **A pathspec commit captures the worktree as it was when the command started.** A pre-commit
  hook that rewrote files would land its fixes in the worktree but not in the commit. That is why
  the hook here only checks (`gates.sh --hook`): an unformatted file fails the commit instead of
  slipping in. Format your own paths first, never the whole tree, where another session's work in
  progress lives too.

The last line binds. Everything above it reports intent; only reading the committed file list
reports the outcome, and after a push it is no longer fixable.

## Scope

Any concurrent work on one checkout. It does **not** apply to git worktrees: each has its own
index, which is the structural fix when sessions run long and independently.
[git-apply-check-passes-then-deletes.md](git-apply-check-passes-then-deletes.md) has the same
shape: the only reliable check is the state **after** the action.
