#!/usr/bin/env bash
# Runs oxfmt on modified files after every write.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FILE="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"

if [[ -z "$FILE" ]] || [[ ! -f "$FILE" ]]; then
  exit 0
fi

EXT="${FILE##*.}"

case "$EXT" in
  ts|tsx|js|jsx|json|css|md)
    if OXFMT="$(resolve_tool oxfmt)"; then
      # shellcheck disable=SC2086 -- OXFMT may be "bunx oxfmt", word splitting intended
      run_capped 5 $OXFMT --write "$FILE" >/dev/null 2>&1 || true
    fi
    ;;
esac

exit 0
