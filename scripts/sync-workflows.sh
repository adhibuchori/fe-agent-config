#!/usr/bin/env bash
# Mirrors _workflow-source/ into .agent/workflows/ and .claude/commands/.
# One-way: _workflow-source/ is the source — edit there, never the targets.
set -euo pipefail

cd "$(dirname "$0")/.."

# --check verifies without writing: exits non-zero when a target is stale, an orphan appears, or
# INDEX.md has drifted from the command set. That is the mode that catches drift — a write-mode run
# overwrites staleness before it can observe it, which is how three commands went unlisted for so long.
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

SOURCE="_workflow-source"
TARGETS_ALL=(".agent/workflows" ".claude/commands")
INDEX="$SOURCE/INDEX.md"

# Vendored third-party skills. Their own installer (npx impeccable install) writes a per-harness
# build into .claude/skills/ + .agents/skills/ and drops a command shim in .claude/commands/, so
# they have no $SOURCE counterpart by design. Never move them into $SOURCE — the installer owns
# their version, and syncing would fight the next upgrade. Exempt from orphan detection.
VENDORED="impeccable.md"

FAILED=0

is_vendored() {
  for v in $VENDORED; do
    [ "$1" = "$v" ] && return 0
  done
  return 1
}

fail() {
  printf '  ✗ %s\n' "$1"
  FAILED=$((FAILED + 1))
}

if [ $CHECK -eq 1 ]; then
  echo "Checking workflows against $SOURCE (no writes)..."
else
  echo "Syncing workflows from $SOURCE..."
fi
echo ""

for target in "${TARGETS_ALL[@]}"; do
  echo "→ $target"
  [ $CHECK -eq 1 ] || mkdir -p "$target"
  SYNCED=0

  for file in "$SOURCE"/*.md; do
    name=$(basename "$file")

    # INDEX.md is a Claude Code command palette; .agent/workflows/ has no use for it.
    if [ "$target" = ".agent/workflows" ] && [ "$name" = "INDEX.md" ]; then
      continue
    fi

    if [ $CHECK -eq 1 ]; then
      if [ ! -f "$target/$name" ]; then
        fail "missing: $name"
      elif ! cmp -s "$file" "$target/$name"; then
        fail "stale: $name"
      fi
    else
      [ -f "$target/$name" ] && verb="updated" || verb="added"
      cp "$file" "$target/$name"
      echo "  ✓ $verb: $name"
    fi

    SYNCED=$((SYNCED + 1))
  done

  [ $CHECK -eq 1 ] || echo "  Synced: $SYNCED"
  echo ""
done

# Orphans — present in a target with no $SOURCE counterpart, vendored skills excepted.
echo "Checking for orphans..."
for target in "${TARGETS_ALL[@]}"; do
  for file in "$target"/*.md; do
    [ -f "$file" ] || continue
    name=$(basename "$file")
    [ "$name" = "INDEX.md" ] && continue
    is_vendored "$name" && continue
    if [ ! -f "$SOURCE/$name" ]; then
      fail "orphan in $target: $name — move it to $SOURCE/ and re-run"
    fi
  done
done

# INDEX.md drift — every command needs a row, every row needs a command. Nothing else validates
# this, and the table is what an agent reads to discover the commands at all.
echo "Checking $INDEX coverage..."
# Backticks are stripped along with spaces: some INDEX tables write the command as `/name` and
# the parser must read the same set of rows either way, or every row reads as missing.
listed=$(awk -F'|' '{ gsub(/[ `]/, "", $3); if ($3 ~ /^\//) print $3 }' "$INDEX")

for file in "$SOURCE"/*.md; do
  name=$(basename "$file")
  [ "$name" = "INDEX.md" ] && continue
  cmd="/${name%.md}"
  printf '%s\n' "$listed" | grep -qxF "$cmd" || fail "not listed in INDEX.md: $cmd"
done

while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  name="${cmd#/}.md"
  [ -f "$SOURCE/$name" ] && continue
  is_vendored "$name" && continue
  fail "listed in INDEX.md but has no $SOURCE file: $cmd"
done <<< "$listed"

echo ""
if [ $FAILED -eq 0 ]; then
  echo "✓ All targets, orphans, and INDEX.md coverage are in sync with $SOURCE."
else
  echo "$FAILED problem(s) found."
  [ $CHECK -eq 1 ] && exit 1
  echo "Re-run without --check only fixes file contents; INDEX.md rows are hand-maintained."
  exit 1
fi
