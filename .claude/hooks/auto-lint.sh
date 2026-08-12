#!/usr/bin/env bash
# Runs oxlint on modified TypeScript files after every write.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FILE="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"

if [[ -z "$FILE" ]] || [[ ! -f "$FILE" ]]; then
  exit 0
fi

EXT="${FILE##*.}"

case "$EXT" in
  ts|tsx)
    if OXLINT="$(resolve_tool oxlint)"; then
      # shellcheck disable=SC2086 -- OXLINT may be "bunx oxlint", word splitting intended
      run_capped 10 $OXLINT -c oxlint.json --ignore-path=.oxlintignore "$FILE" 2>&1 || true
    fi
    ;;
  json)
    if command -v python3 &>/dev/null; then
      python3 -c "import json,sys; json.load(sys.stdin)" < "$FILE" 2>&1 && echo "[auto-lint] $FILE JSON valid" || echo "[auto-lint] WARNING: $FILE has JSON syntax errors" >&2
    fi
    ;;
esac

exit 0
