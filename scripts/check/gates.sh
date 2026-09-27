#!/usr/bin/env bash
# Runs this repo's gates from scripts/check/gates.list: one log per gate, a table at the end, and
# the tail of every failure. .husky/pre-commit runs it with --hook; CLAUDE.md § Quality Gates says
# when to run it by hand. This header is the reference.
#
#   gates.sh                   every gate, read-only: formatting is checked, never written
#   gates.sh --paths P...      format and lint only P (your files); every other gate as usual
#   gates.sh --only TEXT       only the gates whose command contains TEXT
#   gates.sh --fix P...        rewrite P with this repo's formatter, then stop
#   gates.sh --hook            pre-commit: staged files only, gates chosen by what is staged
#   --fail-fast                stop at the first failing gate
#
# gates.list lines are "<kinds><TAB><command>". Kinds say which staged files need the gate: docs
# (markdown under .claude/, root and PR templates, content/ pages), commands (_workflow-source,
# commands, agents, skills), hooks (.claude/hooks, settings.json, the hook probes, and the unlock and
# .env helpers the probes run), or all. A staged file of any other kind is code. Staged code runs
# every line except a hooks-only one: the hook probes take minutes, so only a staged hooks file
# runs them. Without --hook every line runs. Blank lines and lines starting with # are skipped.
#
# @format is the built-in read-only format and lint check for Node repos. It reads the formatter's
# scope from package.json's `format` script (oxfmt) and the linter's flags and scope from `fl:ci`
# (oxlint); with no file list it runs `<package manager> run fl:ci`. A repo without package.json
# lists its own format commands instead of @format.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

LIST=scripts/check/gates.list
MODE=all FAIL_FAST=0 ONLY="" PATHS=()
while [ $# -gt 0 ]; do
  case "$1" in
  --hook) MODE=hook ;;
  --fail-fast) FAIL_FAST=1 ;;
  --only) ONLY="${2:-}" && shift ;;
  --paths) MODE=paths ;;
  --fix) MODE=fix ;;
  -*) echo "gates: unknown option $1" >&2 && exit 2 ;;
  *) PATHS+=("$1") ;;
  esac
  shift
done
[ -f "$LIST" ] || { echo "gates: $LIST not found" >&2; exit 2; }

# The package manager that runs package.json scripts: GATES_PM, else the lockfile's.
package_manager() {
  if [ -n "${GATES_PM:-}" ]; then echo "$GATES_PM"
  elif [ -f bun.lock ] || [ -f bun.lockb ]; then echo bun
  elif [ -f pnpm-lock.yaml ]; then echo pnpm
  elif [ -f yarn.lock ]; then echo yarn
  else echo npm
  fi
}

# Format and lint exactly the files given, read-only unless FIX=1. The formatter's scope comes from
# the repo's own `format` script and the linter's flags and scope from `fl:ci`, so one script serves
# repos that format the whole tree and repos that format only src and scripts.
format_files() {
  FIX="${FIX:-0}" python3 - "$@" <<'PY'
import json, os, re, shlex, subprocess, sys
if not os.path.isfile("package.json"):
    sys.exit("gates: @format needs package.json; list this repo's own format command in gates.list")
files = [f for f in sys.argv[1:] if os.path.isfile(f)]
scripts = json.load(open("package.json")).get("scripts", {})
fix = os.environ.get("FIX") == "1"

def tokens(cmd, tool):
    # shlex, as the shell would: a quoted 'src/**/*.ts' reaches the tool without its quotes.
    for part in cmd.split("&&"):
        words = shlex.split(part)
        if words and words[0] == tool:
            return words[1:]
    return None

def glob_re(pattern):
    """A scope glob as a regex: ** crosses folders, * and ? do not, {a,b} is either."""
    out, depth, i = "", 0, 0
    while i < len(pattern):
        c = pattern[i]
        if pattern.startswith("**/", i):
            out, i = out + "(?:.*/)?", i + 3
            continue
        if pattern.startswith("**", i):
            out, i = out + ".*", i + 2
            continue
        if c == "{":
            out, depth = out + "(?:", depth + 1
        elif c == "}" and depth:
            out, depth = out + ")", depth - 1
        elif c == "," and depth:
            out += "|"
        else:
            out += {"*": "[^/]*", "?": "[^/]"}.get(c, re.escape(c))
        i += 1
    return re.compile(out + r"\Z")

def split(words, valued=("-c", "--config", "--tsconfig", "--ignore-path")):
    flags, scope, i = [], [], 0
    while i < len(words):
        w = words[i]
        if w in valued and i + 1 < len(words):
            flags += [w, words[i + 1]]
            i += 2
            continue
        (flags if w.startswith("-") else scope).append(w)
        i += 1
    return [f for f in flags if f not in ("--write", "--check")], scope

def inside(path, scope):
    return not scope or any(
        glob_re(s).match(path) if any(ch in s for ch in "*?{") else path == s or path.startswith(s.rstrip("/") + "/")
        for s in scope)

bin_dir = os.path.join("node_modules", ".bin")
fmt_words = tokens(scripts.get("format", ""), "oxfmt")
lint_words = tokens(scripts.get("fl:ci", ""), "oxlint")
if fmt_words is None or not os.path.exists(os.path.join(bin_dir, "oxfmt")):
    sys.exit("gates: no oxfmt `format` script or node_modules/.bin/oxfmt here (install dependencies first)")
status = 0
fmt_flags, fmt_scope = split(fmt_words)
to_format = [f for f in files if inside(f, fmt_scope)]
if to_format:
    mode = "--write" if fix else "--check"
    r = subprocess.run([os.path.join(bin_dir, "oxfmt"), mode, "--no-error-on-unmatched-pattern", *fmt_flags, *to_format])
    status |= r.returncode
if fix:
    sys.exit(status)
if lint_words is not None:
    lint_flags, lint_scope = split(lint_words)
    lintable = (".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs")
    to_lint = [f for f in files if f.endswith(lintable) and inside(f, lint_scope)]
    if to_lint:
        # A file the linter's ignore patterns exclude is not an error, as with oxfmt above.
        r = subprocess.run([os.path.join(bin_dir, "oxlint"), "--no-error-on-unmatched-pattern", *lint_flags, *to_lint])
        status |= r.returncode
print(f"format+lint: {len(to_format)} file(s) checked for format, read-only")
sys.exit(1 if status else 0)
PY
}

kind_of() {
  case "$1" in
  .claude/hooks/* | .claude/settings.json | scripts/check/hook-probes.*) echo hooks ;;
  # The probes run these helpers as the user would, and they are code the other gates read too.
  scripts/ops/unlock.sh | scripts/env/*) echo hooks code ;;
  _workflow-source/* | .claude/commands/* | .agent/workflows/* | .claude/agents/* | .claude/skills/* | .agents/skills/*) echo commands ;;
  .claude/* | .agents/rules/* | .mcp.json | .github/PULL_REQUEST_TEMPLATE/*.md) echo docs ;;
  content/*.md | content/*.mdx) echo docs ;;
  */*) echo code ;;
  *.md) echo docs ;;
  *) echo code ;;
  esac
}

if [ "$MODE" = fix ]; then
  [ ${#PATHS[@]} -gt 0 ] || { echo "gates: --fix needs the paths to format" >&2; exit 2; }
  FIX=1 format_files "${PATHS[@]}"
  exit $?
fi

# Which files @format sees, and which kinds of change are in play.
FILES=()
KINDS=" all "
case "$MODE" in
hook)
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "gates: --hook needs a git work tree" >&2; exit 2; }
  # --no-renames lists both sides of a rename, so moving code into .claude/ still reads as code.
  while IFS= read -r f; do
    [ -n "$f" ] && FILES+=("$f") && KINDS="$KINDS$(kind_of "$f") "
  done < <(git diff --cached --name-only --no-renames)
  if [ ${#FILES[@]} -eq 0 ]; then
    echo "gates: nothing staged"
    exit 0
  fi
  ;;
paths) FILES=(${PATHS[@]+"${PATHS[@]}"}) && KINDS=" all code docs commands hooks " ;;
*) KINDS=" all code docs commands hooks " ;;
esac

# One directory per run: two runs in the same second (two sessions, or a hook and a manual run)
# never share or overwrite each other's logs.
LOG_DIR="${TMPDIR:-/tmp}/gates/$(basename "$PWD")-${CLAUDE_CODE_SESSION_ID:-local}-$$-$(date +%s)"
mkdir -p "$LOG_DIR"
VITEST=0
[ -f package.json ] && grep -qE '"test:coverage": *"vitest' package.json && VITEST=1

names=() codes=() secs=() logs=()
n=0 failed=0
while IFS=$'\t' read -r kinds cmd || [ -n "${kinds:-}" ]; do
  case "$kinds" in '' | '#'*) continue ;; esac
  [ -n "$cmd" ] || { echo "gates: $LIST line without a TAB-separated command: $kinds" >&2; exit 2; }
  if [ -n "$ONLY" ] && [[ "$cmd" != *"$ONLY"* ]]; then continue; fi
  run=0
  for k in ${kinds//,/ }; do
    case "$KINDS" in *" $k "*) run=1 ;; esac
    # Staged code needs every other kind of gate as well, but not the hook probes: they take
    # minutes and prove only the files of the hooks kind.
    [ "$k" = hooks ] || case "$KINDS" in *" code "*) run=1 ;; esac
  done
  [ "$run" -eq 1 ] || continue

  n=$((n + 1))
  slug="$(printf '%s' "$cmd" | tr -c 'A-Za-z0-9' '-' | tr -s '-' | cut -c1-40)"
  log="$LOG_DIR/$(printf '%02d' "$n")-${slug%-}.log"
  start=$(date +%s)
  if [ "$cmd" = "@format" ]; then
    if [ ${#FILES[@]} -gt 0 ]; then
      format_files "${FILES[@]}" >"$log" 2>&1
    elif [ "$MODE" = hook ]; then
      echo "no files to format" >"$log"
    elif [ -f package.json ]; then
      "$(package_manager)" run fl:ci </dev/null >"$log" 2>&1
    else
      echo "gates: @format needs package.json; list this repo's own format command in gates.list" >"$log"
      false
    fi
    code=$?
  else
    # A second coverage run in the same checkout deletes the first one's coverage/.tmp mid-run.
    if [ "$VITEST" -eq 1 ] && [[ "$cmd" == *"run test:coverage"* ]]; then
      cmd="$cmd -- --coverage.reportsDirectory=$LOG_DIR/coverage"
    fi
    # </dev/null: the loop reads gates.list on stdin, and a gate that reads stdin would eat it.
    bash -c "$cmd" </dev/null >"$log" 2>&1
    code=$?
  fi
  names+=("$cmd") codes+=("$code") secs+=($(($(date +%s) - start))) logs+=("$log")
  if [ "$code" -ne 0 ]; then
    failed=$((failed + 1))
    [ "$FAIL_FAST" -eq 1 ] && break
  fi
done <"$LIST"

[ "$n" -gt 0 ] || { echo "gates: no gate in $LIST matched"; exit 0; }
printf '\n%-3s %-58s %4s %5s  %s\n' "#" "gate" "exit" "secs" "log"
for i in "${!names[@]}"; do
  printf '%-3s %-58s %4s %5s  %s\n' "$((i + 1))" "${names[$i]:0:58}" "${codes[$i]}" "${secs[$i]}" "$(basename "${logs[$i]}")"
done
for i in "${!names[@]}"; do
  [ "${codes[$i]}" -eq 0 ] && continue
  printf '\n── %s failed (exit %s), last 20 lines:\n' "${names[$i]}" "${codes[$i]}"
  tail -20 "${logs[$i]}"
done
printf '\n%d gate(s) ran, %d failed. Logs: %s\n' "$n" "$failed" "$LOG_DIR"
[ "$failed" -eq 0 ]
