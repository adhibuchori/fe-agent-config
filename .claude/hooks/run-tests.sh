#!/usr/bin/env bash
# Runs vitest on the test that covers the modified source file.
#
# Tests in this repo are NOT co-located. They mirror the source tree under src/testing/:
#   src/lib/validations/contact.ts -> src/testing/lib/validations/contact.test.ts
# A co-located sibling is still honoured as a fallback in case that convention changes.

FILE="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"

if [[ -z "$FILE" ]] || [[ ! -f "$FILE" ]]; then
  exit 0
fi

# Only run for .ts/.tsx source files, never for test files themselves
if [[ "$FILE" =~ \.(test|spec)\.(ts|tsx)$ ]]; then
  exit 0
fi

if [[ ! "$FILE" =~ \.(ts|tsx)$ ]]; then
  exit 0
fi

# Reduce to the path below src/ — the hook may receive an absolute path
REL="${FILE##*/src/}"
if [[ "$REL" == "$FILE" ]]; then
  REL="${FILE#src/}"
  [[ "$REL" == "$FILE" ]] && exit 0 # not under src/ at all
fi

# Already inside the test tree — nothing to map
if [[ "$REL" == testing/* ]]; then
  exit 0
fi

BASE="src/testing/${REL%.*}"
EXT="${REL##*.}"
CO_BASE="${FILE%.*}"
TEST_FILE=""

# Mirrored test first, then co-located fallback
for CANDIDATE in \
  "${BASE}.test.${EXT}" "${BASE}.spec.${EXT}" "${BASE}.test.ts" "${BASE}.spec.ts" \
  "${CO_BASE}.test.${EXT}" "${CO_BASE}.test.ts"; do
  if [[ -f "$CANDIDATE" ]]; then
    TEST_FILE="$CANDIDATE"
    break
  fi
done

if [[ -z "$TEST_FILE" ]]; then
  exit 0
fi

echo "[run-tests] Running tests for $TEST_FILE"

# macOS ships without GNU timeout; gtimeout comes from coreutils. Fall back to no cap
# rather than dying with "command not found".
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT=(timeout 30)
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT=(gtimeout 30)
else
  TIMEOUT=()
fi

"${TIMEOUT[@]}" bun run test "$TEST_FILE" 2>&1 | tail -10 || true

exit 0
