#!/usr/bin/env bash
# Warns when only one locale file is modified in the current session.
# Does not block (exit 0 always) — warns to Claude directly.

FILE="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"

if [[ -z "$FILE" ]]; then
  exit 0
fi

EN_FILE="src/messages/en.json"
ID_FILE="src/messages/id.json"

# Only trigger when a messages file is modified
if [[ ! "$FILE" =~ src/messages/(en|id)\.json$ ]]; then
  exit 0
fi

# Check git status for the other locale file
if [[ "$FILE" == *en.json* ]]; then
  OTHER="$ID_FILE"
  MODIFIED_LANG="en"
  OTHER_LANG="id"
else
  OTHER="$EN_FILE"
  MODIFIED_LANG="id"
  OTHER_LANG="en"
fi

# Check if the other file has been modified in this session (git diff)
if ! git diff --name-only HEAD 2>/dev/null | grep -q "$OTHER"; then
  if ! git diff --cached --name-only 2>/dev/null | grep -q "$OTHER"; then
    echo "[i18n-sync] ⚠ WARNING: $MODIFIED_LANG.json was modified but $OTHER_LANG.json was not." >&2
    echo "[i18n-sync]   §E Rule 21: both locale files must be updated in the same commit." >&2
    echo "[i18n-sync]   Remember to update $OTHER before committing." >&2
  fi
fi

exit 0
