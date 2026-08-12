#!/usr/bin/env bash
# Sends macOS desktop notification for Claude Code events.

MESSAGE="${CLAUDE_NOTIFICATION_MESSAGE:-Task completed}"
TITLE="Claude Code"

if command -v osascript &>/dev/null; then
  osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\"" 2>/dev/null || true
fi

echo "[notify] $MESSAGE"
exit 0
