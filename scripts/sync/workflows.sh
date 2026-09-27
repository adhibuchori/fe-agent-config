#!/usr/bin/env bash
# Mirrors _workflow-source/ into .agent/workflows/ and .claude/commands/.
# One-way: _workflow-source/ is the source - edit there, never the targets.
#
#   bash scripts/sync/workflows.sh           write the mirrors
#   bash scripts/sync/workflows.sh --check   verify only; exit 1 on any drift
#
# A subdirectory is a command namespace: _workflow-source/design/canvas.md is /design:canvas, and
# both mirrors keep the folder. Exits 0 when _workflow-source/ is absent (the prod strip removes it).
set -euo pipefail

cd "$(dirname "$0")/../.."

# --check verifies without writing: exits non-zero when a target is stale, an orphan appears, or
# INDEX.md has drifted from the command set. That is the mode that catches drift - a write-mode run
# overwrites staleness before it can observe it, so an unlisted command would go unnoticed.
CHECK=0
case "${1:-}" in
"") ;;
--check) CHECK=1 ;;
*) echo "usage: bash scripts/sync/workflows.sh [--check]" >&2 && exit 2 ;;
esac

SOURCE="_workflow-source"
TARGETS_ALL=(".agent/workflows" ".claude/commands")
INDEX="$SOURCE/INDEX.md"

if [ ! -d "$SOURCE" ]; then
  echo "$SOURCE/ not present on this branch - skipping"
  exit 0
fi

# Vendored third-party commands: installed into a target by their own installer, with no $SOURCE
# counterpart, and exempt from orphan and INDEX checks. Space-separated paths relative to the
# target, e.g. "tool/run.md". Never move a vendored command into $SOURCE; its installer owns it.
VENDORED=""

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

# Every .md under a directory, as a path relative to it. A subdirectory is a command namespace:
# Claude Code reads commands/design/canvas.md as /design:canvas, so the mirror has to keep the
# folder rather than flatten it.
md_files() {
  (cd "$1" && find . -type f -name '*.md' | sed 's#^\./##' | LC_ALL=C sort)
}

# design/canvas.md → /design:canvas
command_of() {
  local rel="${1%.md}"
  printf '/%s\n' "${rel//\//:}"
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

  while IFS= read -r name; do
    file="$SOURCE/$name"

    # INDEX.md is a Claude Code command palette; .agent/workflows/ has no use for it.
    if [ "$target" = ".agent/workflows" ] && [ "$name" = "INDEX.md" ]; then
      continue
    fi

    [ $CHECK -eq 1 ] || mkdir -p "$(dirname "$target/$name")"

    if [ $CHECK -eq 1 ]; then
      if [ ! -f "$target/$name" ]; then
        fail "missing: $target/$name"
      elif ! cmp -s "$file" "$target/$name"; then
        fail "stale: $target/$name"
      fi
    else
      [ -f "$target/$name" ] && verb="updated" || verb="added"
      cp "$file" "$target/$name"
      echo "  ✓ $verb: $name"
    fi

    SYNCED=$((SYNCED + 1))
  done < <(md_files "$SOURCE")

  [ $CHECK -eq 1 ] || echo "  Synced: $SYNCED"
  echo ""
done

# Orphans - present in a target with no $SOURCE counterpart, vendored commands excepted.
echo "Checking for orphans..."
for target in "${TARGETS_ALL[@]}"; do
  [ -d "$target" ] || continue
  while IFS= read -r name; do
    if [ "$name" = "INDEX.md" ]; then
      # Mirrored into .claude/commands/ only; a copy in .agent/workflows/ is never updated.
      [ "$target" = ".agent/workflows" ] && fail "orphan in $target: INDEX.md - delete it; the index lives in $SOURCE/"
      continue
    fi
    is_vendored "$name" && continue
    if [ ! -f "$SOURCE/$name" ]; then
      fail "orphan in $target: $name - move it to $SOURCE/ and re-run"
    fi
  done < <(md_files "$target")
done

# INDEX.md drift - every command needs a row, every row needs a command. Nothing else validates
# this, and the table is what an agent reads to discover the commands at all.
echo "Checking $INDEX coverage..."
if [ ! -f "$INDEX" ]; then
  fail "missing: $INDEX (a table with one | Category | Command | ... | row per command)"
  listed=""
else
  # Backticks are stripped along with spaces: some INDEX tables write the command as `/name` and
  # the parser must read the same set of rows either way, or every row reads as missing.
  listed=$(awk -F'|' '{ gsub(/[ `]/, "", $3); if ($3 ~ /^\//) print $3 }' "$INDEX")

  while IFS= read -r name; do
    [ "$name" = "INDEX.md" ] && continue
    cmd=$(command_of "$name")
    printf '%s\n' "$listed" | grep -qxF "$cmd" || fail "not listed in INDEX.md: $cmd"
  done < <(md_files "$SOURCE")

  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    name="${cmd#/}"
    name="${name//://}.md"
    [ -f "$SOURCE/$name" ] && continue
    is_vendored "$name" && continue
    fail "listed in INDEX.md but has no $SOURCE file: $cmd"
  done <<<"$listed"
fi

echo ""
if [ $FAILED -eq 0 ]; then
  echo "✓ All targets, orphans, and INDEX.md coverage are in sync with $SOURCE."
else
  echo "$FAILED problem(s) found."
  [ $CHECK -eq 1 ] && exit 1
  echo "Re-run without --check only fixes file contents; INDEX.md rows are hand-maintained."
  exit 1
fi
