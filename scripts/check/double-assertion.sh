#!/usr/bin/env bash
# Refuses a TypeScript double assertion through `unknown` (`x as unknown as T`), which switches off
# the compiler's overlap check. Rule and alternatives: .claude/rules/typescript/types.md.
# Scans tracked and untracked, not ignored, *.ts/*.tsx/*.mts/*.cts outside generated/ and
# node_modules/. A repo with no TypeScript passes.
set -uo pipefail
top="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$top" ] || ! cd "$top"; then
  echo "::error::double-assertion: not inside a git work tree" >&2
  exit 2
fi

hits="$(git grep --untracked -nE 'as[[:space:]]+unknown[[:space:]]+as[[:space:]]' -- \
  '*.ts' '*.tsx' '*.mts' '*.cts' ':!**/generated/**' ':!node_modules/**')"
status=$?
# git grep: 0 found something, 1 found nothing, anything else could not search.
if [ "$status" -gt 1 ]; then
  echo "::error::double-assertion: git grep failed (exit $status)" >&2
  exit 2
fi

if [ -n "$hits" ]; then
  printf '%s\n' "$hits"
  echo "::error::double assertion through unknown - use a real object, a complete fixture, or a narrower parameter type (.claude/rules/typescript/types.md)"
  exit 1
fi
echo "double-assertion: none"
