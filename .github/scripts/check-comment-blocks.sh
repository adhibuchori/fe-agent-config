#!/usr/bin/env bash
# Caps consecutive comment runs under .github/ at 2 lines; shebangs are exempt.
# Overflow belongs in the README, not here. Usage: check-comment-blocks.sh

set -euo pipefail

cd "$(dirname "$0")/../.."

MAX=2
found=0

# These document themselves in place, and a trim would lose it; exact paths, so a new workflow
# is still held to the cap.
SHARED=" .github/workflows/workflows-lint.yml .github/workflows/dependency-review.yml .github/workflows/codeql.yml "

report() {
  printf '%s:%d — %d-line comment block (max %d)\n' "$1" "$2" "$3" "$MAX"
}

while IFS= read -r file; do
  case "$SHARED" in *" ${file#./} "*) continue ;; esac
  start=0
  count=0
  lineno=0

  # shellcheck disable=SC2094 # the loop only reads the file; report prints its name
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))

    # A shebang is not documentation; exempting it keeps a two-line header from
    # reading as three.
    if [ "$lineno" -eq 1 ] && [ "${line:0:2}" = "#!" ]; then
      continue
    fi

    stripped=${line#"${line%%[![:space:]]*}"}

    if [ "${stripped:0:1}" = "#" ]; then
      [ "$count" -eq 0 ] && start=$lineno
      count=$((count + 1))
      continue
    fi

    if [ "$count" -gt "$MAX" ]; then
      report "$file" "$start" "$count"
      found=$((found + 1))
    fi
    count=0
  done <"$file"

  if [ "$count" -gt "$MAX" ]; then
    report "$file" "$start" "$count"
    found=$((found + 1))
  fi
done < <(find .github -type f | sort)

if [ "$found" -gt 0 ]; then
  printf '\n%d comment block(s) over %d lines.\n' "$found" "$MAX"
  exit 1
fi

echo "All comment blocks under .github/ are $MAX lines or fewer."
