#!/usr/bin/env bash
# Warns on design token violations before writing.

FILE="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"
CONTENT="${CLAUDE_TOOL_INPUT_CONTENT:-}"

if [[ -z "$FILE" ]] || [[ -z "$CONTENT" ]]; then
  exit 0
fi

# Only check .tsx, .ts, .css files
if [[ ! "$FILE" =~ \.(tsx|ts|css)$ ]]; then
  exit 0
fi

WARNINGS=()

# Hardcoded hex colors
if grep -qE '#[0-9a-fA-F]{3,6}' <<< "$CONTENT"; then
  WARNINGS+=("hardcoded hex color detected — use Tailwind semantic tokens (bg-card, text-foreground, etc.)")
fi

# Hardcoded font-size in px (non-Tailwind)
if grep -qE 'font-size:\s*[0-9]+px' <<< "$CONTENT"; then
  WARNINGS+=("hardcoded font-size px detected — use Tailwind text utilities (text-sm, text-base, etc.)")
fi

# Hardcoded font-family
if grep -qE "font-family:\s*['\"]" <<< "$CONTENT"; then
  WARNINGS+=("hardcoded font-family detected — use Tailwind font utilities (font-sans, font-mono)")
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo "[token-guard] WARNING in $FILE:" >&2
  for w in "${WARNINGS[@]}"; do
    echo "  ⚠ $w" >&2
  done
fi

exit 0
