#!/usr/bin/env bash
# Proves the Claude Code hooks block what they must and let through what they must: every probe is
# fed to its hook the way Claude Code does it, JSON on stdin, and judged by exit code and output.
# A hook that never fires still exits 0, so only a probe that expects a block can tell it apart.
# Run it whenever a hook, lib.sh or .claude/settings.json changes; pre-commit and the quality gate
# run it too. Every fixture lives in a temp folder; the repo itself is never touched.
#
#   HOOKS_DIR=<dir>     the hooks to prove (default .claude/hooks)
#   PROBES_FILE=<file>  the safety-check probe table (default scripts/check/hook-probes.tsv)
#
# safety-check.sh is required; every other hook is proven when present and skipped when absent, so
# one copy of this script serves a repo with or without generated-guard.sh or migration-guard.sh.
# Beyond the rules it proves each hook's fail mode (a payload that is not JSON, python3 or jq
# missing, python3 broken, hanging or slow enough to reach a guard's deadline), symlinked files,
# linked git worktrees, the plugin-mode project gate and its sticky opt-in, and db-guard's reading
# of SQL. Where the repo ships scripts/ops/unlock.sh and scripts/env/, it runs
# them as the user would, checks that every reader of an unlock file agrees, and sends each
# forging route of docs/unlock.md through safety-check, running whatever gets through.
# Needs bash 3.2+, git and python3; jq is optional. Run it with /bin/bash on macOS to prove 3.2.
set -uo pipefail
# A pathspec commit hands pre-commit an absolute GIT_INDEX_FILE (.git/next-index-N.lock). Inherited,
# it sends every git call on the temp repos below into the real commit's index, which then fails to
# build its tree. The probes never need the outer repo's git environment.
unset GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
unset AGENT_WORKSPACE_ROOT CLAUDE_ENV_FILE HOOK_PROBE_CRASH HOOK_PROBE_NO_TEMP HOOK_PROBE_CAP
unset CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA
cd "$(dirname "$0")/../.." || exit 2

HOOKS="${HOOKS_DIR:-.claude/hooks}"
PROBES="${PROBES_FILE:-scripts/check/hook-probes.tsv}"
if [ ! -f "$HOOKS/safety-check.sh" ]; then
  echo "$HOOKS/safety-check.sh not present on this branch - skipping"
  exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "::error::python3 is required: the hooks' command parser and these probes run on it"
  exit 1
fi
HOOKS="$(cd "$HOOKS" && pwd -P)"
PROBES="$(cd "$(dirname "$PROBES")" && pwd -P)/$(basename "$PROBES")"
BASH_BIN="${BASH:-bash}"
for f in "$HOOKS"/*.sh; do
  "$BASH_BIN" -n "$f" || {
    echo "::error file=$f::bash cannot parse it, so every tool call it guards would be blocked"
    exit 1
  }
done
has() { [ -f "$HOOKS/$1" ]; }

TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# The fixtures get their own git identity and none of the user's git settings (signing, hooks).
cat >"$TMP/gitconfig" <<'EOF'
[user]
	email = probe@example.invalid
	name = probe
[commit]
	gpgsign = false
[init]
	defaultBranch = main
EOF
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
export AGENT_HOOK_STATE_DIR="$TMP/state"
pass=0 fail=0

# $1 dir, $2 branch: a git repo with one empty commit.
repo() {
  git init -q -b "$2" "$1" && git -C "$1" commit -q --allow-empty -m init
}

# The project every safety-check probe runs in (hook-probes.tsv § header).
P="$TMP/proj"
repo "$P" feature/probe
mkdir -p "$P/notes" "$P/docs" "$P/build"
echo keep >"$P/notes/keep.txt" && echo a >"$P/docs/a.md" && printf '[alembic]\n' >"$P/alembic.ini"
echo out >"$P/build/out.txt"
printf '.env\n.env.local\n.claude/state/\n' >"$P/.gitignore"
printf 'API_KEY=\n' >"$P/.env.example" && printf 'API_KEY=\n' >"$P/.env.production.example"
cat >"$P/package.json" <<'EOF'
{"scripts": {"unlock": "bash scripts/ops/unlock.sh", "u2": "bash scripts/ops/unlock.sh", "dump": "cat .env", "build": "echo build"}}
EOF
# Stand-ins for the unlock script and the env helpers, so globs in the table expand to them.
mkdir -p "$P/scripts/ops" "$P/scripts/env" "$P/scripts/check"
for f in scripts/ops/unlock.sh scripts/env/show.sh scripts/env/set.sh scripts/check/gates.sh; do printf '#!/bin/sh\n' >"$P/$f"; done
printf '\n' >"$P/scripts/env/envfile.py"
git -C "$P" add notes docs scripts alembic.ini .gitignore .env.example .env.production.example package.json
git -C "$P" commit -q -m fixture
# Secrets files the probes must never reach, ignored as in a real repo.
env_files() { printf 'API_KEY=probe-secret-value\n' >"$1/.env" && printf 'API_KEY=probe-local-value\n' >"$1/.env.local"; }
env_files "$P"
# A forged unlock tree and archives outside the project (hook-probes.tsv, "The unlock").
mkdir -p "$TMP/forged/.claude/state/unlock" "$TMP/plain-tree/sub"
printf '4102444800\n' >"$TMP/forged/.claude/state/unlock/env" && cp "$TMP/forged/.claude/state/unlock/env" "$TMP/token"
echo x >"$TMP/plain-tree/sub/x.txt"
tar -cf "$TMP/forged.tar" -C "$TMP/forged" .claude && tar -cf "$TMP/plain.tar" -C "$TMP" plain-tree
# A tree that would put its own show.sh in place of the trusted one.
# shellcheck disable=SC2016 # the $1 belongs to the script written
mkdir -p "$TMP/forged-helpers/scripts/env" && printf '#!/bin/sh\ncat "$1"\n' >"$TMP/forged-helpers/scripts/env/show.sh"
export CLAUDE_PROJECT_DIR="$P"

# A fixture checked out on branch $1, printed: its own repo, or with $2 set a linked worktree of one.
repo_on() {
  local d="$TMP/on-${1//\//-}${2:+-wt}"
  if [ ! -d "$d" ]; then
    if [ -n "${2:-}" ]; then
      repo "$d-main" feature/base && git -C "$d-main" worktree add -q -b "$1" "$d"
    else
      repo "$d" "$1"
    fi
  fi
  printf '%s' "$d"
}

# Every hook's stderr lands here, so a probe can read the reason it gave.
ERR="$TMP/stderr.txt"
verdict() {
  local expect="$1" code="$2" out="$3" label="$4" got=allow
  [ "$code" -eq 2 ] && got=block
  [ "$code" -eq 0 ] && [[ "$out" == *additionalContext* ]] && got=warn
  [ "$code" -ne 0 ] && [ "$code" -ne 2 ] && got="error"
  # ok: any exit 0, with or without context. quiet: exit 0 and nothing at all on stdout.
  [ "$expect" = ok ] && [ "$code" -eq 0 ] && got=ok
  [ "$expect" = quiet ] && [ "$code" -eq 0 ] && [ -z "$out" ] && got=quiet
  # refuse: a guard that could not do its job blocks, and says how to turn it off.
  [ "$expect" = refuse ] && [ "$code" -eq 2 ] && grep -q 'To turn the guard off' "$ERR" && got=refuse
  if [ "$got" = "$expect" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL expected $expect, got $got (exit $code): $label"
  fi
}

# JSON payloads, built by python3 so any quoting survives.
bash_json() { # $1 cwd, $2 command, [$3 tool_use_id]. \n is a newline and \t a tab in the command.
  python3 -c 'import json, sys; print(json.dumps({"session_id": "probe-session", "tool_use_id": sys.argv[3], "cwd": sys.argv[1], "hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": sys.argv[2].replace("\\n", "\n").replace("\\t", "\t")}}))' "$1" "$2" "${3:-}"
}
tool_json() { # $1 tool name, $2 JSON object of tool_input
  python3 -c 'import json, sys; print(json.dumps({"session_id": "probe-session", "hook_event_name": "PreToolUse", "tool_name": sys.argv[1], "tool_input": json.loads(sys.argv[2])}))' "$1" "$2"
}

# $1 expect, $2 hook, $3 label, $4 payload, then VAR=value pairs for the hook's environment.
run_hook() {
  local expect="$1" name="$2" label="$3" json="$4" out code
  shift 4
  has "$name" || return 0
  out="$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$P" "$@" "$BASH_BIN" "$HOOKS/$name" 2>"$ERR")"
  code=$?
  verdict "$expect" "$code" "$out" "$name: $label"
}

# $1 expect, $2 cwd, $3 command, then VAR=value pairs: one safety-check probe.
sc() {
  local expect="$1" cwd="$2" cmd="$3"
  shift 3
  run_hook "$expect" safety-check.sh "$cmd (in ${cwd#"$TMP"/}${*:+, $*})" "$(bash_json "$cwd" "$cmd")" CLAUDE_PROJECT_DIR="$P" "$@"
}

# 1. safety-check.sh against the probe table: $1 the project, $2 set for linked worktrees.
table() {
  local proj="$1" wt="${2:-}" expect spec cmd cwd
  while IFS=$'\t' read -r expect spec cmd || [ -n "${expect:-}" ]; do
    case "$expect" in '' | '#'*) continue ;; esac
    cwd="$proj"
    [ "$spec" = - ] || cwd="$(repo_on "$spec" "$wt")"
    sc "$expect" "$cwd" "${cmd//@TMP@/$TMP}" CLAUDE_PROJECT_DIR="$proj"
  done <"$PROBES"
}
table "$P"
# 1a. The same table in a linked worktree of the fixture project, where .git is a file: every rule
# judges it exactly as it judges the main checkout.
PW="$TMP/proj-wt"
git -C "$P" worktree add -q -b feature/probe-wt "$PW"
mkdir -p "$PW/build" && echo out >"$PW/build/out.txt" && env_files "$PW"
table "$PW" wt

# 1b. Inputs that once made the parser fail open. Each must still block, inside the hook timeout.
python3 - "$TMP" "$P" <<'PY'
import json, sys
tmp, cwd = sys.argv[1], sys.argv[2]
def write(name, command=None, raw=None):
    payload = raw or json.dumps({"session_id": "probe-session", "cwd": cwd, "hook_event_name": "PreToolUse",
                                 "tool_name": "Bash", "tool_input": {"command": command}}, ensure_ascii=False)
    with open(f"{tmp}/{name}.json", "w", encoding="utf-8") as fh:
        fh.write(payload)
write("deep", 'echo "' + '$(echo "' * 1000 + "hi" + '")' * 1000 + '"; git reset --hard HEAD~1')
write("big", "printf '%s' '" + "z" * 2_000_000 + "' >/dev/null; git reset --hard HEAD~1")
write("emoji", "rm -rf ~/Documents # \U0001F680")
write("surrogate", raw='{"session_id":"probe-session","cwd":' + json.dumps(cwd)
      + ',"tool_input":{"command":"git reset --hard HEAD~1 \\ud800"}}')
write("plain", "git status")
write("push", "git push origin dev")
write("wipe", "git reset --hard")
write("rmsrc", "rm -rf src")
write("rmdot", "rm -rf .")
write("catenv", "cat .env.local")
write("template", "cat .env.example")
write("unlockrun", "bun unlock env")
write("tokenwrite", "echo 1 > .claude/state/unlock/env")
write("helperwrite", "echo x >> scripts/env/show.sh")
write("clean", "git clean -fdx")
write("cleanlong", "git -C . clean --force -d")
write("cleandry", "git clean -n")
write("husky", "HUSKY=0 git commit -m x")
write("envwrite", "printf 'API_KEY=x' >> .env.local")
write("envcopy", "cp notes/keep.txt .env")
write("envsource", "source .env && echo $API_KEY")
write("unlockscript", "npm run-script unlock env")
write("tokenread", "ls .claude/state/unlock/")
write("helperrun", "bash scripts/env/show.sh .env")
write("envfilepy", "python3 scripts/env/envfile.py show .env")
write("configwrite", "rm -f .claude/agent-config-kit.lock")
write("hookswrite", "echo 'exit 0' > .claude/hooks/safety-check.sh")
write("probeswrite", "sed -i '' /rm/d scripts/check/hook-probes.tsv")
PY
feed() {
  local expect="$1" name="$2" out code t0
  shift 2
  t0=$SECONDS
  out="$(env CLAUDE_PROJECT_DIR="$P" "$@" "$BASH_BIN" "$HOOKS/safety-check.sh" <"$TMP/$name.json" 2>"$ERR")"
  code=$?
  verdict "$expect" "$code" "$out" "payload $name $*"
  if [ $((SECONDS - t0)) -gt 5 ]; then fail=$((fail + 1)) && echo "FAIL payload $name took $((SECONDS - t0))s, over 5s"; fi
}
feed block deep
feed block big
feed block emoji LC_ALL=en_US.US-ASCII
feed block surrogate
feed allow plain
feed block plain HOOK_PROBE_CRASH=1
# Machines without some of the tools, as PATH folders holding only what the hooks may call (and no
# `timeout`, so the hooks' own timer is what stops a slow python3): nopy has jq but no python3, nojq
# python3 but no jq, nojson neither. dying holds a python3 that exits 1 at once, slow one that
# hangs; each goes in front of another PATH.
for kit in nopy nojq nojson; do
  mkdir -p "$TMP/$kit"
  for tool in bash cat dirname basename sed paste grep awk tr sort comm head sleep git env mkdir rm touch jq python3; do
    case "$kit:$tool" in nopy:python3 | nojq:jq | nojson:jq | nojson:python3) continue ;; esac
    p="$(command -v "$tool" 2>/dev/null)" && ln -sf "$p" "$TMP/$kit/$tool"
  done
done
mkdir -p "$TMP/dying" "$TMP/slow"
printf '#!/bin/sh\nexit 1\n' >"$TMP/dying/python3" && printf '#!/bin/sh\nexec sleep 30\n' >"$TMP/slow/python3"
chmod +x "$TMP/dying/python3" "$TMP/slow/python3"
# python3 present but dying before it answers: the command is refused, not waved through.
feed block plain PATH="$TMP/dying:$PATH"
# python3 present but hanging: the hook's own timer stops it and the command is refused, inside the
# hook timeout, with or without a `timeout` command on PATH.
feed block plain PATH="$TMP/slow:$PATH" HOOK_PROBE_CAP=2
feed block plain PATH="$TMP/slow:$TMP/nopy" HOOK_PROBE_CAP=2
# No python3 at all: the plain-text rules stand in (jq reads the payload when present), and without
# any JSON reader they judge the raw payload. Claude is told when jq can say so.
for kit in nopy nojson; do
  feed block push PATH="$TMP/$kit"
  feed block wipe PATH="$TMP/$kit"
  feed block rmsrc PATH="$TMP/$kit"
  feed block rmdot PATH="$TMP/$kit"
  feed ok plain PATH="$TMP/$kit"
  feed block catenv PATH="$TMP/$kit"
  feed block unlockrun PATH="$TMP/$kit"
  feed block tokenwrite PATH="$TMP/$kit"
  feed block helperwrite PATH="$TMP/$kit"
  feed ok template PATH="$TMP/$kit"
  # The rules docs promise for this mode: forced cleans, HUSKY=0, .env* writes, copies and sources,
  # every unlock route by name, and any mention of scripts/env/ (a read cannot be told from a change).
  feed block clean PATH="$TMP/$kit"
  feed block cleanlong PATH="$TMP/$kit"
  feed ok cleandry PATH="$TMP/$kit"
  feed block husky PATH="$TMP/$kit"
  feed block envwrite PATH="$TMP/$kit"
  feed block envcopy PATH="$TMP/$kit"
  feed block envsource PATH="$TMP/$kit"
  feed block unlockscript PATH="$TMP/$kit"
  feed block tokenread PATH="$TMP/$kit"
  feed block helperrun PATH="$TMP/$kit"
  feed block envfilepy PATH="$TMP/$kit"
  # Any mention of a file that turns the guards on: unparsed, a read cannot be told from a change.
  feed block configwrite PATH="$TMP/$kit"
  # The same for the guard scripts themselves.
  feed block hookswrite PATH="$TMP/$kit"
  feed block probeswrite PATH="$TMP/$kit"
done
feed warn plain PATH="$TMP/nopy"
# No jq: python3 reads the payload and the full analyzer runs.
feed block push PATH="$TMP/nojq"
feed allow plain PATH="$TMP/nojq"
feed block surrogate PATH="$TMP/nojq"
# A python3 that is present but broken or hanging, with no jq to read the payload instead: refused,
# not handed to the plain-text rules that stand in only for a missing python3.
feed refuse plain PATH="$TMP/dying:$TMP/nojson"
feed refuse plain PATH="$TMP/slow:$TMP/nojson" HOOK_PROBE_CAP=1
feed ok plain PATH="$TMP/nojson"

# The git-listing allowance confirms a listing by running git. That run never executes a command
# from a -c option or from the repo's own core.fsmonitor setting.
sc block "$P" "cat \$(git -c core.fsmonitor='touch $TMP/fsm-option' diff --name-only)"
FM="$TMP/fsm-repo"
repo "$FM" feature/probe && echo a >"$FM/a.md" && git -C "$FM" add a.md && git -C "$FM" commit -q -m a
git -C "$FM" config core.fsmonitor "touch $TMP/fsm-config"
# shellcheck disable=SC2016 # the $( ) is the probed command's, not this script's
sc allow "$FM" 'cat $(git diff --name-only)' CLAUDE_PROJECT_DIR="$FM"
if [ ! -e "$TMP/fsm-option" ] && [ ! -e "$TMP/fsm-config" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)) && echo "FAIL safety-check ran a core.fsmonitor command while checking a git listing"
fi

# core.hooksPath set to the directory git already uses is no bypass; any other value is.
HP="$(git -C "$P" config --get core.hooksPath || echo .git/hooks)"
sc allow "$P" "git -c core.hooksPath=$HP commit -m x"
sc block "$P" "git -c core.hooksPath=/dev/null commit -m x"
# In a linked worktree .git is a file, so .git/hooks names no folder there: pointing git at it skips
# the gate. The folder git really uses there is the shared one.
HPW="$(git -C "$PW" rev-parse --path-format=absolute --git-path hooks)"
sc allow "$PW" "git -c core.hooksPath=$HPW commit -m x" CLAUDE_PROJECT_DIR="$PW"
sc block "$PW" "git -c core.hooksPath=.git/hooks commit -m x" CLAUDE_PROJECT_DIR="$PW"
sc block "$PW" "git -c core.hooksPath=/dev/null commit -m x" CLAUDE_PROJECT_DIR="$PW"

# 1b-2. The guard scripts by the path they run from (wherever the hooks are installed), and the
# routes the table cannot build in its fixture: a copied tree, an archive or a patch that lands on
# a guard script, and sed or awk program files that write one.
sc block "$P" "echo 'exit 0' >> $HOOKS/lib.sh"
sc block "$P" "sed -i.bak s/2/0/ $HOOKS/safety-check.sh"
sc block "$P" "cd $HOOKS && rm lib.sh"
sc allow "$P" "cat $HOOKS/lib.sh"
sc allow "$P" "cp $HOOKS/lib.sh $TMP/lib-copy.sh"
sc allow "$P" "bash -n $HOOKS/safety-check.sh"
mkdir -p "$TMP/forged-hooks/.claude/hooks" "$TMP/forged-hooks/scripts/check" "$TMP/forged-hooks/scripts/ops"
echo 'exit 0' >"$TMP/forged-hooks/.claude/hooks/safety-check.sh"
echo 'allow	-	rm -rf src' >"$TMP/forged-hooks/scripts/check/hook-probes.tsv"
echo 'exit 0' >"$TMP/forged-hooks/scripts/ops/unlock.sh"
tar -cf "$TMP/hooks.tar" -C "$TMP/forged-hooks" .claude
printf -- '--- a/.claude/hooks/lib.sh\n+++ b/.claude/hooks/lib.sh\n@@ -1 +1 @@\n-a\n+b\n' >"$TMP/hooks.diff"
printf -- '--- a/scripts/ops/unlock.sh\n+++ b/scripts/ops/unlock.sh\n@@ -1 +1 @@\n-a\n+b\n' >"$TMP/unlock.diff"
printf 'w scripts/env/show.sh\n' >"$TMP/w.sed" && printf 's/a/b/\n' >"$TMP/ok.sed"
# shellcheck disable=SC2016 # $1 is awk's field, not the shell's
printf '{ print > "scripts/check/hook-probes.tsv" }\n' >"$TMP/w.awk" && printf '{ print $1 }\n' >"$TMP/ok.awk"
sc block "$P" "cp -r $TMP/forged-hooks/.claude ."
sc block "$P" "cp -r $TMP/forged-hooks/scripts ."
sc block "$P" "cp -r $TMP/forged-hooks/scripts/ops scripts/"
sc block "$P" "cp -r $TMP/forged-hooks/.claude \"\$DEST\""
sc block "$P" "tar -xf $TMP/hooks.tar"
sc block "$P" "git apply $TMP/hooks.diff"
sc block "$P" "patch -p1 < $TMP/unlock.diff"
sc block "$P" "sed -f $TMP/w.sed notes/keep.txt"
sc block "$P" "awk -f $TMP/w.awk notes/keep.txt"
sc allow "$P" "sed -f $TMP/ok.sed notes/keep.txt"
sc allow "$P" "awk -f $TMP/ok.awk notes/keep.txt"
sc allow "$P" "cp -r $TMP/forged-hooks/.claude/hooks $TMP/hooks-copy"

# 1c. .claude/agent-config.json: each key replaces its default, and a broken file keeps the defaults.
C="$TMP/configured"
repo "$C" feature/probe
mkdir -p "$C/.claude" "$C/keep/other"
cat >"$C/.claude/agent-config.json" <<'EOF'
{
  "protectedBranches": ["release"],
  "protectedPaths": ["docs", "keep/this"],
  "commandWrappers": ["runx exec", "dotenvx run -f= --env-file="]
}
EOF
cfg() { sc "$1" "$C" "$2" CLAUDE_PROJECT_DIR="$C"; }
cfg block "git push origin release"
cfg allow "git push origin dev"
cfg block "git branch -D release"
cfg allow "git branch -D dev"
cfg block "gh api -XDELETE repos/o/r/git/refs/heads/release"
cfg block "rm -rf docs"
cfg allow "rm -rf src"
cfg block "rm -rf keep"
cfg block "rm -rf keep/this/x"
cfg allow "rm -rf keep/other"
cfg block "runx exec git push origin release"
cfg block "runx git push origin release"
cfg block "dotenvx run -f .env.local -- git push origin release"
cfg block "dotenvx run --env-file=.env.local git push origin release"
cfg allow "runx exec git status"
cfg allow "dotenvx run -f .env.local -- git status"
# The alembic downgrade guard is on only where an alembic.ini exists (this project has none).
cfg allow "alembic downgrade -1"
cfg allow "uv run alembic downgrade -1"
B="$TMP/broken-config"
repo "$B" feature/probe
mkdir -p "$B/.claude" && printf '{"protectedBranches": [' >"$B/.claude/agent-config.json"
sc warn "$B" "git status" CLAUDE_PROJECT_DIR="$B"
sc block "$B" "git push origin dev" CLAUDE_PROJECT_DIR="$B"
mkdir -p "$TMP/bad-key/.claude" && repo "$TMP/bad-key/r" feature/probe
printf '{"protectedBranches": "release"}' >"$TMP/bad-key/.claude/agent-config.json"
sc block "$TMP/bad-key" "git push origin main" CLAUDE_PROJECT_DIR="$TMP/bad-key"

# 1d. Workspace mode: off by default; with AGENT_WORKSPACE_ROOT, sibling repos are protected.
WS="$TMP/ws"
repo "$WS/group/app" feature/probe
repo "$WS/group/lib" feature/probe
mkdir -p "$WS/group/plain" "$WS/group/app/src/lib/api/generated"
echo 'export const probeNeedle = 1;' >"$WS/group/app/src/lib/api/generated/x.ts"
APP="$WS/group/app"
sc allow "$APP" "rm -rf ../lib" CLAUDE_PROJECT_DIR="$APP"
sc block "$APP" "rm -rf ../lib" CLAUDE_PROJECT_DIR="$APP" AGENT_WORKSPACE_ROOT="$WS"
sc block "$APP" "rm -rf ../../group" CLAUDE_PROJECT_DIR="$APP" AGENT_WORKSPACE_ROOT="$WS"
sc allow "$APP" "rm -rf ../plain" CLAUDE_PROJECT_DIR="$APP" AGENT_WORKSPACE_ROOT="$WS"
# Outside this repo and outside any temp folder, another repo stays protected; a plain folder does not.
sc block "$APP" "rm -rf ../lib" CLAUDE_PROJECT_DIR="$APP" HOOK_PROBE_NO_TEMP=1
sc allow "$APP" "rm -rf ../plain" CLAUDE_PROJECT_DIR="$APP" HOOK_PROBE_NO_TEMP=1

# 2. prompt-intent.sh: the /debug nudge where the project has /rca, nothing otherwise, and pruning.
if has prompt-intent.sh; then
  PI="$TMP/with-rca" PN="$TMP/without-rca"
  mkdir -p "$PI/.claude/commands" "$PN" && echo '# rca' >"$PI/.claude/commands/rca.md"
  # $1 want (nudge|silent), $2 project, $3 event, $4 prompt
  prompt() {
    local out got=silent
    out="$(python3 -c 'import json, sys; print(json.dumps({"session_id": "s", "hook_event_name": sys.argv[1], "prompt": sys.argv[2]}))' "$3" "$4" |
      CLAUDE_PROJECT_DIR="$2" "$BASH_BIN" "$HOOKS/prompt-intent.sh")"
    # shellcheck disable=SC2016 # the backticks are the literal text of the nudge
    [[ "$out" == *'skill `rca`'* ]] && got=nudge
    [ -n "$out" ] && [ "$got" = silent ] && got=other
    if [ "$got" = "$1" ]; then pass=$((pass + 1)); else fail=$((fail + 1)) && echo "FAIL prompt-intent expected $1, got $got: $4 ($3)"; fi
  }
  prompt nudge "$PI" UserPromptSubmit "please look at this /debug"
  prompt nudge "$PI" UserPromptSubmit "/rca the login redirect loops"
  prompt silent "$PI" UserPromptSubmit "no shorthand here"
  prompt silent "$PI" UserPromptSubmit "see /debugger/output for the trace"
  prompt silent "$PN" UserPromptSubmit "please look at this /debug"
  prompt silent "$PI" UserPromptExpansion "please look at this /debug"
  # A session idle past the pruning age keeps its folder on its next prompt; another idle one goes;
  # a folder that does not look like session state stays.
  S="$AGENT_HOOK_STATE_DIR"
  rm -rf "$S" && mkdir -p "$S/s/heads" "$S/idle/heads" "$S/not-state"
  : >"$S/s/heads/record" && : >"$S/not-state/keep.txt"
  touch -t 202001010000 "$S/s" "$S/idle" "$S/not-state"
  python3 -c 'import json; print(json.dumps({"session_id": "s", "hook_event_name": "UserPromptSubmit", "prompt": "show me the status"}))' |
    CLAUDE_PROJECT_DIR="$PN" "$BASH_BIN" "$HOOKS/prompt-intent.sh" >/dev/null
  # The active session's record, not only its folder: the hook recreates the folder it prunes.
  if [ -f "$S/s/heads/record" ] && [ ! -d "$S/idle" ] && [ -f "$S/not-state/keep.txt" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)) && echo "FAIL pruning removed the active session's folder or a non-state folder, or kept the idle one"
  fi
fi

# 3. mcp-guard.sh: the GitHub tools that commit, push or branch without Bash.
mcp() { # $1 expect, $2 tool, $3 branch, then VAR=value pairs
  local expect="$1" tool="$2" branch="$3"
  shift 3
  run_hook "$expect" mcp-guard.sh "$tool on '$branch' ${*:-}" "$(tool_json "mcp__github__$tool" "{\"branch\": \"$branch\"}")" "$@"
}
mcp allow push_files feature/x
mcp block push_files dev
mcp block create_or_update_file main
mcp block delete_file refs/heads/prod
mcp allow create_branch feature/y
mcp allow push_files ""
mcp block push_files release CLAUDE_PROJECT_DIR="$C"
mcp allow push_files dev CLAUDE_PROJECT_DIR="$C"

# 4. File guards: Write/Edit file_path, Serena relative_path, and Serena replace_in_files scopes.
# Generated output is ignored by git in many repos, which Serena honours, so one fixture ignores it.
fixture() {
  repo "$1" feature/probe
  mkdir -p "$1/src/lib/api/generated" "$1/src/lib/api/client" "$1/src/db/migrations" "$1/src/db/schema" \
    "$1/src/app/db/migrations/versions"
  echo 'export const probeNeedle = 1;' >"$1/src/lib/api/generated/api.ts"
  echo 'export const other = 2;' >"$1/src/lib/api/client/mutator.ts"
  echo '{"openapi": "3.1.0"}' >"$1/openapi.json"
  echo 'CREATE TABLE probe ();' >"$1/src/db/migrations/0001_probe.sql"
  echo "revision = 'probe'" >"$1/src/app/db/migrations/versions/0001_probe.py"
  printf '[alembic]\n' >"$1/alembic.ini"
}
F="$TMP/scope-proj" Q="$TMP/scope-ignored" E="$TMP/no-migrations"
fixture "$F" && fixture "$Q" && echo 'src/lib/api/generated/' >"$Q/.gitignore"
repo "$E" feature/probe
# $1 expect, $2 hook, $3 project, $4 tool, $5 tool_input JSON, then VAR=value pairs
guard() {
  local expect="$1" name="$2" proj="$3" tool="$4" input="$5"
  shift 5
  run_hook "$expect" "$name" "$tool $input in ${proj#"$TMP"/} ${*:-}" "$(tool_json "$tool" "$input")" CLAUDE_PROJECT_DIR="$proj" "$@"
}
guard block generated-guard.sh "$F" Edit "{\"file_path\": \"$F/src/lib/api/generated/x.ts\"}"
guard block generated-guard.sh "$F" Write '{"file_path": "src/lib/api/generated/new.ts"}'
guard block generated-guard.sh "$F" mcp__serena__replace_content '{"relative_path": "src/lib/api/generated/x.ts"}'
guard block generated-guard.sh "$F" Edit "{\"file_path\": \"$F/openapi.json\"}"
guard allow generated-guard.sh "$F" mcp__serena__replace_content '{"relative_path": "src/lib/a.ts"}'
guard allow generated-guard.sh "$F" Edit "{\"file_path\": \"$F/src/lib/api/generated-notes.md\"}"
G="$TMP/generated-config"
repo "$G" feature/probe
mkdir -p "$G/.claude" && echo '{"generatedPaths": ["content/generated"]}' >"$G/.claude/agent-config.json"
guard block generated-guard.sh "$G" Write "{\"file_path\": \"$G/content/generated/page.mdx\"}"
guard allow generated-guard.sh "$G" Write "{\"file_path\": \"$G/src/lib/api/generated/x.ts\"}"
guard block migration-guard.sh "$F" mcp__serena__replace_content '{"relative_path": "src/db/migrations/0001_x.sql"}'
guard block migration-guard.sh "$F" Write "{\"file_path\": \"$F/src/app/db/migrations/versions/0002_x.py\"}"
guard allow migration-guard.sh "$F" Write "{\"file_path\": \"$F/src/db/schema/x.ts\"}"
guard allow migration-guard.sh "$E" Write "{\"file_path\": \"$E/src/db/migrations/0001_x.sql\"}"
mkdir -p "$E/.claude" "$E/db/sql" && echo '{"migrationsDirs": ["db/sql"]}' >"$E/.claude/agent-config.json"
guard block migration-guard.sh "$E" Write "{\"file_path\": \"$E/db/sql/0002.sql\"}"
rm -rf "$E/.claude" "$E/db"
# Workspace mode: relative_path against the workspace root, from the repo or from the root itself.
REL_GEN="group/app/src/lib/api/generated/x.ts"
guard block generated-guard.sh "$APP" mcp__serena__replace_content "{\"relative_path\": \"$REL_GEN\"}" AGENT_WORKSPACE_ROOT="$WS"
guard allow generated-guard.sh "$APP" mcp__serena__replace_content "{\"relative_path\": \"$REL_GEN\"}"
guard block generated-guard.sh "$WS" mcp__serena__replace_content "{\"relative_path\": \"$REL_GEN\"}" AGENT_WORKSPACE_ROOT="$WS"
guard block generated-guard.sh "$WS" mcp__serena__replace_in_files '{"relative_path": "group/app/src/lib/api", "needle": "probeNeedle", "repl": "x", "mode": "literal"}' AGENT_WORKSPACE_ROOT="$WS"
guard allow generated-guard.sh "$WS" mcp__serena__replace_in_files '{"relative_path": "group/app/src/lib/api", "needle": "absentNeedle", "repl": "x", "mode": "literal"}' AGENT_WORKSPACE_ROOT="$WS"
# Serena's replace_in_files names a folder, or the whole project.
scope() { # $1 hook, $2 tool_input JSON (fields beside repl), $3 expect, [$4 project]
  guard "$3" "$1" "${4:-$F}" mcp__serena__replace_in_files "{$2, \"repl\": \"x\"}"
}
lit='"mode": "literal"'
scope generated-guard.sh "\"relative_path\": \"src/lib/api/generated\", \"needle\": \"probeNeedle\", $lit" block
scope generated-guard.sh "\"relative_path\": \"src/lib/api\", \"needle\": \"probeNeedle\", $lit" block
scope generated-guard.sh "\"needle\": \"probeNeedle\", $lit" block
scope generated-guard.sh "\"paths_include_glob\": \"src/lib/api/generated/**\", \"needle\": \"probe\\\\w+\", \"mode\": \"regex\"" block
scope generated-guard.sh "\"paths_include_glob\": \"**/*.json\", \"needle\": \"openapi\", $lit" block
scope generated-guard.sh "\"relative_path\": \"src/lib/api\", \"needle\": \"probeNeedle\", \"dry_run\": true, $lit" allow
scope generated-guard.sh "\"relative_path\": \"src/lib/api\", \"paths_exclude_glob\": \"src/lib/api/generated/**\", \"needle\": \"probeNeedle\", $lit" allow
scope generated-guard.sh "\"relative_path\": \"src/lib/api\", \"needle\": \"absentNeedle\", $lit" allow
scope generated-guard.sh "\"relative_path\": \"src/lib/api/client\", \"needle\": \"export\", $lit" allow
scope generated-guard.sh "\"relative_path\": \"src/lib/api\", \"needle\": \"probeNeedle\", $lit" allow "$Q"
scope migration-guard.sh "\"relative_path\": \"src/db/migrations\", \"needle\": \"CREATE\", $lit" block
scope migration-guard.sh "\"paths_include_glob\": \"src/db/migrations/*.sql\", \"needle\": \"CREATE\", $lit" block
scope migration-guard.sh "\"needle\": \"revision\", $lit" block
scope migration-guard.sh "\"relative_path\": \"src/db/schema\", \"needle\": \"CREATE\", $lit" allow
scope migration-guard.sh "\"paths_exclude_glob\": \"src/db/migrations/*\", \"needle\": \"CREATE\", $lit" allow
scope migration-guard.sh "\"needle\": \"CREATE\", $lit" allow "$E"
# A symlink is judged as named and as the file it points to, where a write lands: a dangling link
# too, since the write creates its target.
LK="$TMP/links"
fixture "$LK"
ln -s api/generated/api.ts "$LK/src/lib/gen-link.ts"
ln -s api/generated/new.ts "$LK/src/lib/dangling.ts"
ln -s api/client/mutator.ts "$LK/src/lib/ok-link.ts"
ln -s ../migrations/0001_probe.sql "$LK/src/db/schema/mig-link.sql"
guard block generated-guard.sh "$LK" Edit "{\"file_path\": \"$LK/src/lib/gen-link.ts\"}"
guard block generated-guard.sh "$LK" Write "{\"file_path\": \"$LK/src/lib/dangling.ts\"}"
guard block generated-guard.sh "$LK" mcp__serena__replace_content '{"relative_path": "src/lib/gen-link.ts"}'
guard allow generated-guard.sh "$LK" Edit "{\"file_path\": \"$LK/src/lib/ok-link.ts\"}"
guard block migration-guard.sh "$LK" Write "{\"file_path\": \"$LK/src/db/schema/mig-link.sql\"}"
guard allow migration-guard.sh "$LK" Write "{\"file_path\": \"$LK/src/db/schema/x.ts\"}"
# 4a. A linked worktree is guarded exactly like its main checkout: the same probes, both places.
WB="$TMP/guard-main" WT="$TMP/guard-wt"
fixture "$WB" && git -C "$WB" add -A && git -C "$WB" commit -q -m fixture
git -C "$WB" worktree add -q -b feature/guard-wt "$WT"
for proj in "$WB" "$WT"; do
  guard block generated-guard.sh "$proj" Edit "{\"file_path\": \"$proj/src/lib/api/generated/api.ts\"}"
  guard block generated-guard.sh "$proj" mcp__serena__replace_content '{"relative_path": "src/lib/api/generated/api.ts"}'
  guard allow generated-guard.sh "$proj" Edit "{\"file_path\": \"$proj/src/lib/a.ts\"}"
  scope generated-guard.sh "\"relative_path\": \"src/lib/api\", \"needle\": \"probeNeedle\", $lit" block "$proj"
  scope generated-guard.sh "\"needle\": \"probeNeedle\", $lit" block "$proj"
  scope generated-guard.sh "\"relative_path\": \"src/lib/api\", \"needle\": \"absentNeedle\", $lit" allow "$proj"
  guard block migration-guard.sh "$proj" Write "{\"file_path\": \"$proj/src/db/migrations/0002_x.sql\"}"
  guard allow migration-guard.sh "$proj" Write "{\"file_path\": \"$proj/src/db/schema/x.ts\"}"
  scope migration-guard.sh "\"relative_path\": \"src/db/migrations\", \"needle\": \"CREATE\", $lit" block "$proj"
  scope migration-guard.sh "\"needle\": \"revision\", $lit" block "$proj"
  scope migration-guard.sh "\"relative_path\": \"src/db/schema\", \"needle\": \"CREATE\", $lit" allow "$proj"
done
# A worktree inside a workspace is one of its repos, for a session opened at the workspace root.
WW="$TMP/ws-wt"
fixture "$WW/main" && git -C "$WW/main" add -A && git -C "$WW/main" commit -q -m fixture
git -C "$WW/main" worktree add -q -b feature/ws-wt "$WW/linked"
# Needles only the linked worktree holds, so a hit proves it was searched.
echo 'export const linkedNeedle = 1;' >"$WW/linked/src/lib/api/generated/linked.ts"
echo 'CREATE TABLE linked_only ();' >"$WW/linked/src/db/migrations/0002_linked.sql"
for r in main linked; do
  guard block generated-guard.sh "$WW" mcp__serena__replace_in_files "{\"relative_path\": \"$r/src/lib/api\", \"needle\": \"probeNeedle\", \"repl\": \"x\", $lit}" AGENT_WORKSPACE_ROOT="$WW"
  guard block generated-guard.sh "$WW" Edit "{\"file_path\": \"$WW/$r/src/lib/api/generated/api.ts\"}" AGENT_WORKSPACE_ROOT="$WW"
done
guard block generated-guard.sh "$WW" mcp__serena__replace_in_files "{\"needle\": \"linkedNeedle\", \"repl\": \"x\", $lit}" AGENT_WORKSPACE_ROOT="$WW"
guard block migration-guard.sh "$WW" mcp__serena__replace_in_files "{\"needle\": \"linked_only\", \"repl\": \"x\", $lit}" AGENT_WORKSPACE_ROOT="$WW"
guard allow migration-guard.sh "$WW" mcp__serena__replace_in_files "{\"needle\": \"absent_needle\", \"repl\": \"x\", $lit}" AGENT_WORKSPACE_ROOT="$WW"

# 5. post-edit.sh: silent on a clean file, context on a finding.
if has post-edit.sh; then
  L="$TMP/edits"
  repo "$L" feature/probe
  mkdir -p "$L/i18n" "$L/migrations/versions"
  echo '{"a": 1}' >"$L/i18n/en.json" && echo '{"a": 1}' >"$L/i18n/fr.json"
  git -C "$L" add i18n && git -C "$L" commit -q -m locales
  edit() { # $1 expect, $2 file (relative to $L)
    guard "$1" post-edit.sh "$L" Edit "{\"file_path\": \"$L/$2\"}"
  }
  echo '{"a": }' >"$L/bad.json" && edit warn bad.json
  echo '{"a": 1}' >"$L/good.json" && edit allow good.json
  printf '// comment\n{"a": 1,}\n' >"$L/tsconfig.json" && edit allow tsconfig.json
  echo 'export const x = {} as unknown as string;' >"$L/cast.ts" && edit warn cast.ts
  echo '{"a": 2}' >"$L/i18n/en.json" && edit allow i18n/en.json
  mkdir -p "$L/.claude" && echo '{"localePairs": [["i18n/en.json", "i18n/fr.json"]]}' >"$L/.claude/agent-config.json"
  edit warn i18n/en.json
  echo '{"a": 2}' >"$L/i18n/fr.json" && edit allow i18n/en.json
  echo 'x = 1' >"$L/migrations/env.py" && edit allow migrations/env.py
  printf '[alembic]\n' >"$L/alembic.ini" && edit warn migrations/env.py
  # A git the hooks start from bash (here the localePairs check) runs with core.fsmonitor off,
  # whatever the repo's config says.
  git -C "$L" config core.fsmonitor "touch $TMP/fsm-bash"
  edit allow i18n/en.json
  git -C "$L" config --unset core.fsmonitor
  if [ ! -e "$TMP/fsm-bash" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)) && echo "FAIL post-edit.sh ran a core.fsmonitor command through git"
  fi
  # The file reaches the formatters and linters after `--`, so a name that starts with a dash is
  # never read as an option. Stand-ins record the arguments they get.
  mkdir -p "$L/node_modules/.bin" "$L/.venv/bin"
  for t in node_modules/.bin/oxfmt node_modules/.bin/oxlint .venv/bin/ruff; do
    # shellcheck disable=SC2016 # the $* belongs to the stand-in written
    printf '#!/bin/sh\necho "%s $*" >>"%s"\n' "${t##*/}" "$TMP/tool-args" >"$L/$t" && chmod +x "$L/$t"
  done
  echo 'export const a = 1;' >"$L/-dash.ts" && echo 'a = 1' >"$L/-dash.py"
  edit allow -dash.ts
  edit allow -dash.py
  if grep -qxF 'oxfmt --write -- -dash.ts' "$TMP/tool-args" && grep -qxF 'oxlint -f unix -- -dash.ts' "$TMP/tool-args" &&
    grep -qxF 'ruff format --quiet -- -dash.py' "$TMP/tool-args" &&
    grep -qxF 'ruff check --output-format concise -- -dash.py' "$TMP/tool-args"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)) && echo "FAIL post-edit.sh handed a file to a tool without -- before it: $(tr '\n' ';' <"$TMP/tool-args")"
  fi
  rm -rf "$L/node_modules" "$L/.venv" "$L/-dash.ts" "$L/-dash.py"
fi

# 6. session-start.sh writes the zsh options once, however often it runs.
if has session-start.sh; then
  export CLAUDE_ENV_FILE="$TMP/env.sh"
  for _ in 1 2; do echo '{}' | "$BASH_BIN" "$HOOKS/session-start.sh"; done
  if [ "$(grep -c 'setopt NO_NOMATCH NO_EQUALS SH_WORD_SPLIT' "$CLAUDE_ENV_FILE")" = 1 ]; then pass=$((pass + 1)); else fail=$((fail + 1)) && echo "FAIL session-start.sh did not write the setopt line exactly once"; fi
  unset CLAUDE_ENV_FILE
fi

# 7. post-commit.sh, the way Claude Code runs it: safety-check.sh records HEAD under the tool call's
# id, the command runs, post-commit.sh reports what landed and warns on a path its pathspec did not
# name. Git resolves each pathspec, so ./, absolute paths, globs, non-ASCII names and --amend match.
if has post-commit.sh; then
  R="$TMP/repo-probe"
  repo "$R" feature/probe
  g() { git -C "$R" "$@"; }
  # $1 tool_use_id, $2 cwd, $3 command: one Bash call's hook input.
  call() {
    python3 -c 'import json, sys; print(json.dumps({"session_id": "probe-session", "tool_use_id": sys.argv[1], "cwd": sys.argv[2], "tool_input": {"command": sys.argv[3]}}))' "$@"
  }
  # A refused PreToolUse writes no record, and every probe expecting silence would pass for that reason.
  pre() { call "$@" | "$BASH_BIN" "$HOOKS/safety-check.sh" >/dev/null 2>&1 || { fail=$((fail + 1)) && echo "FAIL safety-check refused a probe commit: $3"; }; }
  # $1 clean, warning or silent; the rest as call().
  post() {
    local want="$1" out got=clean
    shift
    out="$(call "$@" | "$BASH_BIN" "$HOOKS/post-commit.sh")"
    [[ "$out" == *"Committed in"* ]] || got=silent
    [[ "$out" == *WARNING* ]] && got=warning
    if [ "$got" = "$want" ]; then pass=$((pass + 1)); else fail=$((fail + 1)) && echo "FAIL post-commit expected $want, got $got: $3 (in $2)"; fi
  }
  echo a >"$R/a.txt" && echo b >"$R/b.txt" && g add a.txt b.txt
  pre one "$R" "git commit -m probe -- a.txt"
  g commit -q -m probe
  post warning one "$R" "git commit -m probe -- a.txt"
  mkdir -p "$R/sub" && echo c >"$R/sub/c.txt" && echo u >"$R/sub/ü.txt" && g add sub
  SUB=("$R|git commit -m sub -- sub" "$R|git commit -m sub -- '$R/sub/c.txt' '$R/sub/ü.txt'" "$R/sub|git commit -m sub -- ./c.txt ü.txt" "$R/sub|git commit -m sub -- '*.txt'" "$R/sub|git commit -m sub -- c.txt")
  for i in 0 1 2 3 4; do pre "sub$i" "${SUB[$i]%%|*}" "${SUB[$i]#*|}"; done
  g commit -q -m sub
  for i in 0 1 2 3; do post clean "sub$i" "${SUB[$i]%%|*}" "${SUB[$i]#*|}"; done
  post warning sub4 "${SUB[4]%%|*}" "${SUB[4]#*|}"
  echo d >"$R/d.txt" && g add d.txt
  pre amend "$R" "git commit --amend --no-edit -- d.txt"
  g commit -q --amend --no-edit
  post clean amend "$R" "git commit --amend --no-edit -- d.txt"
  # A commit that did not land reports nothing even when a pipe hides the failure, and each commit of
  # a multi-commit command is held to its own pathspec.
  C1="git commit"
  landing() {
    pre "$1" "$R" "$2"
    (cd "$R" && bash -c "$2") >/dev/null 2>&1
    post "$3" "$1" "$R" "$2"
  }
  printf '#!/bin/sh\nexit 1\n' >"$R/.git/hooks/pre-commit" && chmod +x "$R/.git/hooks/pre-commit"
  echo e >"$R/e.txt" && g add e.txt
  landing refused "$C1 -m refused -- e.txt 2>&1 | tail -1" silent
  rm "$R/.git/hooks/pre-commit"
  echo f >"$R/f.txt" && g add f.txt
  landing two "$C1 -qm three -- e.txt && $C1 -qm four -- f.txt" clean
  # Another PreToolUse hook may rewrite the command before it runs (here, adding a `command`
  # wrapper), so the record is found by the tool call's id. A background commit reaches PostToolUse
  # before it lands and reports nothing, and no record reports nothing either.
  echo h >"$R/h.txt" && g add h.txt
  pre bg "$R" "git commit -m bg -- h.txt"
  post silent bg "$R" "command git commit -m bg -- h.txt"
  pre fg "$R" "git commit -m fg -- h.txt"
  g commit -q -m fg
  post clean fg "$R" "command git commit -m fg -- h.txt"
  echo i >"$R/i.txt" && g add i.txt && g commit -q -m unrecorded
  post silent none "$R" "git commit -m unrecorded -- i.txt"
  # Input without an id falls back to the command text, so two such calls in flight keep two records.
  O="$TMP/repo-other" && repo "$O" feature/other
  echo k >"$R/k.txt" && g add k.txt && echo k >"$O/k.txt" && git -C "$O" add k.txt
  pre "" "$R" "git commit -m noid -- k.txt"
  pre "" "$O" "git commit -m noid-other -- k.txt"
  g commit -q -m noid && git -C "$O" commit -q -m noid-other
  post clean "" "$R" "git commit -m noid -- k.txt"
  post clean "" "$O" "git commit -m noid-other -- k.txt"
  # Only the command's own commits count, each against the HEAD it moved from: a reset or a switch
  # moves HEAD without a commit entry, so neither the commits a branch is ahead by nor a dropped
  # commit's files are reported. Two calls with one commit hold it to both pathspecs.
  echo l >"$R/l.txt" && g add l.txt && g commit -q -m before-reset
  pre reset "$R" "git reset --soft HEAD~1 && git commit -m redo -- m.txt"
  echo m >"$R/m.txt" && g reset -q --soft HEAD~1 && g reset -q -- l.txt && g add m.txt && g commit -q -m redo
  post clean reset "$R" "git reset --soft HEAD~1 && command git commit -m redo -- m.txt"
  g switch -q -c ahead && g commit -q --allow-empty -m ahead-1 && g switch -q -
  pre ahead "$R" "git switch -q ahead && git commit -m mine -- o.txt"
  g switch -q ahead && echo o >"$R/o.txt" && echo s >"$R/stray.txt" && g add o.txt stray.txt && g commit -q -m mine
  post warning ahead "$R" "git switch -q ahead && command git commit -m mine -- o.txt"
  echo p >"$R/p.txt" && echo s >"$R/stray2.txt" && g add p.txt stray2.txt
  pre union "$R" "git commit -m gone -- absent.txt; git commit -m kept -- p.txt"
  g commit -q -m kept
  post warning union "$R" "command git commit -m gone -- absent.txt; command git commit -m kept -- p.txt"
  # A repo the command creates has no record of its own, and is reported whole.
  N="git init -q -b feature/n n && git -C n commit -q --allow-empty -m first"
  pre fresh "$TMP" "$N"
  (cd "$TMP" && bash -c "$N")
  post clean fresh "$TMP" "$N"
  # An unresolved `cd "$(...)"` matches no repo, even when the cwd's repo gains a commit meanwhile.
  echo j >"$R/j.txt" && g add j.txt
  pre dyn "$O" "cd \"\$(printf %s '$R')\" && git commit -m dyn -- j.txt"
  g commit -q -m dyn
  git -C "$O" commit -q --allow-empty -m peer
  post silent dyn "$O" "cd \"\$(printf %s '$R')\" && command git commit -m dyn -- j.txt"
  # A reflog subject that is not UTF-8 neither refuses the next commit nor hides it.
  echo q >"$R/q.txt" && g add q.txt && g commit -q -m "$(printf 'caf\351')" 2>/dev/null
  echo q2 >"$R/q2.txt" && echo s >"$R/stray3.txt" && g add q2.txt stray3.txt
  pre latin "$R" "git commit -m next -- q2.txt"
  g commit -q -m next
  post warning latin "$R" "command git commit -m next -- q2.txt"
  # Per-file commits over a list the analyzer cannot expand have no pathspec to hold them to.
  echo u1 >"$R/u1.txt" && echo u2 >"$R/u2.txt" && g add u1.txt u2.txt
  landing loop "for f in \$(git diff --cached --name-only); do $C1 -q -m \"\$f\" -- \"\$f\"; done" clean
  # A folder only a glob names stands for the cwd's repo; a subject two calls share, or one xargs
  # fills in, pairs no commit by message.
  echo w >"$R/w.txt" && echo s >"$R/stray5.txt" && g add w.txt stray5.txt
  pre globloop "$R" "for d in ./*/; do git -C \"\$d\" commit -F ../msg -- w.txt; done"
  g commit -q -m globloop
  post warning globloop "$R" "for d in ./*/; do command git -C \"\$d\" commit -F ../msg -- w.txt; done"
  echo b9 >"$R/b9.txt" && g add b9.txt
  pre twin "$R" "for f in a9.txt b9.txt; do git commit -m 'chore: format' -- \"\$f\"; done"
  g commit -q -m "chore: format"
  post clean twin "$R" "for f in a9.txt b9.txt; do command git commit -m 'chore: format' -- \"\$f\"; done"
  X="printf '%s\\n' x1.txt x2.txt | xargs -I{} $C1 -q -m 'add {}' -- {}"
  echo 1 >"$R/x1.txt" && echo 2 >"$R/x2.txt" && g add x1.txt x2.txt
  landing xargs "$X" clean
  # A tracked file named HEAD does not make the reflog ambiguous.
  echo x >"$R/HEAD" && g add HEAD
  pre headfile "$R" "git commit -m headfile -- HEAD"
  g commit -q -m headfile
  post clean headfile "$R" "command git commit -m headfile -- HEAD"
  # Without a HEAD reflog, or with one expired meanwhile, the commits since the recorded HEAD stand in.
  NL="$TMP/repo-nolog" && git init -q -b feature/nolog "$NL" && git -C "$NL" config core.logAllRefUpdates false
  rm -rf "$NL/.git/logs"
  git -C "$NL" commit -q --allow-empty -m init
  echo a >"$NL/a.txt" && echo s >"$NL/s.txt" && git -C "$NL" add a.txt s.txt
  pre nolog "$NL" "git commit -m nolog -- a.txt"
  git -C "$NL" commit -q -m nolog
  post warning nolog "$NL" "command git commit -m nolog -- a.txt"
  echo e2 >"$R/e2.txt" && echo s >"$R/stray4.txt" && g add e2.txt stray4.txt
  pre expire "$R" "git commit -m expired -- e2.txt"
  g reflog expire --expire=now --expire-unreachable=now --all && g commit -q -m expired
  post warning expire "$R" "command git commit -m expired -- e2.txt"
  # A root commit on an orphan branch is reported alone, against nothing.
  g switch -q --orphan orphan && echo r >"$R/root.txt" && g add root.txt
  pre orphan "$R" "git commit -m root -- root.txt"
  g commit -q -m root
  post clean orphan "$R" "command git commit -m root -- root.txt"
  # A linked worktree keeps its own HEAD reflog, under the main repo's .git/worktrees/: what landed
  # there is read from it as in a main checkout, and a commit in the main checkout is not its own.
  RB="$TMP/commit-main" RW="$TMP/commit-wt"
  repo "$RB" feature/probe && git -C "$RB" worktree add -q -b feature/commit-wt "$RW"
  echo a >"$RW/a.txt" && echo s >"$RW/s.txt" && git -C "$RW" add a.txt s.txt
  pre wt1 "$RW" "git commit -m wt-one -- a.txt s.txt"
  git -C "$RW" commit -q -m wt-one
  post clean wt1 "$RW" "command git commit -m wt-one -- a.txt s.txt"
  echo b >"$RW/b.txt" && echo t >"$RW/t.txt" && git -C "$RW" add b.txt t.txt
  pre wt2 "$RW" "git commit -m wt-two -- b.txt"
  git -C "$RW" commit -q -m wt-two
  post warning wt2 "$RW" "command git commit -m wt-two -- b.txt"
  pre wt3 "$RW" "git commit -m wt-three -- c.txt"
  git -C "$RB" commit -q --allow-empty -m main-side
  post silent wt3 "$RW" "command git commit -m wt-three -- c.txt"
  # Without jq, python3 reads the payload and the report is the same.
  echo n >"$RW/n.txt" && echo u >"$RW/u.txt" && git -C "$RW" add n.txt u.txt
  PATH="$TMP/nojq" pre nojq "$RW" "git commit -m nojq -- n.txt"
  git -C "$RW" commit -q -m nojq
  PATH="$TMP/nojq" post warning nojq "$RW" "command git commit -m nojq -- n.txt"
fi

# 8. A payload that is not one JSON object. A guard refuses it and says how to turn the guard off;
# a feedback hook exits 0 and prints nothing.
GUARDS="safety-check.sh mcp-guard.sh generated-guard.sh migration-guard.sh db-guard.sh"
FEEDBACK="post-edit.sh post-commit.sh prompt-intent.sh session-start.sh"
for bad in '{not json' '[]' '"text"' '' '{"tool_input": {"command": "git push origin dev"}' '{} {}'; do
  for h in $GUARDS; do run_hook refuse "$h" "payload [$bad]" "$bad"; done
  for h in $FEEDBACK; do run_hook quiet "$h" "payload [$bad]" "$bad"; done
done

# A project folder that cannot be entered: guards refuse, feedback hooks stay quiet.
for h in $GUARDS; do run_hook refuse "$h" "missing project folder" "$(bash_json "$P" "git status")" CLAUDE_PROJECT_DIR="$TMP/absent"; done
for h in $FEEDBACK; do run_hook quiet "$h" "missing project folder" "$(bash_json "$P" "git status")" CLAUDE_PROJECT_DIR="$TMP/absent"; done

# 9. Each hook's fail mode when a tool is missing, broken or too slow (README, "Fail modes"). A
# guard that can still read the call keeps guarding; one that cannot refuses; feedback stays quiet.
# $1 expect, $2 hook, $3 kit label, $4 payload, then VAR=value pairs; also fails past the timeout.
timed() {
  local t0=$SECONDS
  run_hook "$1" "$2" "$3" "$4" "${@:5}"
  if [ $((SECONDS - t0)) -ge 10 ]; then fail=$((fail + 1)) && echo "FAIL $2 ($3) took $((SECONDS - t0))s, past the 10s hook timeout"; fi
}
MB="$(tool_json mcp__github__push_files '{"branch": "dev"}')"
MF="$(tool_json mcp__github__push_files '{"branch": "feature/x"}')"
GE="$(tool_json Edit "{\"file_path\": \"$F/src/lib/api/generated/api.ts\"}")"
GO="$(tool_json Edit "{\"file_path\": \"$F/src/lib/a.ts\"}")"
ME="$(tool_json Write "{\"file_path\": \"$F/src/db/migrations/0002_x.sql\"}")"
GS="$(tool_json mcp__serena__replace_in_files '{"relative_path": "src/lib/api", "needle": "probeNeedle", "repl": "x", "mode": "literal"}')"
GM="$(tool_json mcp__serena__replace_in_files '{"relative_path": "src/lib/api", "needle": "absentNeedle", "repl": "x", "mode": "literal"}')"
MS="$(tool_json mcp__serena__replace_in_files '{"relative_path": "src/db", "needle": "CREATE", "repl": "x", "mode": "literal"}')"
for kit in nojq nopy; do
  K=(PATH="$TMP/$kit" CLAUDE_PROJECT_DIR="$F")
  timed block mcp-guard.sh "$kit" "$MB" "${K[@]}"
  timed allow mcp-guard.sh "$kit" "$MF" "${K[@]}"
  timed block generated-guard.sh "$kit" "$GE" "${K[@]}"
  timed allow generated-guard.sh "$kit" "$GO" "${K[@]}"
  timed block migration-guard.sh "$kit" "$ME" "${K[@]}"
done
# replace_in_files needs python3 to work out its reach: without it, refused whatever it touches.
timed block generated-guard.sh nojq "$GS" PATH="$TMP/nojq" CLAUDE_PROJECT_DIR="$F"
timed allow generated-guard.sh nojq "$GM" PATH="$TMP/nojq" CLAUDE_PROJECT_DIR="$F"
timed block migration-guard.sh nojq "$MS" PATH="$TMP/nojq" CLAUDE_PROJECT_DIR="$F"
timed refuse generated-guard.sh nopy "$GM" PATH="$TMP/nopy" CLAUDE_PROJECT_DIR="$F"
timed refuse migration-guard.sh nopy "$MS" PATH="$TMP/nopy" CLAUDE_PROJECT_DIR="$F"
# Neither reader: nothing can be checked, so every guarded call is refused.
for payload in "$MF" "$GO" "$GM"; do
  for h in mcp-guard.sh generated-guard.sh migration-guard.sh; do
    timed refuse "$h" nojson "$payload" PATH="$TMP/nojson" CLAUDE_PROJECT_DIR="$F"
  done
done
# python3 broken (exits at once) or hanging, with jq there: the config falls back to jq, and only
# the replace_in_files check, which needs python3, refuses.
for kit in dying slow; do
  K=(PATH="$TMP/$kit:$TMP/nopy" CLAUDE_PROJECT_DIR="$F" HOOK_PROBE_CAP=1)
  timed block mcp-guard.sh "$kit" "$MB" "${K[@]}"
  timed allow mcp-guard.sh "$kit" "$MF" "${K[@]}"
  timed block generated-guard.sh "$kit" "$GE" "${K[@]}"
  timed allow generated-guard.sh "$kit" "$GO" "${K[@]}"
  timed refuse generated-guard.sh "$kit" "$GM" "${K[@]}"
  timed refuse migration-guard.sh "$kit" "$MS" "${K[@]}"
done
# db-guard.sh reads SQL with python3 alone: without it, or with it broken or hanging, every call is
# refused, reads included; without jq it works.
DR="$(tool_json mcp__db-prod__execute_sql '{"sql": "SELECT 1"}')"
DW="$(tool_json mcp__db-prod__execute_sql '{"sql": "DELETE FROM t"}')"
if has db-guard.sh; then
  timed allow db-guard.sh nojq "$DR" PATH="$TMP/nojq" CLAUDE_PROJECT_DIR="$F"
  timed block db-guard.sh nojq "$DW" PATH="$TMP/nojq" CLAUDE_PROJECT_DIR="$F"
  for kit in nopy nojson; do timed refuse db-guard.sh "$kit" "$DR" PATH="$TMP/$kit" CLAUDE_PROJECT_DIR="$F"; done
  for kit in dying slow; do timed refuse db-guard.sh "$kit" "$DR" PATH="$TMP/$kit:$TMP/nopy" CLAUDE_PROJECT_DIR="$F" HOOK_PROBE_CAP=1; done
  timed refuse db-guard.sh "slow, default cap" "$DR" PATH="$TMP/slow:$TMP/nopy" CLAUDE_PROJECT_DIR="$F"
  # Wired on every MCP tool as a plugin, db-guard passes a call to any other tool before it needs
  # python3: jq reads the name and the pattern, bash matches them. Only the SQL tool, or a pattern
  # beyond plain names, | and ( ), waits for python3; with no JSON reader at all it still refuses.
  OT="$(tool_json mcp__serena__find_symbol '{"name_path": "x"}')"
  for kit in nopy dying slow; do
    KP="$TMP/$kit"
    [ "$kit" = nopy ] || KP="$TMP/$kit:$TMP/nopy"
    timed allow db-guard.sh "$kit, another tool" "$OT" PATH="$KP" CLAUDE_PROJECT_DIR="$F"
  done
  timed refuse db-guard.sh "nojson, another tool" "$OT" PATH="$TMP/nojson" CLAUDE_PROJECT_DIR="$F"
  DG="$TMP/db-pattern"
  repo "$DG" feature/probe && mkdir -p "$DG/.claude"
  echo '{"dbWriteGuard": {"toolPattern": "mcp__pg__(query|execute)"}}' >"$DG/.claude/agent-config.json"
  timed allow db-guard.sh "nopy, pattern set, another tool" "$OT" PATH="$TMP/nopy" CLAUDE_PROJECT_DIR="$DG"
  timed allow db-guard.sh "nopy, pattern set, the default tool" "$DR" PATH="$TMP/nopy" CLAUDE_PROJECT_DIR="$DG"
  timed refuse db-guard.sh "nopy, pattern set, its tool" "$(tool_json mcp__pg__query '{"query": "SELECT 1"}')" \
    PATH="$TMP/nopy" CLAUDE_PROJECT_DIR="$DG"
  printf '%s\n' '{"dbWriteGuard": {"toolPattern": "mcp__pg__\\w+"}}' >"$DG/.claude/agent-config.json"
  timed refuse db-guard.sh "nopy, a pattern bash may read otherwise" "$OT" PATH="$TMP/nopy" CLAUDE_PROJECT_DIR="$DG"
fi
# A symlink is followed by realpath or readlink, else python3 (the kits hold neither command); with
# none of them it is refused.
LS="$(tool_json Edit "{\"file_path\": \"$LK/src/lib/gen-link.ts\"}")"
LO="$(tool_json Edit "{\"file_path\": \"$LK/src/lib/ok-link.ts\"}")"
timed block generated-guard.sh nojq "$LS" PATH="$TMP/nojq" CLAUDE_PROJECT_DIR="$LK"
timed allow generated-guard.sh nojq "$LO" PATH="$TMP/nojq" CLAUDE_PROJECT_DIR="$LK"
timed refuse generated-guard.sh nopy "$LO" PATH="$TMP/nopy" CLAUDE_PROJECT_DIR="$LK"
# The real caps, not lowered: a hanging python3 is given up on, and the call refused, before the
# 10 s hook timeout would let it through.
timed block safety-check.sh "slow, default cap" "$(bash_json "$P" "git status")" PATH="$TMP/slow:$TMP/nopy"
timed refuse generated-guard.sh "slow, default caps" "$GM" PATH="$TMP/slow:$TMP/nopy" CLAUDE_PROJECT_DIR="$F"
# One deadline for the whole guard: a python3 that takes 2 s per call stays inside every step's own
# cap, yet the steps add up past Claude Code's 10 s hook timeout, which would let the call through.
# The guard refuses at its 9 s deadline instead, and says so.
mkdir -p "$TMP/sluggish"
# shellcheck disable=SC2016 # the $@ belongs to the script written
printf '#!/bin/sh\nsleep 2 </dev/null >/dev/null 2>&1\nexec %s "$@"\n' "$(command -v python3)" >"$TMP/sluggish/python3"
chmod +x "$TMP/sluggish/python3"
for h in safety-check.sh generated-guard.sh; do
  has "$h" || continue
  if [ "$h" = safety-check.sh ]; then
    timed refuse "$h" "sluggish python3" "$(bash_json "$P" "git status")" PATH="$TMP/sluggish:$TMP/nojq"
  else
    timed refuse "$h" "sluggish python3" "$GO" PATH="$TMP/sluggish:$TMP/nojq" CLAUDE_PROJECT_DIR="$F"
  fi
  if grep -q 'ran out of time' "$ERR"; then pass=$((pass + 1)); else fail=$((fail + 1)) && echo "FAIL $h did not name its deadline: $(head -1 "$ERR")"; fi
done
# Feedback hooks fail open: whatever is missing or broken, exit 0 and no output they cannot stand by.
if has post-edit.sh; then
  EB="$(tool_json Edit "{\"file_path\": \"$L/bad.json\"}")"
  EC="$(tool_json Edit "{\"file_path\": \"$L/cast.ts\"}")"
  timed warn post-edit.sh nojq "$EB" PATH="$TMP/nojq" CLAUDE_PROJECT_DIR="$L"
  timed allow post-edit.sh nopy "$EB" PATH="$TMP/nopy" CLAUDE_PROJECT_DIR="$L"
  timed warn post-edit.sh nopy "$EC" PATH="$TMP/nopy" CLAUDE_PROJECT_DIR="$L"
  timed quiet post-edit.sh nojson "$EC" PATH="$TMP/nojson" CLAUDE_PROJECT_DIR="$L"
  timed quiet post-edit.sh dying "$EB" PATH="$TMP/dying:$TMP/nojson" CLAUDE_PROJECT_DIR="$L"
  # A python3 that fails is no verdict on the file: no "not valid JSON" note for a good one.
  timed allow post-edit.sh dying "$(tool_json Edit "{\"file_path\": \"$L/good.json\"}")" PATH="$TMP/dying:$TMP/nopy" CLAUDE_PROJECT_DIR="$L"
fi
for kit in nopy nojson dying; do
  KP="$TMP/$kit"
  [ "$kit" = dying ] && KP="$TMP/dying:$TMP/nojson"
  timed quiet post-commit.sh "$kit" "$(bash_json "$P" "git commit -m x -- a.txt")" PATH="$KP"
  if has prompt-intent.sh; then
    timed quiet prompt-intent.sh "$kit" '{"session_id": "s", "hook_event_name": "UserPromptSubmit", "prompt": "/debug"}' PATH="$KP" CLAUDE_PROJECT_DIR="$PI"
  fi
  timed quiet session-start.sh "$kit" '{}' PATH="$KP"
done
if has prompt-intent.sh; then
  out="$(printf '%s' '{"session_id": "s", "hook_event_name": "UserPromptSubmit", "prompt": "/debug"}' | env PATH="$TMP/nojq" CLAUDE_PROJECT_DIR="$PI" "$BASH_BIN" "$HOOKS/prompt-intent.sh" 2>/dev/null)"
  if [[ "$out" == *'rca'* ]]; then pass=$((pass + 1)); else fail=$((fail + 1)) && echo "FAIL prompt-intent without jq gave no nudge"; fi
fi

# 10. Plugin mode: with CLAUDE_PLUGIN_ROOT set, a project that has neither .claude/agent-config.json
# nor .claude/agent-config-kit.lock gets no hook at all, even for a call a guard would refuse or a
# payload it cannot read. Opting in with either file turns every hook back on. Copied into a repo
# (no CLAUDE_PLUGIN_ROOT), the hooks run without either file.
PG="$TMP/plugin-project"
fixture "$PG"
mkdir -p "$PG/.claude/commands" && echo '# rca' >"$PG/.claude/commands/rca.md"
echo '{"a": }' >"$PG/bad.json"
PLUGIN=(CLAUDE_PLUGIN_ROOT="$(dirname "$HOOKS")" CLAUDE_PROJECT_DIR="$PG")
PB="$(bash_json "$PG" "git push origin dev")"
PC="$(bash_json "$PG" "git commit -m x -- a.txt")"
PM="$(tool_json mcp__github__push_files '{"branch": "dev"}')"
PE="$(tool_json Edit "{\"file_path\": \"$PG/src/lib/api/generated/api.ts\"}")"
PW2="$(tool_json Write "{\"file_path\": \"$PG/src/db/migrations/0002_x.sql\"}")"
PJ="$(tool_json Edit "{\"file_path\": \"$PG/bad.json\"}")"
PP='{"session_id": "s", "hook_event_name": "UserPromptSubmit", "prompt": "/debug"}'
# $1 state (off, lock, config or template): whether each hook acts.
plugin_probes() {
  local on="$1" b=block w=warn envfile="$TMP/plugin-env-$1.sh"
  shift
  [ "$on" = off ] && b=quiet && w=quiet
  run_hook "$b" safety-check.sh "plugin $on: push" "$PB" "$@"
  run_hook "$( [ "$on" = off ] && echo quiet || echo refuse)" safety-check.sh "plugin $on: bad payload" '{not json' "$@"
  run_hook "$b" mcp-guard.sh "plugin $on: push_files dev" "$PM" "$@"
  run_hook "$b" generated-guard.sh "plugin $on: generated edit" "$PE" "$@"
  run_hook "$b" migration-guard.sh "plugin $on: migration write" "$PW2" "$@"
  run_hook "$b" db-guard.sh "plugin $on: SQL write" "$DW" "$@"
  run_hook "$w" post-edit.sh "plugin $on: bad.json" "$PJ" "$@"
  run_hook quiet post-commit.sh "plugin $on: commit" "$PC" "$@"
  if has prompt-intent.sh; then
    out="$(printf '%s' "$PP" | env "$@" "$BASH_BIN" "$HOOKS/prompt-intent.sh" 2>/dev/null)"
    if { [ "$on" = off ] && [ -z "$out" ]; } || { [ "$on" != off ] && [[ "$out" == *rca* ]]; }; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1)) && echo "FAIL prompt-intent in plugin state $on: $out"
    fi
  fi
  if has session-start.sh; then
    rm -f "$envfile"
    echo '{}' | env "$@" CLAUDE_ENV_FILE="$envfile" "$BASH_BIN" "$HOOKS/session-start.sh"
    if { [ "$on" = off ] && [ ! -e "$envfile" ]; } || { [ "$on" != off ] && [ -s "$envfile" ]; }; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1)) && echo "FAIL session-start in plugin state $on"
    fi
  fi
}
plugin_probes off "${PLUGIN[@]}"
touch "$PG/.claude/agent-config-kit.lock"
plugin_probes lock "${PLUGIN[@]}"
rm "$PG/.claude/agent-config-kit.lock" && echo '{}' >"$PG/.claude/agent-config.json"
plugin_probes config "${PLUGIN[@]}"
rm "$PG/.claude/agent-config.json"
plugin_probes template CLAUDE_PROJECT_DIR="$PG"
# As a plugin, the per-session state lives in the plugin's data folder.
touch "$PG/.claude/agent-config-kit.lock"
run_hook allow safety-check.sh "plugin state dir" "$(bash_json "$PG" "git commit -m x")" "${PLUGIN[@]}" \
  CLAUDE_PLUGIN_DATA="$TMP/plugin-data" AGENT_HOOK_STATE_DIR=
if [ -n "$(find "$TMP/plugin-data/hook-state/probe-session/heads" -type f 2>/dev/null)" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)) && echo "FAIL plugin mode kept no HEAD record under CLAUDE_PLUGIN_DATA"
fi
# The opt-in sticks: a project seen opted in is recorded in CLAUDE_PLUGIN_DATA, and once both files
# are gone the hooks keep guarding it and say so on stderr. A plugin data folder without that record
# keeps the project silent. The shell may read the record, never remove it.
PD="$TMP/plugin-optin"
STICKY=("${PLUGIN[@]}" CLAUDE_PLUGIN_DATA="$PD")
run_hook block safety-check.sh "plugin opted in: push" "$PB" "${STICKY[@]}"
rm "$PG/.claude/agent-config-kit.lock"
run_hook block safety-check.sh "plugin, both files gone: push" "$PB" "${STICKY[@]}"
if grep -q 'are both gone now' "$ERR"; then pass=$((pass + 1)); else fail=$((fail + 1)) && echo "FAIL the vanished opt-in files went unreported"; fi
run_hook block mcp-guard.sh "plugin, both files gone: push_files dev" "$PM" "${STICKY[@]}"
run_hook block db-guard.sh "plugin, both files gone: SQL write" "$DW" "${STICKY[@]}"
run_hook quiet safety-check.sh "plugin, never recorded: push" "$PB" "${PLUGIN[@]}" CLAUDE_PLUGIN_DATA="$TMP/plugin-other"
run_hook block safety-check.sh "plugin: rm the opt-in record" "$(bash_json "$PG" "rm $PD/opted-in-projects")" "${STICKY[@]}"
run_hook block safety-check.sh "plugin: move the data folder" "$(bash_json "$PG" "mv $PD $TMP/elsewhere")" "${STICKY[@]}"
run_hook allow safety-check.sh "plugin: read the opt-in record" "$(bash_json "$PG" "cat $PD/opted-in-projects")" "${STICKY[@]}"
# As a plugin, the plugin's own scripts/ and hooks/ are guard scripts wherever the plugin lives; the
# same folders are nothing special to a template copy (no CLAUDE_PLUGIN_ROOT).
FP="$TMP/fake-plugin"
mkdir -p "$FP/scripts" "$FP/hooks" && echo 'exit 0' >"$FP/scripts/guard.sh" && echo '{}' >"$FP/hooks/hooks.json"
touch "$PG/.claude/agent-config-kit.lock"
FPLUG=(CLAUDE_PLUGIN_ROOT="$FP" CLAUDE_PROJECT_DIR="$PG")
run_hook block safety-check.sh "plugin: write its scripts" "$(bash_json "$PG" "echo x >> $FP/scripts/guard.sh")" "${FPLUG[@]}"
run_hook block safety-check.sh "plugin: rm its hooks.json" "$(bash_json "$PG" "rm $FP/hooks/hooks.json")" "${FPLUG[@]}"
run_hook block safety-check.sh "plugin: sed w into its scripts" "$(bash_json "$PG" "sed -n 'w $FP/scripts/guard.sh' notes/keep.txt")" "${FPLUG[@]}"
run_hook block safety-check.sh "plugin: move the plugin" "$(bash_json "$PG" "mv $FP $TMP/fake-plugin-off")" "${FPLUG[@]}"
# shellcheck disable=SC2016 # the variable is the probed command's, left for the hook to read
run_hook block safety-check.sh "plugin: rm by variable" "$(bash_json "$PG" 'rm "$CLAUDE_PLUGIN_ROOT/scripts/guard.sh"')" "${FPLUG[@]}"
run_hook allow safety-check.sh "plugin: read its scripts" "$(bash_json "$PG" "cat $FP/scripts/guard.sh")" "${FPLUG[@]}"
run_hook allow safety-check.sh "plugin: copy its scripts out" "$(bash_json "$PG" "cp $FP/scripts/guard.sh $TMP/guard-copy.sh")" "${FPLUG[@]}"
run_hook allow safety-check.sh "template: the same folder is a temp fixture" "$(bash_json "$PG" "echo x >> $FP/scripts/guard.sh")" CLAUDE_PROJECT_DIR="$PG"
rm "$PG/.claude/agent-config-kit.lock"

# 11. db-guard.sh: read-only SQL passes; SQL that may write runs only while the user has unlocked db.
# $1 dir, $2 target, $3 seconds until it ends (default 600): a token as scripts/ops/unlock.sh writes it.
token() {
  mkdir -p "$1/.claude/state/unlock" && chmod 700 "$1/.claude/state" "$1/.claude/state/unlock"
  (umask 077 && printf '%s\n' "$(($(date +%s) + ${3:-600}))" >"$1/.claude/state/unlock/$2")
}
# $1 tool, $2 field, $3 SQL (\n is a newline)
sql_json() {
  python3 -c 'import json, sys; print(json.dumps({"session_id": "probe-session", "hook_event_name": "PreToolUse", "tool_name": sys.argv[1], "tool_input": {sys.argv[2]: sys.argv[3].replace("\\n", "\n")}}))' "$@"
}
if has db-guard.sh; then
  DBP="$TMP/db-proj"
  repo "$DBP" feature/probe
  printf '.claude/state/\n' >"$DBP/.gitignore"
  sql() { # $1 expect, $2 SQL, then VAR=value pairs
    local expect="$1" q="$2"
    shift 2
    run_hook "$expect" db-guard.sh "SQL [$q] ${*:-}" "$(sql_json mcp__db-prod__execute_sql sql "$q")" CLAUDE_PROJECT_DIR="$DBP" "$@"
  }
  while IFS=$'\t' read -r expect q; do
    sql "$expect" "$q"
  done <<'EOF'
allow	SELECT * FROM users WHERE id = 1
allow	select count(*) from orders;
allow	  SELECT 1  ;
allow	SELECT * FROM users;
allow	WITH recent AS (SELECT * FROM orders WHERE created_at > now() - interval '1 day') SELECT count(*) FROM recent
allow	WITH RECURSIVE t(n) AS (VALUES (1) UNION ALL SELECT n + 1 FROM t WHERE n < 5) SELECT sum(n) FROM t
allow	EXPLAIN SELECT * FROM users
allow	EXPLAIN DELETE FROM users
allow	EXPLAIN (ANALYZE false) DELETE FROM users
allow	EXPLAIN ANALYZE SELECT * FROM users
allow	EXPLAIN (ANALYZE, BUFFERS) SELECT 1
allow	SHOW search_path
allow	VALUES (1), (2)
allow	TABLE users
allow	(SELECT 1) UNION (SELECT 2)
allow	SELECT 'a;b' AS text, "select" FROM t
allow	SELECT E'\'; DELETE FROM t; --'
allow	SELECT 'it''s'
allow	SELECT data #>> '{a,b}' FROM t
allow	select * from "update" -- a table named update
allow	SELECT lower(name), replace(name, 'a', 'b'), now() FROM users
allow	SELECT 'C:\path' AS p, name ~ '\d+' AS digits FROM t
allow	SELECT "we\ird" FROM t
block	DELETE FROM users
block	delete from users where id = 1
block	INSERT INTO users (id) VALUES (1)
block	UPDATE users SET name = 'x'
block	MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN DELETE
block	TRUNCATE users
block	DROP TABLE users
block	ALTER TABLE users ADD COLUMN x int
block	CREATE TABLE t (id int)
block	GRANT ALL ON users TO public
block	REVOKE ALL ON users FROM public
block	CALL cleanup()
block	DO $$ BEGIN DELETE FROM t; END $$
block	COPY users FROM STDIN
block	COPY users TO STDOUT
block	SET ROLE admin
block	SET default_transaction_read_only = off
block	BEGIN
block	VACUUM users
block	REFRESH MATERIALIZED VIEW v
block	WITH gone AS (DELETE FROM sessions RETURNING *) SELECT count(*) FROM gone
block	WITH x AS (SELECT 1) INSERT INTO t SELECT * FROM x
block	EXPLAIN ANALYZE DELETE FROM users
block	EXPLAIN (ANALYZE, BUFFERS) UPDATE users SET name = 'x'
block	EXPLAIN ANALYSE INSERT INTO t VALUES (1)
block	SELECT * INTO backup_users FROM users
block	SELECT * FROM users FOR UPDATE
block	SELECT * FROM users FOR NO KEY UPDATE
block	SELECT * FROM users FOR SHARE
block	SELECT setval('users_id_seq', 1)
block	SELECT "setval"('users_id_seq', 1)
block	SELECT pg_catalog."setval"('users_id_seq', 1)
block	SELECT nextval('users_id_seq')
block	SELECT pg_catalog.pg_terminate_backend(123)
block	SELECT dblink_exec('dbname=x', 'DELETE FROM t')
block	SELECT query_to_xml('DELETE FROM t RETURNING 1', true, true, '')
block	SELECT lo_unlink(1)
block	SELECT pg_sleep(60)
block	SELECT 1; DELETE FROM users
block	SELECT 1;DROP TABLE users;
block	SELECT 1\n; DELETE FROM users
block	SELECT 1 /* ; */
block	SELECT 1 /* /* */ DELETE FROM t */
block	SELECT /*!50000 1 */
block	SELECT 1 -- ; DELETE FROM t
block	SELECT `id` FROM users
block	SELECT 1 # comment
block	SELECT $tag$x$tag$
block	SELECT 'never closed
block	SELECT "never closed
block	SELECT 1 /* never closed
block	SELECT \x
block	SELECT 'x\'' ; DELETE FROM t; -- '
block	SELECT "x\"" ; DELETE FROM t; -- "
block	SELECT 'x\'; DELETE FROM t; --'
block
block
block	;
EOF
  # Unlocked, a write runs and Claude is told; reads pass either way. An expired unlock, or env's
  # unlock, opens nothing.
  token "$DBP" db
  sql warn "DELETE FROM sessions WHERE expired"
  sql allow "SELECT 1"
  token "$DBP" db -5
  sql block "DELETE FROM sessions WHERE expired"
  rm -rf "$DBP/.claude/state" && token "$DBP" env
  sql block "DELETE FROM sessions WHERE expired"
  rm -rf "$DBP/.claude"
  # The tool is dbWriteGuard.toolPattern: others are not judged; the SQL may come as query or
  # statement; a call without SQL text is a write.
  run_hook allow db-guard.sh "another server's tool" "$(sql_json mcp__db-dev__execute_sql sql 'DELETE FROM t')" CLAUDE_PROJECT_DIR="$DBP"
  run_hook block db-guard.sh "SQL in query" "$(sql_json mcp__db-prod__execute_sql query 'DROP TABLE t')" CLAUDE_PROJECT_DIR="$DBP"
  run_hook block db-guard.sh "SQL in statement" "$(sql_json mcp__db-prod__execute_sql statement 'DROP TABLE t')" CLAUDE_PROJECT_DIR="$DBP"
  run_hook block db-guard.sh "no SQL text" "$(tool_json mcp__db-prod__execute_sql '{"other": 1}')" CLAUDE_PROJECT_DIR="$DBP"
  mkdir -p "$DBP/.claude" && echo '{"dbWriteGuard": {"toolPattern": "mcp__pg__(query|execute)"}}' >"$DBP/.claude/agent-config.json"
  run_hook block db-guard.sh "configured tool, write" "$(sql_json mcp__pg__query query 'DELETE FROM t')" CLAUDE_PROJECT_DIR="$DBP"
  run_hook allow db-guard.sh "configured tool, read" "$(sql_json mcp__pg__query query 'SELECT 1')" CLAUDE_PROJECT_DIR="$DBP"
  run_hook allow db-guard.sh "default tool, no longer the pattern" "$(sql_json mcp__db-prod__execute_sql sql 'DELETE FROM t')" CLAUDE_PROJECT_DIR="$DBP"
  for bad in '{"dbWriteGuard": {"toolPattern": "("}}' '{"dbWriteGuard": {"toolPattern": ""}}' '{"dbWriteGuard": "x"}' '{"dbWriteGuard": {"tool": "x"}}'; do
    echo "$bad" >"$DBP/.claude/agent-config.json"
    run_hook block db-guard.sh "malformed config [$bad] keeps the default" "$(sql_json mcp__db-prod__execute_sql sql 'DELETE FROM t')" CLAUDE_PROJECT_DIR="$DBP"
  done
  rm -rf "$DBP/.claude"
fi

# 12. The unlock scripts (docs/unlock.md), run as the user runs them, and the rules of every reader
# of an unlock file. Skipped where the repo does not ship them.
if [ -f scripts/ops/unlock.sh ] && [ -f scripts/env/envfile.py ]; then
  holds() { # $1 label, then a command that must succeed
    local label="$1"
    shift
    if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)) && echo "FAIL $label"; fi
  }
  lacks() { ! grep -qF -- "$2" "$1"; }
  mode_of() { python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$1"; }
  # $1 dir: a repo holding the scripts, .claude/state/ ignored unless $2 is "unignored".
  kit_repo() {
    repo "$1" feature/probe
    mkdir -p "$1/scripts/ops" "$1/scripts/env" "$1/notes"
    cp -p scripts/ops/unlock.sh "$1/scripts/ops/"
    cp -p scripts/env/show.sh scripts/env/set.sh scripts/env/envfile.py "$1/scripts/env/"
    [ "${2:-}" = unignored ] || printf '.env\n.env.local\n.env.production\n.claude/state/\n' >"$1/.gitignore"
  }
  U="$TMP/unlock-proj"
  kit_repo "$U"
  T="$U/.claude/state/unlock"
  unlock() { (cd "$U" && env -u npm_config_user_agent "$BASH_BIN" scripts/ops/unlock.sh "$@"); }
  ends_in() { # $1 target, $2 seconds: the file ends about that far ahead
    local left=$(($(cat "$T/$1") - $(date +%s)))
    [ "$left" -ge $(($2 - 10)) ] && [ "$left" -le "$2" ]
  }

  # unlock.sh: its lines, the files it writes, the minutes it takes. The end is a clock time, with
  # the weekday in front when it falls on another day (`until Sun 00:10`).
  CLOCK='([A-Z][a-z]{2} )?[0-9]{2}:[0-9]{2}'
  ENV_LINE='^🔓 \.env unlocked until '"$CLOCK"' \(20 min\) — lock now: \./scripts/ops/unlock\.sh off env$'
  DB_LINE='^🔓 db writes unlocked until '"$CLOCK"' \(5 min\) — lock now: \./scripts/ops/unlock\.sh off db$'
  ENV_STATUS='^🔓 env  \.env open until '"$CLOCK"' \(20 min left\)'
  out="$(unlock env)"
  holds "unlock env line: $out" grep -qE "$ENV_LINE" <<<"$out"
  holds "the env file ends in 20 minutes" ends_in env 1200
  holds "the env file is 0600" [ "$(mode_of "$T/env")" = 600 ]
  holds "the unlock folder is 0700" [ "$(mode_of "$T")" = 700 ]
  holds "the state folder is 0700" [ "$(mode_of "$U/.claude/state")" = 700 ]
  out="$(unlock db 5)"
  holds "unlock db 5 line: $out" grep -qE "$DB_LINE" <<<"$out"
  holds "the db file ends in 5 minutes" ends_in db 300
  # Near midnight the end falls on the next day. A clock set to 23:56 (a TZ offset from UTC) makes
  # unlock.sh print the weekday form, and the same patterns accept it.
  late="$(python3 -c '
import time
off = (23 * 3600 + 56 * 60 - int(time.time()) % 86400) % 86400
off -= 86400 if off > 43200 else 0
print("PRB%s%02d:%02d:%02d" % ("-" if off >= 0 else "+", abs(off) // 3600, abs(off) % 3600 // 60, abs(off) % 60))')"
  for pair in "env|$ENV_LINE" "db 5|$DB_LINE" "status|$ENV_STATUS"; do
    # shellcheck disable=SC2086 # the target and its minutes are two words on purpose
    out="$(TZ="$late" unlock ${pair%%|*} | head -1)"
    holds "at 23:56, unlock ${pair%%|*} names the next day: $out" grep -qE "until [A-Z][a-z]{2} [0-9]{2}:[0-9]{2} " <<<"$out"
    holds "at 23:56, the probe pattern accepts it: $out" grep -qE "${pair#*|}" <<<"$out"
  done
  for agent in 'bun/1.2.0 npm/? node/v22.0.0' 'pnpm/9.1.0 npm/? node/v22.0.0' 'yarn/1.22.22 npm/? node/v22.0.0' 'npm/10.8.0 node/v22.0.0'; do
    out="$(cd "$U" && npm_config_user_agent="$agent" "$BASH_BIN" scripts/ops/unlock.sh env 1)"
    want="bun unlock"
    case "$agent" in pnpm/*) want="pnpm unlock" ;; yarn/*) want="yarn unlock" ;; npm/*) want="npm run unlock" ;; esac
    holds "run through ${agent%% *}, the line says $want" grep -q "lock now: $want off env\$" <<<"$out"
  done
  unlock env >/dev/null
  before="$(cat "$T/env")"
  for m in 0 241 abc -1 1.5 '' ' 5' 1e2 '０' '５'; do
    unlock env "$m" >/dev/null 2>&1
    code=$?
    holds "minutes [$m] are refused" [ "$code" = 2 ]
  done
  holds "refused minutes left env as it was" [ "$(cat "$T/env")" = "$before" ]
  unlock env 08 >/dev/null
  holds "08 reads as 8 minutes" ends_in env 480
  for bad in foo 'status now' 'off foo' 'env 5 6' 'off env db'; do
    # shellcheck disable=SC2086 # each case is several words on purpose
    unlock $bad >/dev/null 2>&1
    code=$?
    holds "unlock $bad is refused" [ "$code" = 2 ]
  done
  unlock >/dev/null 2>&1
  code=$?
  holds "unlock with no argument is refused" [ "$code" = 2 ]
  holds "unlock help prints the usage" grep -q '^usage:' <<<"$(unlock help)"
  unlock off >/dev/null && unlock env >/dev/null
  out="$(unlock status)"
  holds "status shows env open: $out" grep -qE "$ENV_STATUS" <<<"$out"
  holds "status shows db locked" grep -q '^🔒 db   db writes locked$' <<<"$out"
  (umask 077 && printf '%s\n' "$(($(date +%s) - 5))" >"$T/db" && printf 'x\n' >"$T/stray")
  out="$(unlock status)"
  holds "an expired db shows locked" grep -q '^🔒 db' <<<"$out"
  holds "status removed the expired and the stray file" test ! -e "$T/db" -a ! -e "$T/stray"
  unlock db >/dev/null && unlock off env >/dev/null
  holds "off env locks env and keeps db" test ! -e "$T/env" -a -e "$T/db"
  holds "off prints its line" grep -q '^🔒 everything locked (env, db)$' <<<"$(unlock off)"
  holds "off locks every target" [ -z "$(ls -A "$T")" ]
  # Only the script itself runs: through a symlink, a hard link or a copy it refuses and writes nothing.
  ln -s ../scripts/ops/unlock.sh "$U/notes/u"
  (cd "$U" && "$BASH_BIN" notes/u env) >/dev/null 2>&1
  code=$?
  holds "unlock.sh run through a symlink is refused" [ "$code" = 2 ]
  ln -s unlock.sh "$U/scripts/ops/unlock-link.sh"
  (cd "$U" && "$BASH_BIN" scripts/ops/unlock-link.sh env) >/dev/null 2>&1
  code=$?
  holds "unlock.sh run through a symlink beside it is refused" [ "$code" = 2 ]
  rm -f "$U/scripts/ops/unlock-link.sh"
  ln "$U/scripts/ops/unlock.sh" "$TMP/unlock-hard.sh"
  unlock env >/dev/null 2>&1
  code=$?
  holds "unlock.sh with a second hard link is refused" [ "$code" = 2 ]
  rm -f "$TMP/unlock-hard.sh" "$U/notes/u"
  mkdir -p "$U/notes/deep" && cp -p "$U/scripts/ops/unlock.sh" "$U/notes/deep/u.sh"
  (cd "$U" && "$BASH_BIN" notes/deep/u.sh env) >/dev/null 2>&1
  code=$?
  holds "a copy of unlock.sh is refused" [ "$code" = 2 ]
  rm -rf "$U/notes/deep"
  holds "the refused runs wrote nothing" [ -z "$(ls -A "$T")" ]
  mv "$U/.claude/state" "$TMP/state-away" && ln -s "$TMP/state-away" "$U/.claude/state"
  unlock env >/dev/null 2>&1
  code=$?
  holds "a symlinked .claude/state is refused" [ "$code" = 2 ]
  rm "$U/.claude/state" && mv "$TMP/state-away" "$U/.claude/state"
  UN="$TMP/unlock-unignored"
  kit_repo "$UN" unignored
  out="$(cd "$UN" && "$BASH_BIN" scripts/ops/unlock.sh env)"
  holds "unlock warns when .claude/state/ is not ignored" grep -q 'not in .gitignore' <<<"$out"

  # Every reader of an unlock file agrees on each case: safety-check before set.sh, set.sh itself,
  # db-guard and unlock.sh status. $1 the case, $2 open or locked; the case is set up for env and db.
  printf 'API_KEY=probe-secret-value\nPORT=3000\n' >"$U/.env"
  put() { # $1 content, [$2 mode]
    rm -rf "$T" && mkdir -p "$T" && chmod 700 "$U/.claude/state" "$T"
    for t in env db; do
      printf '%s' "$1" >"$T/$t" && chmod "${2:-600}" "$T/$t"
    done
  }
  soon() { printf '%s\n' "$(($(date +%s) + ${1:-600}))"; }
  agree() {
    local label="$1" want="$2" code n=0 sc=block db=block rc=2
    [ "$want" = open ] && n=2 sc=allow db=warn rc=0
    run_hook "$sc" safety-check.sh "set.sh with an unlock file $label" "$(bash_json "$U" "printf 3001 | bash scripts/env/set.sh .env PORT")" CLAUDE_PROJECT_DIR="$U"
    if has db-guard.sh; then
      run_hook "$db" db-guard.sh "a write with an unlock file $label" "$DW" CLAUDE_PROJECT_DIR="$U"
    fi
    (cd "$U" && printf 3001 | "$BASH_BIN" scripts/env/set.sh .env PORT) >/dev/null 2>&1
    code=$?
    holds "set.sh with an unlock file $label exits $rc" [ "$code" = "$rc" ]
    holds "unlock status reads an unlock file $label as $want" [ "$(unlock status | grep -c '^🔓')" = "$n" ]
  }
  put "$(soon)"
  agree "as unlock.sh writes it" open
  put "$(soon -5)"
  agree "that has expired" locked
  put "$(soon $((245 * 60)))"
  agree "past the 240-minute limit" locked
  # The same, with a modification time set ahead so only the limit from now can refuse it.
  put "$(soon $((300 * 60)))"
  python3 -c 'import os, sys, time; t = time.time() + 200 * 60; [os.utime(p, (t, t)) for p in sys.argv[1:]]' "$T/env" "$T/db"
  agree "past the limit from now, written ahead in time" locked
  put "$(soon)" 644
  agree "readable by others" locked
  put "$(soon)" && chmod 755 "$T"
  agree "in a folder open to others" locked
  put "abc"
  agree "holding no number" locked
  put "$(soon)"$'\n'"$(soon)"
  agree "holding two numbers" locked
  put "$(soon)" && touch -t 202001010000 "$T/env" "$T/db"
  agree "written years ago" locked
  put "$(soon)"
  for t in env db; do mv "$T/$t" "$TMP/real-$t" && ln -s "$TMP/real-$t" "$T/$t"; done
  agree "that is a symlink" locked
  put "$(soon)"
  for t in env db; do ln "$T/$t" "$TMP/hard-$t"; done
  agree "with a second hard link" locked
  rm -f "$TMP"/hard-* "$TMP"/real-*
  put "$(soon)" && mv "$T" "$TMP/real-unlock" && ln -s "$TMP/real-unlock" "$T"
  agree "in a symlinked folder" locked
  rm -f "$T" && rm -rf "$TMP/real-unlock"
  put "$(soon)" && git -C "$U" add -f .claude/state/unlock
  agree "tracked by git" locked
  git -C "$U" rm -q -r --cached .claude/state/unlock
  unlock off >/dev/null
  agree "that is absent" locked

  # show.sh: every key, no secret, the template's missing keys.
  S1=sk_probe_51Habcdefghijklmnop
  cat >"$U/.env.production" <<EOF
# a comment holding sk_probe_comment_secret
NODE_ENV=production
PORT=3000
DEBUG=false
API_URL=https://api.example.com/v1
DATABASE_URL=postgres://app:probePassw0rdValue@db.internal:5432/app?sslmode=require&password=probeQueryPass99
REDIS_HOST=redis.internal:6379
STRIPE_SECRET_KEY=$S1
SESSION_SIGNER=probeRandomValue12345XYZ
SESSION_SIGNING=probeSessionSignSecret
SUPABASE_ANON=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJwcm9iZSJ9.probeSignatureValue9
ADMIN_PW=hunter2
FLAG_NAME=plainword
CACHE_TTL=30s
LOG_LEVEL=debug
export TZ='UTC'
MULTI="probe line one
probe line two"
EMPTY=
this line sk_probe_badline_secret is not a pair
EOF
  printf 'NODE_ENV=\nPORT=\nSENTRY_DSN=\n' >"$U/.env.production.example"
  (cd "$U" && "$BASH_BIN" scripts/env/show.sh .env.production) >"$TMP/show.out" 2>&1
  code=$?
  holds "show.sh exits 1 when the template has a key the file lacks" [ "$code" = 1 ]
  for secret in sk_probe_comment_secret probePassw0rdValue probeQueryPass99 "$S1" probeRandomValue12345XYZ probeSessionSignSecret probeSignatureValue9 hunter2 plainword 'probe line' sk_probe_badline_secret; do
    holds "show.sh hides $secret" lacks "$TMP/show.out" "$secret"
  done
  for shown in production 3000 false https://api.example.com/v1 'postgres://app:…(22 chars)@db.internal:5432/app?sslmode=require&password=prob…(16 chars)' \
    redis.internal:6379 "sk_p…(${#S1} chars)" 30s debug UTC '(empty)' 'missing SENTRY_DSN' 'line 20 is not KEY=VALUE' 'env is locked'; do
    holds "show.sh prints [$shown]" grep -qF -- "$shown" "$TMP/show.out"
  done
  holds "show.sh skips comments rather than reporting them" lacks "$TMP/show.out" 'line 1 is not'
  holds "show.sh masks a short value under a secret-named key" grep -qE '^  ADMIN_PW +…\(7 chars\)$' "$TMP/show.out"
  holds "show.sh masks a secret under a widened key name (SESSION/SIGN)" grep -qE '^  SESSION_SIGNING .*…\(' "$TMP/show.out"
  holds "show.sh masks a plain-looking word by default" grep -qE '^  FLAG_NAME +…\(9 chars\)$' "$TMP/show.out"
  (cd "$U" && "$BASH_BIN" scripts/env/show.sh .env) >/dev/null 2>&1
  code=$?
  holds "show.sh exits 0 without a template" [ "$code" = 0 ]
  for bad in notes .env.absent; do
    (cd "$U" && "$BASH_BIN" scripts/env/show.sh "$bad") >/dev/null 2>&1
    code=$?
    holds "show.sh refuses $bad" [ "$code" = 2 ]
  done

  # set.sh: refused while locked; unlocked, it changes one line and keeps the rest.
  setv() { # $1 file, $2 key, $3 value; prints set.sh's output
    (cd "$U" && printf '%s' "$3" | "$BASH_BIN" scripts/env/set.sh "$1" "$2") >"$TMP/set.out" 2>&1
  }
  cp "$U/.env.production" "$TMP/prod.before"
  setv .env.production STRIPE_SECRET_KEY sk_probe_NEWsecretValue123456
  code=$?
  holds "set.sh refuses while env is locked" [ "$code" = 2 ]
  holds "the locked refusal names the unlock command" grep -q 'scripts/ops/unlock.sh env' "$TMP/set.out"
  holds "a locked set.sh changed nothing" cmp -s "$U/.env.production" "$TMP/prod.before"
  unlock env >/dev/null
  setv .env.production STRIPE_SECRET_KEY sk_probe_NEWsecretValue123456
  code=$?
  holds "set.sh updates a key while env is unlocked" [ "$code" = 0 ]
  holds "set.sh prints the new value masked" lacks "$TMP/set.out" sk_probe_NEWsecretValue123456
  holds "set.sh changed only that line" python3 -c '
import sys
a, b = (open(p).read().split("\n") for p in sys.argv[1:3])
sys.exit(not (len(a) == len(b) and [i for i, (x, y) in enumerate(zip(a, b)) if x != y] == [7]
              and b[7] == "STRIPE_SECRET_KEY=sk_probe_NEWsecretValue123456"))' "$TMP/prod.before" "$U/.env.production"
  holds "one backup, private, holding the old file" python3 -c '
import os, sys
d = sys.argv[1]
names = [n for n in os.listdir(d) if n.startswith(".env.production.")]
sys.exit(not (len(names) == 1 and os.stat(os.path.join(d, names[0])).st_mode & 0o777 == 0o600
              and open(os.path.join(d, names[0])).read() == open(sys.argv[2]).read()))' "$U/.claude/state/env-backups" "$TMP/prod.before"
  holds "the audit log names the key" grep -q "	.env.production	STRIPE_SECRET_KEY	updated$" "$U/.claude/state/env-audit.log"
  run_hook block safety-check.sh "a recursive grep over the backups" "$(bash_json "$U" "grep -r STRIPE .claude/state")" CLAUDE_PROJECT_DIR="$U"
  # A nested file's backup sits in the same folders under env-backups/, keeping its .env* name.
  mkdir -p "$U/apps/web" && printf 'API_KEY=probe-nested-value\n' >"$U/apps/web/.env"
  setv apps/web/.env API_KEY probe-nested-new
  code=$?
  holds "set.sh updates a nested .env" [ "$code" = 0 ]
  holds "its backup keeps the folder and the .env name, private" python3 -c '
import glob, os, sys
b = glob.glob(os.path.join(sys.argv[1], "apps", "web", ".env.*"))
modes = [os.stat(p).st_mode & 0o777 for p in b] + [os.stat(os.path.join(sys.argv[1], d)).st_mode & 0o777 for d in ("apps", "apps/web")]
sys.exit(not (len(b) == 1 and modes == [0o600, 0o700, 0o700]))' "$U/.claude/state/env-backups"
  run_hook block safety-check.sh "cat of a nested backup" "$(bash_json "$U" "cat .claude/state/env-backups/apps/web/.env.*")" CLAUDE_PROJECT_DIR="$U"
  holds "the audit log holds no value" lacks "$U/.claude/state/env-audit.log" sk_probe_NEWsecretValue123456
  holds "the audit log is 0600" [ "$(mode_of "$U/.claude/state/env-audit.log")" = 600 ]
  setv .env.production TZ Europe/Berlin
  holds "set.sh keeps export and single quotes" grep -qx "export TZ='Europe/Berlin'" "$U/.env.production"
  setv .env.production NEW_FLAG true
  holds "set.sh appends a new key" [ "$(tail -n 1 "$U/.env.production")" = NEW_FLAG=true ]
  setv .env.production DOLLAR 'pa$$ word'
  holds "set.sh single-quotes a value with \$ and a space" grep -qx "DOLLAR='pa\$\$ word'" "$U/.env.production"
  setv .env.production MULTI "$(printf 'first\nsecond')"
  holds "set.sh writes a multi-line value that reads back the same" python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import envfile
got = {e["key"]: e["value"] for e in envfile.parse(envfile.read_lines(sys.argv[2])) if "key" in e}
sys.exit(got.get("MULTI") != "first\nsecond")' "$U/scripts/env" "$U/.env.production"
  cp "$U/.env.production" "$TMP/prod.before"
  setv .env.production MIXED "it's \$HOME"
  code=$?
  holds "set.sh refuses a value no quoting keeps intact" [ "$code" = 2 ]
  holds "that refusal changed nothing" cmp -s "$U/.env.production" "$TMP/prod.before"
  ln -s .env.production "$U/.env.link"
  mkdir -p "$TMP/outside" && printf 'A=1\n' >"$TMP/outside/.env"
  for bad in ".env.production.example|A" ".env.link|A" "$TMP/outside/.env|A" ".env.production|1BAD" "package.json|A"; do
    setv "${bad%%|*}" "${bad#*|}" x
    code=$?
    holds "set.sh refuses ${bad%%|*} ${bad#*|}" [ "$code" = 2 ]
  done
  holds "the refusals changed nothing" cmp -s "$U/.env.production" "$TMP/prod.before"
  # The read-back check: a line that would not read back as the value is never written.
  (cd "$U" && printf 'probe' | python3 -I -c 'import sys
sys.path.insert(0, "scripts/env")
import envfile
envfile.render = lambda value, quote: "\"" + value
sys.exit(envfile.main(["envfile.py", "set", ".env.production", "TZ"]))') >/dev/null 2>&1
  code=$?
  holds "set.sh refuses a line that would not read back" [ "$code" = 2 ]
  holds "that refusal changed nothing" cmp -s "$U/.env.production" "$TMP/prod.before"
  (cd "$UN" && printf x | "$BASH_BIN" scripts/env/set.sh .env A) >"$TMP/set.out" 2>&1
  code=$?
  holds "set.sh refuses where .claude/state/ is not ignored" [ "$code" = 2 ]
  holds "that refusal says to ignore .claude/state/" grep -q 'gitignore' "$TMP/set.out"
  unlock off >/dev/null

  # The forging routes, the way Claude Code runs them: each command goes to safety-check first and
  # runs only when let through. None may leave an unlock file behind or change scripts/env/.
  V="$TMP/forge-proj"
  kit_repo "$V"
  helpers_sum() { cat "$V/scripts/env/show.sh" "$V/scripts/env/set.sh" "$V/scripts/env/envfile.py" | cksum; }
  helpers_before="$(helpers_sum)"
  echo '{"scripts": {"unlock": "bash scripts/ops/unlock.sh", "u2": "bash scripts/ops/unlock.sh"}}' >"$V/package.json"
  env_files "$V"
  mkdir -p "$TMP/forge-src/.claude/state/unlock" && chmod 700 "$TMP/forge-src/.claude/state" "$TMP/forge-src/.claude/state/unlock"
  soon >"$TMP/forge-src/.claude/state/unlock/env" && chmod 600 "$TMP/forge-src/.claude/state/unlock/env"
  tar -cf "$TMP/forge.tar" -C "$TMP/forge-src" .claude
  forged=0
  while IFS= read -r cmd; do
    cmd="${cmd//@TMP@/$TMP}"
    if printf '%s' "$(bash_json "$V" "$cmd")" | env CLAUDE_PROJECT_DIR="$V" "$BASH_BIN" "$HOOKS/safety-check.sh" >/dev/null 2>&1; then
      forged=$((forged + 1)) && echo "FAIL safety-check let a forging command run: $cmd"
      (cd "$V" && "$BASH_BIN" -c "$cmd") >/dev/null 2>&1
    fi
  done <<'EOF'
bash scripts/ops/unlock.sh env
./scripts/ops/unlock.sh env 240
bun unlock env
npm run unlock env
pnpm unlock env
yarn unlock env
bun run u2 env
bash -c 'bash scripts/ops/unlock.sh env'
echo 'bash scripts/ops/unlock.sh env' | bash
bash < scripts/ops/unlock.sh
mkdir -p .claude/state/unlock && date +%s > .claude/state/unlock/env
mkdir -p -m 700 .claude/state/unlock; echo $(( $(date +%s) + 600 )) > .claude/state/unlock/env
mkdir -p .claude && cd .claude && mkdir -p state/unlock && cd state/unlock && touch env
D=.claude/state/unlock; mkdir -p "$D" && touch "$D/env"
a=unl; b=ock; mkdir -p .claude/state/$a$b && touch .claude/state/$a$b/env
mkdir -p "$(printf %s .claude/state/unlock)"
echo .claude/state/unlock | xargs mkdir -p
python3 -c "import os; os.makedirs('.claude/state/unlock', exist_ok=True); open('.claude/state/unlock/env', 'w').write('9')"
python3 -c "import os; os.makedirs(os.path.join('.claude', 'state', 'unlock'), exist_ok=True)"
node -e "require('fs').mkdirSync('.claude/state/unlock', {recursive: true})"
perl -e 'mkdir ".claude"; mkdir ".claude/state"; mkdir ".claude/state/unlock"'
cp -r @TMP@/forge-src/.claude .
cp -R @TMP@/forge-src/. .
rsync -a @TMP@/forge-src/ .
tar -xf @TMP@/forge.tar
mkdir -p .claude && ln -s @TMP@/forge-src/.claude/state .claude/state
timeout 5 bash scripts/ops/unlock.sh env
git -c alias.u='!bash scripts/ops/unlock.sh' u env
bash scripts/ops/unl*.sh env
bash $(ls scripts/ops/u*) env
find scripts/ops -name 'u*' -exec bash {} env \;
ls scripts/ops/* | xargs -n1 bash
for f in scripts/ops/*.sh; do bash "$f" env; done
HOME=.claude/state; mkdir -p ~/unlock && touch ~/unlock/env
printf '#!/bin/sh\ncat "$1"\n' > scripts/env/show.sh
sed -i.bak 's/^/#/' scripts/env/envfile.py
cd scripts/env && printf 'import sys\nprint(open(sys.argv[2]).read())\n' > envfile.py
python3 -c "open('scripts/env/envfile.py', 'w').write('print(1)')"
cp @TMP@/forged-helpers/scripts/env/show.sh scripts/env/show.sh
cp -r @TMP@/forged-helpers/scripts .
rsync -a @TMP@/forged-helpers/ .
EOF
  holds "every forging route was refused" [ "$forged" = 0 ]
  holds "no unlock file exists after the forging routes" [ ! -e "$V/.claude/state/unlock" ]
  holds "scripts/env/ is unchanged after them" [ "$(helpers_sum)" = "$helpers_before" ]
  (cd "$V" && "$BASH_BIN" scripts/env/show.sh .env) >"$TMP/forge-show.out" 2>&1
  holds "show.sh still masks the secret after them" lacks "$TMP/forge-show.out" probe-secret-value
  (cd "$V" && printf x | "$BASH_BIN" scripts/env/set.sh .env API_KEY) >/dev/null 2>&1
  code=$?
  holds "set.sh still refuses after them" [ "$code" = 2 ]
  # The control: the user's own run (`!` runs outside the hooks) does open it.
  (cd "$V" && "$BASH_BIN" scripts/ops/unlock.sh env) >/dev/null
  (cd "$V" && printf x | "$BASH_BIN" scripts/env/set.sh .env API_KEY) >/dev/null 2>&1
  code=$?
  holds "after the user's unlock, set.sh runs" [ "$code" = 0 ]
fi

echo "hook probes: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
