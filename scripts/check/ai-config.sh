#!/usr/bin/env bash
# The AI-config checks that pre-commit and the CI quality gate share, so a docs-only commit meets
# them before CI does. Exits 0 when .claude/ is absent: the prod strip removes it
# (.github/scripts/strip-paths.sh).
#
#   1. Every "Rule N" that the AI layer cites is defined in AGENTS.md. Read: root *.md, docs/**,
#      .claude/{agents,hooks,rules,docs,anti-patterns}/**, _workflow-source/**, .github/** and the
#      root lint config. A definition is a heading, bold or list lead ("### Rule N", "**Rule N**")
#      or a table row whose first cell is N, so a citation left behind by a renumbering fails even
#      when the old number still appears in prose. Skipped when the repo has no AGENTS.md.
#   2. CLAUDE.md (and .claude/CLAUDE.md) plus every rule without paths: fits the 15,000-byte
#      always-loaded budget, and CLAUDE.md has no @imports, not even inside an HTML comment.
#   3. No hook script in .claude/hooks/ (any file but *.md) reads CLAUDE_TOOL_INPUT_* (hooks get
#      their JSON payload on stdin), and every hook script .claude/settings.json runs exists and is
#      addressed through $CLAUDE_PROJECT_DIR.
#   4. No session notes are tracked, and every npx/bunx/uvx MCP server in .mcp.json and
#      .claude/mcp/*.json is pinned to one release: a full x.y.z version, a full commit SHA or a
#      digest. *.example.json files are templates to copy and fill in, so their placeholders are
#      not checked; the filled-in copy is. scripts/check/ai-config-probes.sh proves the pin rule.
#
# Checks 3 and 4 parse JSON with python3. Without python3 they fail; they never pass unread.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

if [ ! -d .claude ]; then
  echo ".claude/ not present on this branch - skipping"
  exit 0
fi
failed=0
HAVE_PY=0
command -v python3 >/dev/null 2>&1 && HAVE_PY=1

# ── 1. Rule citations ───────────────────────────────────────────────────────────────────────────
# scripts/ is not read: a check script may number its own rules (a lint's own "Rule N"), which are
# not AGENTS.md rules. Mirrors (.claude/commands, .agent/workflows) are read at their source.
citing_files() {
  local f
  for f in *.md .oxlintrc.json .oxlintrc.jsonc oxlint.json; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
  find .claude/agents .claude/hooks .claude/rules .claude/docs .claude/anti-patterns _workflow-source docs \
    -type f \( -name '*.md' -o -name '*.sh' \) 2>/dev/null
  find .github -type f \( -name '*.md' -o -name '*.yml' -o -name '*.yaml' -o -name '*.sh' \) 2>/dev/null
}

if [ ! -f AGENTS.md ]; then
  echo "AGENTS.md not present - rule-citation check skipped"
else
  # A definition is a heading, bold, bullet or numbered-list lead that starts with "Rule N", or a
  # table row whose first cell is N. Only the number at the start counts: "**Rule N** - see Rule M"
  # defines N, not M.
  defined="$(
    {
      sed -nE 's/^[[:space:]]*(#{1,6}[[:space:]]+|[-*+][[:space:]]+|[0-9]+[.)][[:space:]]+)?(\*\*|__)?Rule ([0-9]+)([^0-9].*)?$/\3/p' AGENTS.md
      sed -nE 's/^[[:space:]]*\|[[:space:]]*(\*\*|__)?(Rule )?([0-9]+)(\*\*|__)?[[:space:]]*\|.*$/\3/p' AGENTS.md
    } | sort -u
  )"
  stale=0
  scanned=0
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    scanned=$((scanned + 1))
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      if ! printf '%s\n' "$defined" | grep -qxF "$n"; then
        echo "::error file=$f::cites Rule $n, which AGENTS.md does not define"
        stale=1
      fi
    done < <(grep -oE 'Rule [0-9]+' "$f" | grep -oE '[0-9]+' | sort -u)
  done < <(citing_files | sort -u)
  if [ "$stale" -ne 0 ]; then
    failed=1
  else
    echo "All cited rule numbers are defined in AGENTS.md (${scanned} files read)"
  fi
fi

# ── 2. Always-loaded context budget ─────────────────────────────────────────────────────────────
# Every session loads CLAUDE.md, its @imports and each rule without paths:, so that set has a budget.
always=0
for memory in CLAUDE.md .claude/CLAUDE.md; do
  [ -f "$memory" ] || continue
  always=$((always + $(wc -c <"$memory" | tr -d ' ')))
  # An @import inside an HTML comment still reads as an import to a reviewer and to this check.
  if grep -nE '(^|[[:space:]])@[^[:space:]`]+\.md' "$memory"; then
    echo "::error file=$memory::an @import loads its file every session - list it under On-demand References"
    failed=1
  fi
done
while IFS= read -r rule; do
  if [ "$(head -1 "$rule")" = "---" ] && sed -n '2,/^---$/p' "$rule" | grep -q '^paths:'; then
    continue
  fi
  always=$((always + $(wc -c <"$rule" | tr -d ' ')))
done < <(find -L .claude/rules -type f -name '*.md' 2>/dev/null)
echo "Always-loaded context: ${always} bytes (budget 15000)"
if [ "$always" -gt 15000 ]; then
  echo "::error::always-loaded context is ${always} bytes, over the 15000-byte budget"
  failed=1
fi

# ── 3. Hooks: stdin contract and settings.json wiring ───────────────────────────────────────────
# Markdown in .claude/hooks/ documents the contract and may name the variable; scripts may not.
if grep -rlE --exclude='*.md' 'CLAUDE_TOOL_INPUT_' .claude/hooks 2>/dev/null; then
  echo "::error::a hook reads an environment variable Claude Code never sets - read the JSON payload on stdin"
  failed=1
fi
if [ -f .claude/settings.json ]; then
  if [ "$HAVE_PY" -eq 0 ]; then
    echo "::error::python3 not found - cannot verify the hook wiring in .claude/settings.json"
    failed=1
  else
    wiring="$(
      python3 - .claude/settings.json <<'PY'
import json, os, re, sys

path = sys.argv[1]
try:
    settings = json.load(open(path))
except (OSError, ValueError) as err:
    print(f"{path}: not valid JSON ({err})")
    sys.exit(0)
ref = re.compile(r"(\S*?)\.claude/hooks/([A-Za-z0-9_.-]+)")
for event, groups in (settings.get("hooks") or {}).items():
    for group in groups or []:
        for hook in (group or {}).get("hooks") or []:
            command = (hook or {}).get("command") or ""
            for prefix, name in ref.findall(command):
                if not os.path.isfile(os.path.join(".claude", "hooks", name)):
                    print(f"{path}: {event} runs .claude/hooks/{name}, which does not exist")
                if "CLAUDE_PROJECT_DIR" not in prefix:
                    print(f"{path}: {event} runs .claude/hooks/{name} by a relative path - use $CLAUDE_PROJECT_DIR")
PY
    )"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "::error::the settings.json wiring check crashed (exit $rc)"
      failed=1
    elif [ -n "$wiring" ]; then
      printf '%s\n' "$wiring" | sed 's/^/::error::/'
      failed=1
    fi
  fi
fi

# ── 4. Session notes and MCP pins ───────────────────────────────────────────────────────────────
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ -n "$(git ls-files .claude/session-feedback .claude/session-logs)" ]; then
    echo "::error::session notes are tracked - route learnings through /learn-session"
    failed=1
  fi
else
  echo "not a git work tree - tracked session-notes check skipped"
fi

# Every npx/bunx/uvx package spec names one release: @x.y.z or ==x.y.z (a leading v and a
# pre-release or build suffix allowed), a full commit SHA after @ or #, or an @sha256:/@sha512:
# digest. A bare name, a tag such as @latest, a range, a major-only @1 or a major.minor @1.2 all
# resolve to whatever was published last in them, and fail.
mcp_files=()
for f in .mcp.json .claude/mcp/*.json; do
  case "$f" in *.example.json) continue ;; esac
  [ -f "$f" ] && mcp_files+=("$f")
done
if [ ${#mcp_files[@]} -gt 0 ]; then
  if [ "$HAVE_PY" -eq 0 ]; then
    echo "::error::python3 not found - cannot verify that the MCP servers are pinned"
    failed=1
  else
    unpinned="$(
      python3 - "${mcp_files[@]}" <<'PY'
import json, re, sys

VERSION = r"v?\d+\.\d+\.\d+(?:[-+.]?[0-9A-Za-z][0-9A-Za-z.+-]*)?"
PINNED = re.compile(
    rf"((?:@|==){VERSION}|[@#](?:[0-9a-f]{{40}}|[0-9a-f]{{64}})|@sha256:[0-9a-f]{{64}}|@sha512:[0-9a-f]{{128}})$"
)
for path in sys.argv[1:]:
    try:
        servers = json.load(open(path)).get("mcpServers", {})
    except (OSError, ValueError, AttributeError) as err:
        print(f"{path}: not valid MCP JSON ({err})")
        continue
    for name, server in servers.items():
        args, cmd = list(server.get("args") or []), server.get("command")
        if cmd not in ("npx", "bunx", "uvx"):
            continue
        explicit = any(a in ("--from", "--package", "-p") or a.startswith("--package=") for a in args)
        specs, i = [], 0
        while i < len(args):
            arg = args[i]
            if arg in ("--from", "--with", "--package", "-p") and i + 1 < len(args):
                specs.append(args[i + 1])
                i += 2
            elif arg.startswith("--package="):
                specs.append(arg.split("=", 1)[1])
                i += 1
            elif arg.startswith("-"):
                i += 1
            else:
                if not explicit:
                    specs.append(arg)
                break
        if not specs:
            print(f"{path}: {name} names no package")
        for spec in specs:
            if not PINNED.search(spec):
                print(f"{path}: {name} runs {spec}")
PY
    )"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "::error::the MCP pin check crashed (exit $rc)"
      failed=1
    elif [ -n "$unpinned" ]; then
      printf '%s\n' "$unpinned"
      echo "::error::an MCP server is not pinned to one release - use a full x.y.z version, a full commit SHA or a digest"
      failed=1
    fi
  fi
fi

[ "$failed" -eq 0 ] && echo "AI config within budget"
exit "$failed"
