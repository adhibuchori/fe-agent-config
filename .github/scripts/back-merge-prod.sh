#!/usr/bin/env bash
# Back-merges prod into dev, re-instating the stripped AI config.
# Shared by strip-ai-on-pr.yml and /promote-dokploy — see README § CI/CD.
set -euo pipefail

cd "$(dirname "$0")/../.."

# STRIP_PATHS, STRIP_GLOBS, LIST, GIT_BOT_IDENTITY and `set -f` come from here, so all three
# strip scripts agree on both the paths and the committer.
. .github/scripts/strip-paths.sh

# The dev checkout below refuses to overwrite these untracked leftovers.
# shellcheck disable=SC2086 -- one pathspec per word
git clean -fdq -- $STRIP_PATHS $STRIP_GLOBS || true

git fetch origin dev prod
git checkout dev
BEFORE=$(git rev-parse HEAD)

# Settle the genuine no-op here, so that further down a missing MERGE_HEAD can only mean the merge
# itself failed. It used to mean both, and that is how an identity error passed as "nothing to do".
if git merge-base --is-ancestor origin/prod HEAD; then
  echo "prod is already an ancestor of dev; nothing to back-merge."
  exit 0
fi

git "${GIT_BOT_IDENTITY[@]}" merge --no-commit --no-ff origin/prod || true

# Re-instate whatever the merge would delete — that is the AI config the strip
# removed from prod, and dev is where it belongs.
git diff --cached --diff-filter=D --name-only "$BEFORE" | while read -r f; do
  [ -n "$f" ] && git checkout "$BEFORE" -- "$f"
done

# Same for modify/delete conflicts — keep dev's copy.
git diff --name-only --diff-filter=U | while read -r f; do
  [ -n "$f" ] && git checkout "$BEFORE" -- "$f" && git add "$f"
done

# Anything still conflicted is a genuine content clash, not strip fallout.
# Stop rather than push a guess.
REMAINING=$(git diff --name-only --diff-filter=U)
if [ -n "$REMAINING" ]; then
  echo "::error::Back-merge hit conflicts outside the stripped paths; resolve manually:"
  echo "$REMAINING"
  git merge --abort || true
  exit 1
fi

if [ ! -f .git/MERGE_HEAD ]; then
  echo "::error::Merge of origin/prod left no MERGE_HEAD, so the back-merge never ran. prod is not"
  echo "::error::an ancestor of dev, so this is a real failure — check the merge output above."
  exit 1
fi

git "${GIT_BOT_IDENTITY[@]}" commit -m "chore: back-merge prod into dev after AI strip [skip ci]"

# Merge, never rebase: the commit above is a merge commit, and rebase drops it —
# the push then reports "Everything up-to-date" and lies.
for attempt in 1 2 3; do
  if git "${GIT_BOT_IDENTITY[@]}" pull --no-rebase --no-edit origin dev && git push origin dev; then
    echo "dev is now up to date with prod."
    exit 0
  fi
  git merge --abort 2>/dev/null || true
  echo "push rejected (attempt ${attempt}/3); dev moved underneath us, retrying."
  sleep 5
done

echo "::error::Could not push the back-merge after 3 attempts."
exit 1
