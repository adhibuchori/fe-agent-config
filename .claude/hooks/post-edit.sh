#!/usr/bin/env bash
# PostToolUse(Write|Edit|MultiEdit and Serena's writes): format, then lint, the file just written.
# One script, because hooks on one event run in parallel and a separate lint hook would race the
# formatter. A clean file says nothing; a finding reaches Claude as additionalContext.
#
# Every tool is the project's own: node_modules/.bin, .venv/bin, then PATH (resolve_tool). A tool
# the project does not have is skipped, so one copy serves TypeScript and Python repos alike. The
# file comes after `--`, so a name that starts with a dash is never read as an option.
#   *.py, *.pyi                              ruff format, then ruff check
#   *.ts *.tsx *.js *.jsx *.mjs *.cjs        oxfmt, then oxlint and the double-assertion note
#   *.json *.css *.md *.mdx                  oxfmt; *.json is also checked for valid JSON/JSONC
# Files that change together (localePairs in .claude/agent-config.json, off by default) are noted
# when only one of them changed.
#
# Fails open: feedback on a write that already happened. A missing tool, a payload it cannot read or
# a tool that fails means no note, and exit 0.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_start feedback "[post-edit]"
FILE="$(hook_file)"
[[ -n "$FILE" && -f "$FILE" ]] || exit 0
hook_adopt_repo "$FILE"
in_project "$FILE" || exit 0
REL="${FILE#"$ROOT"/}"

NOTES=""
note() {
  NOTES="${NOTES}${NOTES:+$'\n\n'}$*"
}

# Diagnostics are the `path:line:col:` lines. Summaries and "All checks passed!" are noise here.
diagnostics() {
  grep -E '^[^[:space:]]+:[0-9]+:[0-9]+:' || true
}

# 1. Format.
case "$REL" in
*.py | *.pyi)
  if RUFF="$(resolve_tool ruff)"; then
    run_capped 15 "$RUFF" format --quiet -- "$REL" >/dev/null 2>&1 || true
  fi
  ;;
*.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs | *.json | *.css | *.md | *.mdx)
  if OXFMT="$(resolve_tool oxfmt)"; then
    run_capped 10 "$OXFMT" --write -- "$REL" >/dev/null 2>&1 || true
  fi
  ;;
esac

# 2. Lint.
case "$REL" in
*.py | *.pyi)
  if RUFF="$(resolve_tool ruff)"; then
    out="$(run_capped 20 "$RUFF" check --output-format concise -- "$REL" 2>&1 | diagnostics)"
    [[ -z "$out" ]] || note "ruff check $REL:"$'\n'"$out"
  fi
  ;;
*.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs)
  if OXLINT="$(resolve_tool oxlint)"; then
    args=()
    # .oxlintrc.json is found by oxlint itself; oxlint.json has to be named.
    [[ -f oxlint.json ]] && args+=(-c oxlint.json)
    [[ -f .oxlintignore ]] && args+=(--ignore-path=.oxlintignore)
    out="$(run_capped 20 "$OXLINT" ${args[@]+"${args[@]}"} -f unix -- "$REL" 2>&1 | diagnostics)"
    [[ -z "$out" ]] || note "oxlint $REL:"$'\n'"$out"
  fi
  casts="$(grep -nE 'as[[:space:]]+unknown[[:space:]]+as[[:space:]]' -- "$REL" 2>/dev/null)"
  if [[ -n "$casts" ]]; then
    why="A double assertion through unknown hides a type error. Use a real object, a complete fixture, or a narrower parameter"
    [[ -f .claude/rules/typescript/types.md ]] && why="$why (.claude/rules/typescript/types.md)"
    note "$REL has a double assertion through unknown. $why:"$'\n'"$casts"
  fi
  ;;
*.json)
  # tsconfig and oxlint configs are JSONC: comments and trailing commas are valid there. Only an
  # answer of "invalid" makes a note: a python3 that fails says nothing about the file.
  if command -v python3 &>/dev/null; then
    valid="$(python3 -c '
import json, re, sys
try:
    text = open(sys.argv[1], encoding="utf-8").read()
    try:
        json.loads(text)
    except ValueError:
        text = re.sub(r"(\"(?:\\.|[^\"\\])*\")|//[^\n]*|/\*.*?\*/", lambda m: m.group(1) or "", text, flags=re.S)
        json.loads(re.sub(r",(\s*[}\]])", r"\1", text))
    print("valid")
except ValueError:
    print("invalid")' "$REL" 2>/dev/null)"
    [[ "$valid" != invalid ]] || note "$REL is not valid JSON."
  fi
  ;;
esac

# 3. Files that change together, from localePairs: each group is a list of repo-relative files.
changed() {
  git diff --name-only HEAD -- "$1" 2>/dev/null | grep -q . ||
    git diff --cached --name-only -- "$1" 2>/dev/null | grep -q . ||
    git ls-files --others --exclude-standard -- "$1" 2>/dev/null | grep -q .
}
while IFS= read -r line; do
  [[ "$line" == *$'\t'* ]] || continue
  group=()
  mine=""
  while IFS= read -r member; do
    [[ -n "$member" ]] || continue
    group+=("$member")
    [[ "$member" == "$REL" ]] && mine=1
  done < <(tr '\t' '\n' <<<"$line")
  [[ -n "$mine" ]] || continue
  for other in "${group[@]}"; do
    [[ "$other" != "$REL" ]] || continue
    changed "$other" || note "$REL changed but $other did not. These files change in the same commit (localePairs)."
  done
done < <(hook_config localePairs 2>/dev/null)

# 4. Alembic scaffolding is hand-edited legitimately, but it shapes every future revision.
if [[ -f alembic.ini && "$REL" =~ (^|/)(env\.py|script\.py\.mako)$ && -d "$(dirname "$REL")/versions" ]]; then
  note "$REL is Alembic scaffolding: this change affects every future revision."
fi

report "$NOTES"
exit 0
