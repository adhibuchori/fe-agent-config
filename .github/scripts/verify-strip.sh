#!/usr/bin/env bash
# Asserts prod lost the stripped paths and dev still carries them.
# Shared by strip-ai-on-pr.yml and /promote-dokploy — see README § CI/CD.
set -euo pipefail

cd "$(dirname "$0")/../.."

# STRIP_PATHS, STRIP_GLOBS, LIST and `set -f` come from here so all three strip scripts agree.
. .github/scripts/strip-paths.sh

git fetch origin prod

# shellcheck disable=SC2086 -- one pathspec per word
remaining=$(git ls-tree -r --name-only origin/prod -- $STRIP_PATHS)
for glob in $STRIP_GLOBS; do
  remaining="${remaining}$(git ls-tree -r --name-only origin/prod -- "$glob")"
done
if [ -n "$remaining" ]; then
  echo "::error::These paths are still tracked on prod after the strip:"
  echo "$remaining"
  exit 1
fi
echo "prod carries none of the stripped paths."

# The mirror assertion: the strip is only half correct if dev lost them too.
# Silence here is what let dev lose its whole AI config unnoticed.
[ -s "$LIST" ] || { echo "Nothing was stripped."; exit 0; }
git fetch origin dev
missing=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  git cat-file -e "origin/dev:$f" 2>/dev/null || missing="${missing}"$'\n'"  $f"
done < "$LIST"
if [ -n "$missing" ]; then
  printf '::error::Stripped from prod but also missing on dev:%s\n' "${missing//$'\n'/%0A}"
  exit 1
fi
echo "dev still carries every stripped path."
