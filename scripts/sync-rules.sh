#!/usr/bin/env bash
# Mirrors .claude/rules/ into .agents/rules/ so Antigravity IDE gets the same guardrails.
# One-way: .claude/rules/ is the source. Everything in .agents/rules/ except 00-read-first.md
# is generated — edit the source and re-run, never the target. See README § Agent Rules.
set -euo pipefail

cd "$(dirname "$0")/.."

# --check verifies without writing: exits non-zero when the target is stale, missing a rule, or
# holding an orphan. That is the mode that actually catches drift — the drift in .agent/workflows/
# happened because nobody ran the sync, a state a write-mode run can never observe.
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

SOURCE=".claude/rules"
TARGET=".agents/rules"

# Antigravity frontmatter key holding the glob patterns. Verified against a rule created
# through Customizations → Rules with trigger set to Glob. Change here if the format moves.
GLOB_KEY="globs"

# The Glob Pattern input in Customizations → Rules caps at 250 characters.
GLOB_MAX=250

# Hand-written, no counterpart under $SOURCE. Exempt from orphan detection.
HANDWRITTEN="00-read-first.md"

# Claude-Code-only content that would mislead an agent without that tooling:
#   */hooks.md            — PostToolUse/PreToolUse/Stop hook configuration
#   common/performance.md — Claude model selection and extended-thinking budgets
EXCLUDED="common/hooks.md react/hooks.md typescript/hooks.md web/hooks.md common/performance.md"

# trigger: model_decision needs a description for the model to judge relevance. Say WHEN the
# rule applies, not what it contains — a summary gives the model nothing to match a task against.
describe() {
  case "$1" in
  common/coding-style.md) echo "Read when writing or refactoring any code: immutability, KISS/DRY/YAGNI, file size limits, error handling." ;;
  common/testing.md) echo "Read when writing or changing tests: 80% coverage floor, TDD cycle, AAA structure, test naming." ;;
  common/security.md) echo "Read when handling user input, secrets, credentials, auth, or external API calls." ;;
  common/git-workflow.md) echo "Read when creating a branch, writing a commit message, or opening a pull request." ;;
  common/code-review.md) echo "Read before reviewing code or marking a task done: severity levels, security triggers, approval criteria." ;;
  common/development-workflow.md) echo "Read before starting a new feature: research-and-reuse step, planning, TDD order, pre-review checks." ;;
  common/patterns.md) echo "Read when choosing an implementation approach or evaluating an external library or template." ;;
  *) echo "" ;;
  esac
}

# Glob patterns for rules that carry no paths: block of their own upstream.
globs_for() {
  case "$1" in
  web/coding-style.md) printf '%s\n' '**/*.tsx' '**/*.jsx' '**/*.css' ;;
  web/design-quality.md) printf '%s\n' '**/*.tsx' 'src/components/**' ;;
  web/patterns.md) printf '%s\n' '**/*.tsx' 'src/hooks/**' 'src/store/**' ;;
  web/performance.md) printf '%s\n' '**/*.tsx' 'next.config.ts' ;;
  web/security.md) printf '%s\n' '**/*.tsx' 'next.config.ts' 'src/middleware.ts' ;;
  web/testing.md) printf '%s\n' '**/*.test.tsx' '**/*.spec.tsx' 'src/testing/**' ;;
  *) : ;;
  esac
}

has_frontmatter() { [ "$(head -1 "$1")" = "---" ]; }

# Re-reads what emit produced and asserts its shape. Every bug found while building this script
# was an emit-format bug that parsed as *something* and failed silently downstream: an unquoted
# `: ` in a description opened a nested mapping, and a YAML list of globs left the pattern field
# empty. Both looked fine in the file and vanished from the Rules panel with no error.
validate_fm() {
  local file="$1" rel="$2" line n=0
  while IFS= read -r line; do
    n=$((n + 1))
    [ "$n" -eq 1 ] && [ "$line" = "---" ] && continue
    [ "$line" = "---" ] && break
    case "$line" in
    'trigger: always_on' | 'trigger: model_decision' | 'trigger: glob') ;;
    'description: "'*'"' | 'globs: "'*'"') ;;
    *)
      echo "::error:: $rel emitted an unparseable frontmatter line: $line" >&2
      return 1
      ;;
    esac
  done <"$file"
  return 0
}

# List items inside the leading frontmatter block, unquoted. The dash must be followed by
# whitespace, otherwise the `---` delimiters themselves match and become `--` entries.
paths_of() {
  sed -n '/^---$/,/^---$/p' "$1" | sed -n 's/^[[:space:]]*-[[:space:]]\{1,\}//p' | tr -d "'\""
}

# Everything after the frontmatter, or the whole file when there is none.
body_of() {
  awk 'NR==1 && $0=="---" { fm=1; next }
       fm && /^---[[:space:]]*$/ { fm=0; next }
       fm { next }
       { print }' "$1"
}

emit() {
  local src="$1" rel="$2" desc patterns joined
  desc="$(describe "$rel")"

  printf -- '---\n'
  if [ -n "$desc" ]; then
    # Always quoted. A bare `: ` inside the text opens a nested mapping and the whole rule
    # fails to parse — Antigravity then drops it from the panel without any error.
    printf 'trigger: model_decision\ndescription: "%s"\n' "${desc//\"/\\\"}"
  else
    if has_frontmatter "$src"; then
      patterns="$(paths_of "$src")"
    else
      patterns="$(globs_for "$rel")"
    fi
    # A new rule file with neither a paths: block nor an entry in globs_for would
    # otherwise ship with no trigger and silently never load. Fail loudly instead.
    if [ -z "$patterns" ]; then
      echo "::error:: no trigger resolved for $rel — add it to globs_for() or describe()" >&2
      return 1
    fi
    # One comma-separated string, not a YAML list: the Glob Pattern field in Customizations →
    # Rules is a single 250-char input. A list parses as valid YAML but leaves the field empty,
    # so the rule never matches anything. Quoted because a bare leading `*` is a YAML alias.
    #
    # Joined with a read loop, never `printf '%s, ' $patterns` — unquoted expansion would run
    # pathname expansion and replace `src/hooks/**` with every file it currently matches.
    joined=""
    while IFS= read -r pattern; do
      [ -n "$pattern" ] || continue
      joined="${joined}${joined:+, }${pattern}"
    done <<<"$patterns"

    if [ "${#joined}" -gt "$GLOB_MAX" ]; then
      echo "::error:: glob string for $rel is ${#joined} chars, over the $GLOB_MAX field limit" >&2
      return 1
    fi
    printf 'trigger: glob\n%s: "%s"\n' "$GLOB_KEY" "$joined"
  fi
  printf -- '---\n\n'
  printf '<!-- Generated by scripts/sync-rules.sh from %s/%s — do not edit. -->\n\n' "$SOURCE" "$rel"
  # Sources with frontmatter already start their body with a blank line; collapse it so the
  # two paths produce identical spacing.
  body_of "$src" | sed '1{/^$/d;}'
}

if [ $CHECK -eq 1 ]; then
  echo "Checking $TARGET against $SOURCE (no writes)..."
else
  echo "Syncing rules from $SOURCE → $TARGET..."
fi
echo ""

mkdir -p "$TARGET"
SYNCED=0
NEW=0
SKIPPED=0
DRIFT=0
EXPECTED="$HANDWRITTEN"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

for src in "$SOURCE"/*/*.md; do
  rel="${src#"$SOURCE"/}"

  case " $EXCLUDED " in
  *" $rel "*)
    [ $CHECK -eq 0 ] && echo "  – excluded: $rel"
    SKIPPED=$((SKIPPED + 1))
    continue
    ;;
  esac

  out="$TARGET/${rel/\//-}"
  EXPECTED="$EXPECTED $(basename "$out")"
  SYNCED=$((SYNCED + 1))

  # Render to a temp file first so a failed emit cannot leave a truncated rule behind.
  emit "$src" "$rel" >"$TMP"
  validate_fm "$TMP" "$rel"

  if [ $CHECK -eq 1 ]; then
    if [ ! -f "$out" ]; then
      echo "  ⚠ missing: $(basename "$out")  (source: $rel)"
      DRIFT=$((DRIFT + 1))
    elif ! cmp -s "$TMP" "$out"; then
      echo "  ⚠ stale:   $(basename "$out")  (source: $rel)"
      DRIFT=$((DRIFT + 1))
    fi
    continue
  fi

  if [ -f "$out" ]; then
    cp "$TMP" "$out"
    echo "  ✓ updated: $(basename "$out")"
  else
    cp "$TMP" "$out"
    echo "  + added:   $(basename "$out")"
    NEW=$((NEW + 1))
  fi
done

# Orphan detection: present in the target with nothing under $SOURCE generating it — a rule
# that was renamed upstream, or newly excluded. sync-workflows.sh only has this direction.
for f in "$TARGET"/*.md; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  case " $EXPECTED " in
  *" $name "*) ;;
  *)
    echo "  ⚠ orphan:  $name"
    echo "    → nothing under $SOURCE generates it; delete it or restore its source"
    DRIFT=$((DRIFT + 1))
    ;;
  esac
done

echo ""
if [ $CHECK -eq 1 ]; then
  if [ $DRIFT -eq 0 ]; then
    echo "  ✓ Up to date. $SYNCED rules, $SKIPPED excluded."
  else
    echo "  $DRIFT issue(s). Run: bun sync:rules"
    exit 1
  fi
else
  echo "  Synced: $SYNCED | New: $NEW | Excluded: $SKIPPED"
  [ $DRIFT -gt 0 ] && exit 1
fi
exit 0
