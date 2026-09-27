#!/usr/bin/env bash
# Removes AI/dev-only config from prod and pushes the result.
# Shared by strip-ai-on-pr.yml and /promote-deploy; why: https://github.com/adhibuchori/fe-agent-config#cicd
set -euo pipefail

cd "$(dirname "$0")/../.."

# STRIP_PATHS, STRIP_GLOBS, LIST, GIT_BOT_IDENTITY and `set -f` come from here, so all three
# strip scripts agree on both the paths and the committer.
. .github/scripts/strip-paths.sh

# shellcheck disable=SC2086 # unquoted on purpose, one pathspec per word
git rm -rf --cached --ignore-unmatch $STRIP_PATHS
for glob in $STRIP_GLOBS; do
  git rm --cached --ignore-unmatch "$glob"
done

# Record what was really tracked, not the STRIP_PATHS wishlist — verify-strip.sh
# asserts against this list, and an empty one means the strip did nothing.
git diff --cached --name-only --diff-filter=D > "$LIST"
wc -l < "$LIST" | xargs echo "paths stripped:"

if git diff --cached --quiet; then
  echo "No AI config files to remove."
  exit 0
fi

# No skip-CI marker: a push starts no workflow here, so a marker would prevent nothing, and no
# script or command in this repo writes one.
git "${GIT_BOT_IDENTITY[@]}" commit -m "chore: strip AI/MCP config files for prod"

# git rm --cached leaves the stripped paths untracked, and a rebase refuses to clobber them.
# shellcheck disable=SC2086 # one pathspec per word
git clean -fdq -- $STRIP_PATHS $STRIP_GLOBS || true

# Anything else pushing to prod makes a rejected push expected rather than fatal.
for attempt in 1 2 3; do
  if git "${GIT_BOT_IDENTITY[@]}" pull --rebase origin prod && git push origin prod; then
    exit 0
  fi
  # Clear a half-finished rebase, or every later attempt fails with
  # "rebase in progress" instead of retrying.
  git rebase --abort 2>/dev/null || true
  # shellcheck disable=SC2086 # one pathspec per word
  git clean -fdq -- $STRIP_PATHS $STRIP_GLOBS || true
  echo "push rejected (attempt ${attempt}/3); prod moved underneath us, retrying."
  sleep 5
done

echo "::error::Could not push the strip commit after 3 attempts."
exit 1
