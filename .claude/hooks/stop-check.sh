#!/usr/bin/env bash
# Session summary on Claude stop: modified files, lint status, open checklist.

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Claude Code — Session Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Modified files
MODIFIED=$(git diff --name-only HEAD 2>/dev/null)
STAGED=$(git diff --cached --name-only 2>/dev/null)
if [[ -n "$MODIFIED" ]] || [[ -n "$STAGED" ]]; then
  echo ""
  echo "📝 Modified files:"
  { echo "$STAGED"; echo "$MODIFIED"; } | sort -u | grep -v '^$' | sed 's/^/  /'
else
  echo ""
  echo "📝 No uncommitted changes."
fi

# Lint status on .ts/.tsx files
TS_FILES=$(git diff --name-only HEAD 2>/dev/null | grep -E '\.(ts|tsx)$' | head -5)
if [[ -n "$TS_FILES" ]] && [[ -x ./node_modules/.bin/oxlint ]]; then
  echo ""
  echo "🔍 Lint check:"
  echo "$TS_FILES" | xargs ./node_modules/.bin/oxlint -c oxlint.json --ignore-path=.oxlintignore 2>&1 | tail -5 || true
fi

# Open checklist
echo ""
echo "✅ Before pushing, verify:"
echo "  □ bun fl          (format + lint)"
echo "  □ bun type-check  (TypeScript)"
echo "  □ bun check:i18n  (unused keys + sync)"
echo "  □ bun test        (vitest)"
echo ""

exit 0
