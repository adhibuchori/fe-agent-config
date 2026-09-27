# `git apply --check` passes, then the patch deletes the files

**Applies to:** Any patch built with `git diff --no-index`
**Status:** Permanent (git works as documented)

## Symptom

`git apply --check patch` exits 0. `git apply patch` reports nothing wrong, and `git status` shows:

```text
 D AGENTS.md
 D SSOT.md
?? var/
```

The files you meant to edit are gone, and copies of them sit under a directory named after the
machine's temp path.

## Root cause

`git diff --no-index a b` writes the **literal paths it was given** into the diff header. Copy a
file to a temp directory, diff against it, and the header reads:

```text
--- a/SSOT.md
+++ b/var/folders/<temp>/SSOT.md
```

`git apply` reads that as one instruction: delete `SSOT.md`, create `var/folders/<temp>/SSOT.md`.
It is not a malformed patch; it is a valid patch for a rename nobody intended, so nothing warns.
Rewriting the `a/` side and missing the `b/` side is easy, because the `b/` path is long and scrolls
off.

## Why `--check` does not save you

`git apply --check` answers "can this patch be applied cleanly?", not "is this the change you
meant?". A delete-and-recreate applies perfectly cleanly. **A green `--check` is a merge-conflict
test, not a safety net.** That is the trap: the natural precaution is taken, it passes, and the
outcome is still destructive.

## Fix

1. **Do not build patches with `git diff --no-index`.** Edit the target file directly, after
   asserting that the anchor text exists and is unique.
2. If a patch is unavoidable, read its `+++ b/` lines before applying. Every one must be a
   repo-relative path.
3. Whatever the route, read `git status` **after** applying. The post-state is the confirmation,
   not `--check`.

## Recovery, if it already happened

Nothing is lost when the files were tracked and committed:

```bash
git checkout -- SSOT.md AGENTS.md   # restore from HEAD
git clean -fd -- var                # scoped: only the stray tree
git diff --quiet HEAD -- SSOT.md AGENTS.md && echo restored
```

Scope the `clean` to the stray directory. A bare `git clean -fd` also removes untracked work that
belongs to someone else, which in a shared checkout is the more expensive mistake of the two.

## Scope

Any patch workflow. [shared-git-index-across-sessions.md](shared-git-index-across-sessions.md) has
the same shape: a check that passes up front while the outcome is still wrong.
