#!/usr/bin/env bash
# IS_SKELETON_SHOWN and its twin IS_LOADER_SHOWN hold wired screens on their loading state, for
# comparing a placeholder with the real layout; IS_ERROR_SHOWN holds wired lists on their error
# state. They are development switches: a commit with one on ships screens stuck on a placeholder
# or a failure. Part of the optional skeleton module (.claude/rules/web/skeletons.md); a switch is
# checked where its file exists, and a repo with none of them passes.
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 2

# Where the switches live. Change the paths here if your repo keeps them elsewhere.
SWITCHES="src/lib/constants/ui/skeleton-preview.ts:IS_SKELETON_SHOWN
src/lib/constants/ui/loader-preview.ts:IS_LOADER_SHOWN
src/lib/constants/ui/error-preview.ts:IS_ERROR_SHOWN"

failed=0
found=0
while IFS=: read -r file constant; do
  [ -f "$file" ] || continue
  found=$((found + 1))
  if grep -qE "^export const ${constant} = false;\$" "$file"; then
    echo "$constant is false"
  elif grep -q "$constant" "$file"; then
    echo "::error file=$file::$constant must be false in a commit: it holds every wired screen on its placeholder"
    failed=1
  else
    echo "::error file=$file::$constant is not declared here; update scripts/check/skeleton-switch.sh if it moved"
    failed=1
  fi
done <<EOF
$SWITCHES
EOF

[ "$found" -gt 0 ] || echo "no preview switch in this repo - nothing to check"
exit "$failed"
