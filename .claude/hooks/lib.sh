#!/usr/bin/env bash
# Shared helpers for the hooks in this directory. Source it, don't execute it.
# Contract: https://code.claude.com/docs/en/hooks. The hooks read their JSON payload on stdin, block
# a PreToolUse call with exit 2 and the reason on stderr, and reach Claude after a tool ran through
# hookSpecificOutput.additionalContext (plain stdout of PreToolUse/PostToolUse only reaches the
# debug log).
# Runs under /bin/bash 3.2 on macOS: no ${x,,}, no declare -A, no mapfile. A syntax error here exits
# 2, which blocks every tool call, so scripts/check/hook-probes.sh runs before any change lands.
# No hook opens a network connection or installs anything; the only programs they start are git,
# python3, jq, coreutils and the project's own formatters and linters.
#
# Fail modes, chosen per hook by hook_start (see .claude/hooks/README.md, "Fail modes"):
#   guard     PreToolUse. Only exit 2 stops a call; a crash, exit 1 or Claude Code's own timeout
#             lets it through. So a guard that cannot do its job (payload not a JSON object, no
#             JSON reader, python3 broken or too slow) refuses the call and says how to proceed.
#   feedback  PostToolUse, UserPromptSubmit, SessionStart. Context only: any failure exits 0 and
#             says nothing, since the tool already ran and the prompt must go through.
#
# Per-repo settings live in .claude/agent-config.json (every key optional; see
# .claude/agent-config.example.json). Without the file the defaults below apply.
# Multi-repo workspaces are off unless AGENT_WORKSPACE_ROOT names the folder that holds the repos.
# Installed as a plugin (CLAUDE_PLUGIN_ROOT set), every hook stays silent in a project that has not
# opted in with .claude/agent-config.json or .claude/agent-config-kit.lock (hook_gate). Once a
# project has opted in, the plugin remembers it, so deleting both files does not turn the hooks off.

# The defaults of .claude/agent-config.json. A key the file sets replaces its default whole.
HOOK_DEFAULTS='{
  "protectedBranches": ["dev", "prod", "main", "master"],
  "protectedPaths": ["src", "app", "components", "content", "tests", "scripts", ".claude", ".agent",
                     ".agents", "_workflow-source", ".github", ".git",
                     "AGENTS.md", "SSOT.md", "CLAUDE.md", "PRODUCT.md", "DESIGN.md"],
  "generatedPaths": ["src/lib/api/generated", "src/generated", "openapi.json", "openapi.yaml", "openapi.yml"],
  "commandWrappers": [],
  "localePairs": [],
  "migrationsDirs": ["src/db/migrations", "drizzle", "src/app/db/migrations/versions", "alembic/versions",
                     "migrations/versions"],
  "dbWriteGuard": {"toolPattern": "mcp__db-prod__execute_sql"}
}'

# Every git a hook starts reads only, so core.fsmonitor, the one setting a read such as rev-parse or
# ls-files runs as a command, is off for it whatever the repo's config says. (The Python checks set
# it for their own git runs: HOOK_PY_PRELUDE.)
git() {
  command git -c core.fsmonitor=false "$@"
}

# One deadline for a guard's whole run, inside Claude Code's 10 s hook timeout, which would let the
# call through. Each capped step gets at most what is left of it (hook_cap), and a guard that is
# still running when it passes refuses the call (hook_exit), so steps that each keep to their own
# cap cannot add up past the timeout. SECONDS counts whole seconds and lags the clock by less than
# one, so 8 on it is at most 9 s. It is set here, not inherited from the environment.
HOOK_DEADLINE=8
SECONDS=0

# The folder the running hooks live in, physical: .claude/hooks as a template, the plugin's
# scripts/ as a plugin. Taken while this file is sourced, before hook_root changes folder; the shell
# rules refuse any change to it (the guard scripts, in analyze_command).
HOOK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"

# Every hook begins with hook_start <guard|feedback> <tag> [plaintext]: the plugin gate, the
# payload, the payload check (guards only) and the project folder. `plaintext` lets a guard go on
# with HOOK_NO_READER=1 when neither python3 nor jq exists; safety-check.sh then judges the raw
# payload with its plain-text rules instead of refusing every command.
hook_start() {
  HOOK_KIND="$1"
  HOOK_TAG="$2"
  HOOK_NO_READER=""
  hook_gate
  [[ "$HOOK_KIND" != guard ]] || trap hook_exit EXIT
  hook_input
  if [[ "$HOOK_KIND" == guard ]]; then
    hook_payload_check
    if [[ -n "$HOOK_NO_READER" && "${3:-}" != plaintext ]]; then
      hook_fail "neither python3 nor jq is installed, so this tool call could not be read."
    fi
  fi
  hook_root
}

# Plugin mode only (CLAUDE_PLUGIN_ROOT is set when Claude Code runs a plugin's hook): a project that
# has not opted in, with neither .claude/agent-config.json nor .claude/agent-config-kit.lock, gets
# no hook at all. Copied into a repo as a template, the hooks always run.
# The opt-in sticks: a project seen with either file is recorded in the plugin's data folder
# (hook_optin_file), and when both files are gone later the hooks say so on stderr and keep
# guarding. Only the user undoes it, by disabling the plugin for the project or deleting the record.
hook_gate() {
  [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] || return 0
  local dir="${CLAUDE_PROJECT_DIR:-}" real record
  [[ -n "$dir" ]] || dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  real="$(cd "$dir" 2>/dev/null && pwd -P)" && dir="$real"
  record="$(hook_optin_file)"
  if [[ -f "$dir/.claude/agent-config.json" || -f "$dir/.claude/agent-config-kit.lock" ]]; then
    if [[ -n "$record" && "$dir" != *$'\n'* ]] && ! grep -qxF -- "$dir" "$record" 2>/dev/null; then
      mkdir -p "${record%/*}" 2>/dev/null && printf '%s\n' "$dir" >>"$record" 2>/dev/null
    fi
    return 0
  fi
  if [[ -n "$record" && "$dir" != *$'\n'* ]] && grep -qxF -- "$dir" "$record" 2>/dev/null; then
    printf '%s\n' "${HOOK_TAG:-[hook]} This project opted in to these hooks, and .claude/agent-config.json and .claude/agent-config-kit.lock are both gone now, so the hooks keep guarding it with their defaults. To stop them here, the user disables the plugin for this project, or removes this folder's line from $record." >&2
    return 0
  fi
  cat >/dev/null 2>&1
  exit 0
}

# The plugin's record of the projects that opted in, one folder per line; empty outside plugin mode
# or without a data folder.
hook_optin_file() {
  [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -n "${CLAUDE_PLUGIN_DATA:-}" ]] || return 0
  printf '%s' "$CLAUDE_PLUGIN_DATA/opted-in-projects"
}

# A hook that cannot do its job. A guard refuses the call, says why and how to get past it; a
# feedback hook exits 0 and says nothing. Past the deadline the reason says that too.
hook_fail() {
  [[ "${HOOK_KIND:-guard}" == guard ]] || exit 0
  local why="$1"
  if [[ "$SECONDS" -ge "$HOOK_DEADLINE" && "$why" != *"ran out of time"* ]]; then
    why="$why It also ran out of time: a guard stops at 9 s, inside Claude Code's 10 s hook timeout."
  fi
  block "${HOOK_TAG:-[hook]} BLOCKED: $why" \
    "This guard refuses what it cannot check. Fix the cause (install or repair python3 or jq); if the call must happen as is, the user does it themselves (\`!\` for a shell command)." \
    "To turn the guard off, the user removes its entry from .claude/settings.json, or disables the plugin that installs it."
}

# A guard's EXIT trap: a run that would let the call through after the deadline refuses it instead,
# since a step cut short by the deadline may have read nothing (an empty field reads as "no file").
hook_exit() {
  local rc=$?
  if [[ "$rc" -eq 0 && "$SECONDS" -ge "$HOOK_DEADLINE" ]]; then
    hook_fail "this guard ran out of time before it finished checking the call: it stops at 9 s, inside Claude Code's 10 s hook timeout (python3, jq or git answered too slowly)."
  fi
  exit "$rc"
}

# Claude Code sends the tool call as JSON on stdin; no environment variable carries it.
# Call hook_input once at top level, before any $(...), so every hook_field sees the payload.
hook_input() {
  [[ -n "${HOOK_INPUT+x}" ]] || HOOK_INPUT="$(cat)"
}

# A time cap in seconds: $1, or HOOK_PROBE_CAP when that is lower (hook-probes.sh only; it can
# only make a hook give up sooner, which a guard turns into a refusal). A guard's cap is also no
# more than what is left before its deadline, and 0 once it has passed (run_capped then runs nothing).
hook_cap() {
  local cap="$1" left
  if [[ "${HOOK_PROBE_CAP:-}" =~ ^[1-9]$ && "$HOOK_PROBE_CAP" -lt "$cap" ]]; then
    cap="$HOOK_PROBE_CAP"
  fi
  if [[ "${HOOK_KIND:-}" == guard ]]; then
    left=$((HOOK_DEADLINE - SECONDS))
    [[ "$left" -ge "$cap" ]] || cap=$((left > 0 ? left : 0))
  fi
  printf '%s' "$cap"
}

# python3 for a quick read, capped so a hung interpreter cannot outlast the hook's timeout.
hook_py() {
  run_capped "$(hook_cap 3)" python3 "$@"
}

# Guards only: the payload is one JSON object. jq or python3 decides; when neither answers and
# neither is installed, HOOK_NO_READER=1 (hook_start decides what that means). Anything else that
# no reader accepts (bad JSON, an array, empty input, a python3 that is present but broken) refuses.
hook_payload_check() {
  local verdict=""
  if command -v jq &>/dev/null; then
    verdict="$(jq -rs 'if length == 1 and (.[0] | type) == "object" then "object" else "other" end' \
      <<<"$HOOK_INPUT" 2>/dev/null)"
  fi
  if [[ "$verdict" != object && "$verdict" != other ]] && command -v python3 &>/dev/null; then
    verdict="$(hook_py -c '
import json, sys
try:
    data = json.loads(sys.stdin.buffer.read())
except ValueError:
    data = None
print("object" if isinstance(data, dict) else "other")' <<<"$HOOK_INPUT" 2>/dev/null)"
  fi
  case "$verdict" in
  object) return 0 ;;
  other) hook_fail "this tool call's payload is not a JSON object, so it could not be checked." ;;
  esac
  if command -v jq &>/dev/null || command -v python3 &>/dev/null; then
    hook_fail "this tool call could not be read (python3 failed or was too slow, and jq is missing or refused the payload)."
  fi
  HOOK_NO_READER=1
}

# jq first for speed; python3 when jq is missing or refuses the payload (a lone surrogate, a deep
# array), because an empty field would let the command through unread.
hook_field() {
  command -v jq &>/dev/null && jq -r "$1 // empty" <<<"$HOOK_INPUT" 2>/dev/null && return 0
  hook_py -c '
import json, sys
node = json.loads(sys.stdin.buffer.read() or b"{}")
for key in sys.argv[1].lstrip(".").split("."):
    node = node.get(key) if isinstance(node, dict) else None
text = "" if node is None else node if isinstance(node, str) else json.dumps(node)
sys.stdout.buffer.write(text.encode("utf-8", "surrogatepass") + b"\n")' "$1" <<<"$HOOK_INPUT" 2>/dev/null
}

# The physical spelling of a path (symlinked folders resolved), for a path that need not exist yet.
# macOS reaches its temp folders through symlinks (/tmp, /var), and ROOT is compared by prefix.
hook_physical() {
  local dir="$1" rest=""
  while [[ ! -d "$dir" ]]; do
    rest="/${dir##*/}$rest"
    dir="${dir%/*}"
    [[ -n "$dir" ]] || {
      printf '%s' "$1"
      return 0
    }
  done
  dir="$(cd "$dir" 2>/dev/null && pwd -P)" || {
    printf '%s' "$1"
    return 0
  }
  printf '%s%s' "${dir%/}" "$rest"
}

# Hooks start in whatever directory the session last cd'ed into, so anchor to the project.
# WORKSPACE is the opt-in multi-repo root (AGENT_WORKSPACE_ROOT), empty when unset.
hook_root() {
  ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  cd "$ROOT" 2>/dev/null || hook_fail "the project folder $ROOT cannot be entered."
  ROOT="$(pwd -P)"
  WORKSPACE=""
  if [[ -n "${AGENT_WORKSPACE_ROOT:-}" && -d "${AGENT_WORKSPACE_ROOT}" ]]; then
    WORKSPACE="$(cd "$AGENT_WORKSPACE_ROOT" && pwd -P)"
  fi
}

# Absolute path of the tool's target file, or empty. Write/Edit send file_path, relative paths
# resolving against the call's cwd. Serena sends relative_path against its active project: this
# repo, or, in workspace mode, the workspace root (so the path carries this repo's folder prefix).
hook_file() {
  local file cwd rel
  file="$(hook_field .tool_input.file_path)"
  if [[ -z "$file" ]]; then
    rel="$(hook_field .tool_input.relative_path)"
    [[ -n "$rel" ]] || return 0
    file="$ROOT/$rel"
    if [[ -n "$WORKSPACE" && ! -e "$file" ]]; then
      if [[ "$ROOT" == "$WORKSPACE"/* && "$rel" == "${ROOT#"$WORKSPACE"/}/"* ]]; then
        file="$WORKSPACE/$rel"
      elif [[ -e "$WORKSPACE/$rel" ]]; then
        file="$WORKSPACE/$rel"
      fi
    fi
  elif [[ "$file" != /* ]]; then
    cwd="$(hook_field .cwd)"
    file="${cwd:-$ROOT}/$file"
  fi
  hook_physical "$file"
}

# The file a write to $1 lands in: $1 itself, or, when $1 is a symlink (a dangling one included),
# the file it finally points to. realpath resolves an existing target, readlink follows a dangling
# chain link by link, python3 is the last resort. Empty when none of them can say.
hook_target() {
  local p="$1" t n=0
  if [[ ! -L "$p" ]]; then
    printf '%s' "$p"
    return 0
  fi
  if [[ -e "$p" ]] && command -v realpath &>/dev/null && t="$(realpath -- "$p" 2>/dev/null)" && [[ -n "$t" ]]; then
    printf '%s' "$t"
    return 0
  fi
  if command -v readlink &>/dev/null; then
    while [[ -L "$p" && "$n" -lt 40 ]] && t="$(readlink -- "$p" 2>/dev/null)" && [[ -n "$t" ]]; do
      [[ "$t" == /* ]] || t="${p%/*}/$t"
      p="$(hook_physical "$t")"
      n=$((n + 1))
    done
    [[ -L "$p" ]] || {
      printf '%s' "$p"
      return 0
    }
  fi
  command -v python3 &>/dev/null || return 0
  hook_py -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null
}

# Python shared by the embedded programs below: the config loader and the workspace helpers.
read -r -d '' HOOK_PY_PRELUDE <<'PY'
import fnmatch, glob, json, os, re, shlex, stat, subprocess, sys, time

# Every git these checks start reads only: core.fsmonitor (the one setting a read like ls-files or
# rev-parse runs as a command) is switched off for them, whatever a repo's config says.
_n = int(os.environ.get("GIT_CONFIG_COUNT") or 0) if (os.environ.get("GIT_CONFIG_COUNT") or "0").isdigit() else 0
os.environ.update({"GIT_CONFIG_COUNT": str(_n + 1), f"GIT_CONFIG_KEY_{_n}": "core.fsmonitor",
                   f"GIT_CONFIG_VALUE_{_n}": "false"})
DEFAULTS = json.loads(os.environ.get("HOOK_DEFAULTS") or "{}")


def inside(p, root):
    return p == root or p.startswith(root.rstrip("/") + "/")


def valid(key, value):
    """A config entry of the right shape. Paths are repo-relative and never climb out of the repo."""
    if key == "localePairs":
        return isinstance(value, list) and len(value) > 1 and all(valid("generatedPaths", v) for v in value)
    if not isinstance(value, str) or not value.strip():
        return False
    if key == "dbWriteGuard.toolPattern":
        try:
            re.compile(value)
        except re.error:
            return False
    if key in ("generatedPaths", "migrationsDirs", "protectedPaths", "localePairs"):
        return not value.startswith("/") and ".." not in value.split("/")
    return True


def load_config(root):
    """.claude/agent-config.json over the defaults, and a warning when part of it cannot be used.
    A key the file leaves out keeps its default; an unusable file or key falls back to the default."""
    cfg = {k: dict(v) if isinstance(v, dict) else list(v) for k, v in DEFAULTS.items()}
    try:
        with open(os.path.join(root, ".claude", "agent-config.json"), encoding="utf-8") as fh:
            user = json.load(fh)
    except FileNotFoundError:
        return cfg, ""
    except (OSError, ValueError):
        return cfg, ".claude/agent-config.json is not valid JSON, so the hooks use their defaults."
    if not isinstance(user, dict):
        return cfg, ".claude/agent-config.json is not a JSON object, so the hooks use their defaults."
    bad = []
    for key in DEFAULTS:
        if key in user:
            value = user[key]
            if isinstance(DEFAULTS[key], dict):
                # An object key (dbWriteGuard): each known field replaces its default; // is a note.
                fields = {k: v for k, v in value.items() if not k.startswith("//")} if isinstance(value, dict) else None
                if fields is not None and all(k in DEFAULTS[key] and valid(key + "." + k, v) for k, v in fields.items()):
                    cfg[key].update(fields)
                else:
                    bad.append(key)
            elif isinstance(value, list) and all(valid(key, v) for v in value):
                cfg[key] = value
            else:
                bad.append(key)
    note = ""
    if bad:
        note = ".claude/agent-config.json: " + ", ".join(bad) + " malformed, so the hooks use the default."
    return cfg, note


def workspace_root():
    """The opt-in multi-repo root, or "" (the default: this repo stands alone)."""
    w = os.path.expanduser(os.environ.get("AGENT_WORKSPACE_ROOT", "").strip())
    return os.path.realpath(w) if w and os.path.isdir(w) else ""


def workspace_repos(ws):
    """Every git repo in the workspace, up to two folders below it (a .git folder, or a .git file
    for a worktree)."""
    found = [ws] if os.path.exists(os.path.join(ws, ".git")) else []
    for pattern in ("*", "*/*"):
        found += [os.path.dirname(g) for g in glob.glob(os.path.join(ws, pattern, ".git"))]
    return [os.path.realpath(r) for r in found]


def git_top(d):
    r = subprocess.run(["git", "-C", d, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else ""


# The user's unlocks (docs/unlock.md): scripts/ops/unlock.sh writes .claude/state/unlock/<target>
# holding the time the unlock ends. scripts/env/envfile.py and unlock.sh read it by the same rules.
UNLOCK_LONGEST = 240 * 60


def unlock_until(root, target):
    """The epoch the user's unlock of target (env or db) ends at, or 0 while it is locked. Only a
    token unlock.sh could have written counts: one number in a plain file with one link, private
    to this user and untracked by git, in a private folder that is not a link, ending in the future
    and no later than the longest unlock allows from when the file was written."""
    uid = os.geteuid()
    folder = os.path.join(root, ".claude", "state", "unlock")
    try:
        for d in (os.path.dirname(folder), folder):
            info = os.lstat(d)
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != uid:
                return 0
        if info.st_mode & 0o077:
            return 0
        fd = os.open(os.path.join(folder, target), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            info = os.fstat(fd)
            text = os.read(fd, 64)
        finally:
            os.close(fd)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != uid or info.st_mode & 0o077 or info.st_nlink != 1
                or not re.fullmatch(rb"[0-9]{1,12}\n?", text)):
            return 0
        until, now = int(text), time.time()
        if until <= now or until > now + UNLOCK_LONGEST + 60 or until > info.st_mtime + UNLOCK_LONGEST + 60:
            return 0
    except (OSError, ValueError):
        return 0
    tracked = subprocess.run(["git", "-C", root, "ls-files", "--", os.path.join(folder, target)],
                             capture_output=True, text=True)
    return 0 if tracked.returncode == 0 and tracked.stdout.strip() else until


def unlock_hint(root, target):
    """What the user types to unlock target here: the package.json alias, run by the package
    manager the lockfile names, when the repo has the alias; the script itself otherwise."""
    try:
        with open(os.path.join(root, "package.json"), encoding="utf-8") as fh:
            scripts = json.load(fh).get("scripts") or {}
    except (OSError, ValueError, AttributeError):
        scripts = {}
    if isinstance(scripts, dict) and "unlock" in scripts:
        for lock, run in (("bun.lock", "bun unlock"), ("bun.lockb", "bun unlock"), ("pnpm-lock.yaml", "pnpm unlock"),
                          ("yarn.lock", "yarn unlock")):
            if os.path.exists(os.path.join(root, lock)):
                return f"! {run} {target}"
        return f"! npm run unlock {target}"
    return f"! ./scripts/ops/unlock.sh {target}"
PY

# One key of .claude/agent-config.json (or its default), one item per line; an item that is itself a
# list (localePairs) prints tab-separated. python3 first, jq second; status 1 when neither could
# read it, so a guard can refuse instead of guarding nothing.
hook_config() {
  if command -v python3 &>/dev/null; then
    HOOK_DEFAULTS="$HOOK_DEFAULTS" hook_py -c "$HOOK_PY_PRELUDE"'
cfg, _ = load_config(sys.argv[1])
for item in cfg.get(sys.argv[2], []):
    print("\t".join(item) if isinstance(item, list) else item)' "$ROOT" "$1" 2>/dev/null && return 0
  fi
  command -v jq &>/dev/null || return 1
  # shellcheck disable=SC2016 # $k and $d are jq variables
  local filter='(if type == "object" and has($k) and (.[$k] | type) == "array" then .[$k] else $d[$k] end)
    | .[]? | if type == "array" then join("\t") else . end'
  if [[ -f "$ROOT/.claude/agent-config.json" ]] &&
    jq -r --arg k "$1" --argjson d "$HOOK_DEFAULTS" "$filter" "$ROOT/.claude/agent-config.json" 2>/dev/null; then
    return 0
  fi
  jq -rn --arg k "$1" --argjson d "$HOOK_DEFAULTS" '$d[$k][]? | if type == "array" then join("\t") else . end'
}

# Serena's replace_in_files edits every file under relative_path (a file, a folder, or nothing for
# the whole project) that paths_include_glob admits, paths_exclude_glob does not, git does not
# ignore (Serena skips ignored files and refuses an ignored relative_path), and the needle matches.
# 0 when such a call, not a dry run, reaches an existing file under one of $@: paths relative to a
# repo, looked up in this repo, or in every repo of the workspace when the session is opened at its
# root (workspace mode only).
read -r -d '' HOOK_SCOPE_PY <<'PY'
root, guarded = os.path.realpath(sys.argv[1]), [g.strip("/") for g in sys.argv[2:] if g.strip("/")]
ws = workspace_root()
repos = workspace_repos(ws) if ws and root == ws and git_top(root) != root else [root]
rel, inc, exc = (os.environ.get(k, "").strip() for k in ("SCOPE_REL", "SCOPE_INC", "SCOPE_EXC"))
# $( ) drops a needle's trailing newlines, which only widens what it matches.
needle, mode = os.environ.get("SCOPE_NEEDLE", ""), os.environ.get("SCOPE_MODE", "")


def pattern(g, loose):
    """A glob as a regex. loose: `*` crosses folders too, so an include glob is read as widely as
    it could be meant; an exclude glob is read narrowly, so it never hides more than it says."""
    out, i = [], 0
    while i < len(g):
        if g.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif g.startswith("**", i):
            out.append(".*")
            i += 2
        else:
            c = g[i]
            out.append(".*" if c == "*" and loose else "[^/]*" if c == "*" else "[^/]" if c == "?" else re.escape(c))
            i += 1
    return re.compile("".join(out) + r"\Z")


def names(path):
    """The spellings a glob may be matched against: from the repo, from the workspace, and from
    the relative_path the call names."""
    yield os.path.relpath(path, repo)
    if ws:
        yield os.path.relpath(path, ws)
    if scope and os.path.isdir(scope):
        yield os.path.relpath(path, scope)


def ignored(path):
    return subprocess.run(["git", "-C", repo, "check-ignore", "-q", "--", path]).returncode == 0


def matches(path):
    """Whether the needle is in the file, read as Serena reads it (Python re, DOTALL and MULTILINE,
    in regex mode). An unreadable file or a needle Python cannot compile counts as a match."""
    if not needle:
        return True
    try:
        with open(path, encoding="utf-8", errors="surrogateescape") as fh:
            text = fh.read()
        return bool(re.search(needle, text, re.S | re.M)) if mode == "regex" else needle in text
    except (OSError, re.error):
        return True


for repo in repos:
    # relative_path against this repo, or, in workspace mode, against the workspace root with the
    # repo's folder as its prefix.
    scope = ""
    if rel:
        own = os.path.relpath(repo, ws) + "/" if ws and inside(repo, ws) and repo != ws else None
        scope = os.path.join(repo, rel[len(own):]) if own and (rel + "/").startswith(own) else os.path.join(repo, rel)
        if not os.path.exists(scope) and ws and root == ws:
            scope = os.path.join(ws, rel)
        scope = os.path.realpath(scope)
    for g in guarded:
        base = os.path.join(repo, g)
        files = [base] if os.path.isfile(base) else [os.path.join(d, f) for d, _, fs in os.walk(base) for f in fs]
        for f in files:
            if scope and not inside(f, scope):
                continue
            if inc and not any(pattern(inc, True).match(n) for n in names(f)):
                continue
            if exc and any(pattern(exc, False).match(n) for n in names(f)):
                continue
            if ignored(f) or not matches(f):
                continue
            print("HIT")
            sys.exit(0)
print("MISS")
PY

# Fails closed: without python3, or when the check does not answer within 5 s, the guard refuses.
hook_scope_hits() {
  local verdict rel inc exc needle mode
  [[ "$(hook_field .tool_name)" == mcp__serena__replace_in_files ]] || return 1
  [[ "$(hook_field .tool_input.dry_run)" != true ]] || return 1
  [[ $# -gt 0 ]] || return 1
  command -v python3 &>/dev/null ||
    hook_fail "Serena's replace_in_files is checked by python3, which is not installed."
  # The fields first: the cap below is what is left of the deadline once they are read.
  rel="$(hook_field .tool_input.relative_path)"
  inc="$(hook_field .tool_input.paths_include_glob)"
  exc="$(hook_field .tool_input.paths_exclude_glob)"
  needle="$(hook_field .tool_input.needle)"
  mode="$(hook_field .tool_input.mode)"
  verdict="$(SCOPE_REL="$rel" SCOPE_INC="$inc" SCOPE_EXC="$exc" SCOPE_NEEDLE="$needle" SCOPE_MODE="$mode" \
    HOOK_DEFAULTS="$HOOK_DEFAULTS" run_capped "$(hook_cap 5)" python3 -c "$HOOK_PY_PRELUDE"$'\n'"$HOOK_SCOPE_PY" "$ROOT" "$@" 2>/dev/null)"
  case "$verdict" in
  HIT) return 0 ;;
  MISS) return 1 ;;
  esac
  hook_fail "the check of which files this replace_in_files reaches did not finish (python3 failed or took over 5 s)."
}

# Workspace mode only: a session opened at the workspace root has no repo of its own, so a file hook
# follows the repo the file lives in and re-anchors ROOT there.
hook_adopt_repo() {
  local dir top
  [[ -n "$WORKSPACE" ]] || return 0
  [[ "$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" == "$ROOT" ]] && return 0
  dir="$(dirname "$1")"
  while [[ ! -d "$dir" && "$dir" == /* && "$dir" != / ]]; do dir="$(dirname "$dir")"; done
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 0
  top="$(hook_physical "$top")"
  if [[ -n "$top" && "$top" == "$WORKSPACE"/* ]]; then
    ROOT="$top"
    cd "$ROOT" || exit 0
  fi
  return 0
}

# A file outside this repo follows its own repo's rules, not this one's.
in_project() {
  [[ "$1" == "$ROOT"/* ]]
}

# Exit 2 is the only code that stops a PreToolUse call; stderr is the reason Claude reads.
block() {
  printf '%s\n' "$@" >&2
  exit 2
}

# Context for Claude without blocking: PostToolUse by default, PreToolUse when named. Plain stdout
# from these events only reaches the debug log.
report() {
  local event="${2:-PostToolUse}"
  [[ -n "$1" ]] || return 0
  if command -v jq &>/dev/null; then
    jq -cn --arg ctx "$1" --arg ev "$event" '{hookSpecificOutput: {hookEventName: $ev, additionalContext: $ctx}}'
  else
    hook_py -c 'import json, sys; print(json.dumps({"hookSpecificOutput": {"hookEventName": sys.argv[2], "additionalContext": sys.argv[1]}}))' "$1" "$event"
  fi
}

# Project tools live in node_modules/.bin or .venv/bin, which a hook's PATH never includes.
# No fallback to a package runner (bunx, npx, uvx): a hook must not download and run an unpinned
# package.
resolve_tool() {
  local tool="$1"
  if [[ -x "node_modules/.bin/$tool" ]]; then
    printf '%s' "node_modules/.bin/$tool"
  elif [[ -x ".venv/bin/$tool" ]]; then
    printf '%s' ".venv/bin/$tool"
  elif command -v "$tool" &>/dev/null; then
    printf '%s' "$tool"
  else
    return 1
  fi
}

# Runs "$@" for at most $1 seconds and returns its status (124 or 143 when it was stopped). macOS
# ships no `timeout`, so there a background timer stops the command instead: a guard still running
# when Claude Code's own hook timeout fires would let the call through. A cap of 0 (a guard past its
# deadline) runs nothing and returns 124; `timeout 0` would mean no limit at all.
run_capped() {
  local secs="$1" to pid dog rc
  shift
  [[ "$secs" =~ ^[0-9]+$ && "$secs" -gt 0 ]] || return 124
  to="$(command -v timeout || command -v gtimeout || true)"
  if [[ -n "$to" ]]; then
    "$to" "$secs" "$@"
    return
  fi
  # An explicit <&0 keeps stdin: a background command otherwise reads /dev/null.
  "$@" <&0 &
  pid=$!
  (
    trap 'kill "$s" 2>/dev/null; exit 0' TERM
    sleep "$secs" &
    s=$!
    wait "$s" && kill -TERM "$pid" 2>/dev/null
  ) </dev/null >/dev/null 2>&1 &
  dog=$!
  wait "$pid" 2>/dev/null
  rc=$?
  kill -TERM "$dog" 2>/dev/null
  wait "$dog" 2>/dev/null
  return "$rc"
}

# The hooks' per-session state: <dir>/<session_id>/heads holds the HEAD each commit command started
# from, which post-commit.sh reads; prompt-intent.sh prunes sessions idle for two days. As a plugin,
# the state lives in the plugin's data folder, never under the plugin itself.
hook_state_dir() {
  if [[ -n "${AGENT_HOOK_STATE_DIR:-}" ]]; then
    printf '%s' "$AGENT_HOOK_STATE_DIR"
  elif [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
    printf '%s' "$CLAUDE_PLUGIN_DATA/hook-state"
  else
    printf '%s' "${TMPDIR:-/tmp}/claude-hook-state"
  fi
}

# Tokenises a shell command the way a shell would and applies the safety rules to each simple
# command. Quoted text stays one word; $( ) bodies, `bash -c` payloads and heredocs fed to a shell
# are read as commands; a heredoc fed to anything else is data. Prints BLOCK<TAB>reason and
# WARN<TAB>text lines, and END when it finished. HOOK_MODE=check also records, under the tool call's
# id, where the HEAD reflog ends in each repo a git commit names; HOOK_MODE=commits then prints
# COMMIT<TAB>dir<TAB>sha<TAB>base<TAB>paths for each commit the command made since that point.
# The command arrives on stdin: an environment variable caps it at the 1 MiB argument limit.
read -r -d '' HOOK_ANALYZER <<'PY'
CMD = sys.stdin.buffer.read().decode("utf-8", "surrogateescape")
ROOT = os.path.realpath(os.environ.get("HOOK_ROOT") or os.getcwd())
SESSION = os.environ.get("HOOK_SESSION", "")
STATE = os.environ.get("HOOK_STATE", "")
TOOL_USE = os.environ.get("HOOK_TOOL_USE_ID", "")
MODE = os.environ.get("HOOK_MODE", "check")
HOME = os.path.realpath(os.path.expanduser("~"))
WORKSPACE = workspace_root()
# The folders whose protected names count: this repo, and the workspace when one is set.
REGIONS = [ROOT] + ([WORKSPACE] if WORKSPACE and WORKSPACE != ROOT else [])
TEMP = [os.path.realpath(p) for p in {"/tmp", "/private/tmp", "/var/folders", os.environ.get("TMPDIR") or "/tmp"}]
if os.environ.get("HOOK_PROBE_NO_TEMP"):
    TEMP = []  # hook-probes.sh: judge a temp fixture as it would be judged anywhere else (stricter only)
out = []
CFG, CFG_NOTE = load_config(ROOT)
if CFG_NOTE:
    out.append(f"WARN\t{CFG_NOTE}")

BRANCHES = [b for b in CFG["protectedBranches"]]
BRANCH_SET = set(BRANCHES)
BRANCH_TEXT = "/".join(BRANCHES) or "none configured"
BRANCH_ALT = "|".join(re.escape(b) for b in BRANCHES) or r"(?!)"
BRANCH_REF = re.compile(r"refs/heads/(?:" + BRANCH_ALT + r")(?:$|[?#])")
PROTECTED = [p.strip("/") for p in CFG["protectedPaths"] if p.strip("/")]
PROTECTED_NAMES = {p for p in PROTECTED if "/" not in p}
PROTECTED_PATHS = [p for p in PROTECTED if "/" in p]
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
WRAPPERS = {"env", "command", "builtin", "exec", "nohup", "time", "sudo", "nice", "caffeinate", "noglob", "nocorrect",
            "timeout", "gtimeout", "stdbuf", "setsid", "doas", "arch", "xcrun", "unbuffer", "chronic", "ionice"}
# The options of each wrapper that take a value; any other option stands alone (`command -p rm`).
WRAPPER_ARGS = {"env": {"-u", "-C", "--unset", "--chdir"}, "sudo": {"-u", "-g", "-p", "-C", "-h", "-U", "-r", "-t", "-D"},
                "nice": {"-n"}, "exec": {"-a"}, "caffeinate": {"-t", "-w"},
                "timeout": {"-s", "--signal", "-k", "--kill-after"}, "gtimeout": {"-s", "--signal", "-k", "--kill-after"},
                "stdbuf": {"-i", "-o", "-e"}, "doas": {"-u", "-C", "-a"}, "arch": {"-arch", "-e", "-d"},
                "xcrun": {"-sdk", "--sdk", "-toolchain", "--toolchain"}, "ionice": {"-c", "-n", "--class", "--classdata"}}
# Wrappers that take positional words before the command: timeout's duration.
WRAPPER_POSITIONAL = {"timeout": 1, "gtimeout": 1}
# rtk, a CLI proxy that trims a command's output for an agent (an RTK hook may add it to any
# command): `rtk git push ...` and `rtk proxy|err|test|summary git push ...` run `git push ...`, and
# its own readers read the files they name, as cat does. Its options stand alone.
RTK_RUNNERS = {"proxy", "err", "test", "summary"}
RTK_READERS = {"read", "smart", "json", "log"}
# commandWrappers from the config: "name [subcommand ...] [-opt= ...]". The wrapper and any of its
# subcommands present are dropped, then its options up to `--`; an option written with a trailing
# `=` takes the next word as its value.
CONFIG_WRAPPERS = {}
for entry in CFG["commandWrappers"]:
    words = entry.split()
    CONFIG_WRAPPERS[os.path.basename(words[0])] = ([w for w in words[1:] if not w.startswith("-")],
                                                   {w[:-1] for w in words[1:] if w.startswith("-") and w.endswith("=")})
KEYWORDS = {"if", "then", "else", "elif", "do", "while", "until", "!", "{", "coproc"}
SEPARATORS = {";", "&&", "||", "|", "&", "|&", ";;", "(", ")", "}"}
REDIRECTS = {">", ">>", "<", ">&", "<&", "&>", "&>>", ">|", "<>", "<<<"}
# Longest first: `)&&` is two operators, not one word, or the command after it is never read.
OPERATORS = sorted(SEPARATORS | REDIRECTS | {"<<"}, key=len, reverse=True)
HEREDOC = re.compile(r"<<(-?)[ \t]*\\?(['\"]?)([A-Za-z_][A-Za-z0-9_.-]*)\2")
# Keywords after which `((` opens arithmetic rather than two subshells.
ARITH_AFTER = {"for", "select", "while", "until", "if", "elif", "then", "else", "do", "!", "{"}
ANSI_C = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", "e": "\x1b", "a": "\a"}
UNQUOTED_END = re.compile(r"[\s;&|()<>'\"\\]")
DOUBLE_END = re.compile(r"[\"\\]")
DOUBLE_PLAIN_END = re.compile(r"[\"\\$`]")
# Folders a repo search never descends into: dependency and build output, large and never a repo.
HEAVY = {"node_modules", ".venv", "venv", ".next", "dist", "build", "target", "__pycache__", ".cache", ".git"}
# Variables an `export` or `declare -x` on this command line hands to every later command.
EXPORTED = {}
# pushd's stack, so popd returns the commands after it to the folder they came from.
DIRSTACK = []
# The repo HEAD before each commit this command makes: {dir: sha, "" when the repo has none}.
HEADS = {}


def skip_heredoc_bodies(text, i, pending):
    for delim, strip in pending:
        while i < len(text):
            j = text.find("\n", i)
            line = text[i:] if j < 0 else text[i:j]
            i = len(text) if j < 0 else j + 1
            if (line.lstrip("\t") if strip else line) == delim:
                break
    return i


def end_of_subst(text, i):
    """Index of the ')' closing a $( whose body starts at i: nested quotes, $( ) and heredocs count.
    One frame per open $( on an explicit stack, so a thousand nested levels cannot overflow."""
    stack, pending, n = [[1, None]], [], len(text)
    while i < n:
        c, frame = text[i], stack[-1]
        if frame[1] == "'":
            frame[1] = None if c == "'" else "'"
            i += 1
            continue
        if c == "\\":
            i += 2
            continue
        if text.startswith("$(", i):
            stack.append([1, None])
            i += 2
            continue
        if frame[1] == '"':
            frame[1] = None if c == '"' else '"'
            i += 1
            continue
        if c in "'\"":
            frame[1] = c
        elif text.startswith("<<", i) and not text.startswith("<<<", i) and HEREDOC.match(text, i):
            m = HEREDOC.match(text, i)
            pending.append((m.group(3), m.group(1) == "-"))
            i = m.end()
            continue
        elif c == "\n" and pending:
            i = skip_heredoc_bodies(text, i + 1, pending)
            pending = []
            continue
        elif c == "(":
            frame[0] += 1
        elif c == ")":
            frame[0] -= 1
            if frame[0] == 0:
                stack.pop()
                if not stack:
                    return i
        i += 1
    return n


def end_of_arith(text, i):
    depth = 2
    while i < len(text) and depth:
        depth += {"(": 1, ")": -1}.get(text[i], 0)
        i += 1
    return i


ANSI_ESCAPE = re.compile(r"x([0-9a-fA-F]{1,2})|u([0-9a-fA-F]{1,4})|U([0-9a-fA-F]{1,8})|([0-7]{1,3})|c(.)", re.S)


def ansi_decode(body):
    """The text of a $'...' body, or of an echo -e / printf argument: every escape decoded."""
    chars, j, n = [], 0, len(body)
    while j < n:
        if body[j] != "\\" or j + 1 >= n:
            chars.append(body[j])
            j += 1
            continue
        m = ANSI_ESCAPE.match(body, j + 1)
        if m is None:
            chars.append(ANSI_C.get(body[j + 1], body[j + 1]))
            j += 2
            continue
        digits = m.group(1) or m.group(2) or m.group(3)
        try:
            chars.append(chr(int(digits, 16)) if digits else chr(int(m.group(4), 8)) if m.group(4)
                         else chr(ord(m.group(5).upper()) ^ 64))
        except ValueError:
            chars.append("?")
        j = m.end()
    return "".join(chars)


def arith_position(buf):
    """Whether `((` here opens arithmetic: at the start of a command or after a keyword like for."""
    prev = "".join(buf).rstrip()
    return not prev or prev[-1] in ";&|(" or re.split(r"[\s;&|()]+", prev)[-1] in ARITH_AFTER


def expansions_in(text):
    """The command bodies of every $( ) and `...` in an unquoted heredoc body: bash runs them even
    though the surrounding text is data (`cat <<EOF` ... `$(cat .env)` ... `EOF`)."""
    found, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if text.startswith("$(", i):
            j = end_of_subst(text, i + 2)
            found.append(text[i + 2:j])
            i = j + 1
            continue
        if c == "`":
            j = i + 1
            while j < n and text[j] != "`":
                j += 2 if text[j] == "\\" else 1
            found.append(text[i + 1:j].replace("\\`", "`"))
            i = j + 1
            continue
        i += 1
    return found


def lex(text, subs):
    """Unquoted newlines become ';', continuations join, heredoc bodies are lifted out, and each
    $( ) body is replaced by a placeholder word and queued in subs to be read as a command."""
    buf, docs, pending, quote, i, n = [], [], [], None, 0, len(text)
    while i < n:
        c = text[i]
        if quote == "'":
            j = text.find("'", i)
            j = n - 1 if j < 0 else j
            buf.append(text[i:j + 1])
            quote = None if text[j] == "'" else quote
            i = j + 1
            continue
        if text.startswith("$((", i):
            # Arithmetic only when it closes on `))`; `$((cmd) | x)` is a substitution whose
            # body opens a subshell, and bash runs it.
            j = end_of_arith(text, i + 3)
            if text[j - 2:j] == "))":
                buf.append("__ARITH__")
                i = j
                continue
        if text.startswith("$(", i):
            j = end_of_subst(text, i + 2)
            subs.append(text[i + 2:j])
            buf.append(f"__SUBST{len(subs) - 1}__")
            i = j + 1
            continue
        if quote == '"':
            if c == "\\":
                # A trailing backslash too: left to the plain-text branch below, it matched itself
                # without moving on and the lexer never returned.
                buf.append(text[i:i + 2])
                i += 2
                continue
            if c == "`":
                # "...`cmd`..." runs cmd like "...$(cmd)...": a markdown code span in a double-quoted
                # message is a command to bash. \` inside it is a literal backtick.
                j = i + 1
                while j < n and text[j] != "`":
                    j += 2 if text[j] == "\\" else 1
                subs.append(text[i + 1:j].replace("\\`", "`"))
                buf.append(f"__SUBST{len(subs) - 1}__")
                i = j + 1
                continue
            if c not in '"$`':
                # Plain text up to the next quote, escape or expansion, in one step.
                m = DOUBLE_PLAIN_END.search(text, i)
                j = n if m is None else m.start()
                buf.append(text[i:j])
                i = j
                continue
            buf.append(c)
            quote = None if c == '"' else quote
            i += 1
            continue
        if text.startswith('$"', i):
            i += 1  # a locale string reads as a double-quoted one
            continue
        if text.startswith("$'", i):
            # ANSI-C quoting: `\'` does not close it. Decoded and re-emitted single-quoted, so the
            # tokenizer sees the word bash sees: $'rm\x20-rf' is `rm -rf`, not a quote left open.
            j = i + 2
            while j < n and text[j] != "'":
                j += 2 if text[j] == "\\" else 1
            buf.append("'" + ansi_decode(text[i + 2:j]).replace("'", "'\"'\"'") + "'")
            i = j + 1
            continue
        if c in "<>" and text.startswith("(", i + 1):
            # Process substitution: <(cmd) and >(cmd) run cmd, like $(cmd).
            j = end_of_subst(text, i + 2)
            subs.append(text[i + 2:j])
            buf.append(f" __SUBST{len(subs) - 1}__ ")
            i = j + 1
            continue
        if c == "\\" and i + 1 < n:
            # An escaped character is literal, like `\(` in `find ... \( -name .git \)`. Quoting is
            # not enough for punctuation, which the tokenizer returns the same quoted or not.
            nxt = text[i + 1]
            if nxt in "()|&;<>{}":
                buf.append(" __ESCAPED__ ")
            elif nxt != "\n":
                buf.append('"\'"' if nxt == "'" else "'" + nxt + "'")
            i += 2
            continue
        if c in "'\"":
            quote = c
            buf.append(c)
            i += 1
            continue
        if c == "#" and (i == 0 or text[i - 1] in " \t\n;&|("):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "`":
            # `cmd` runs cmd and puts its output in its place, like $(cmd): a placeholder word, so a
            # backtick command name or file operand is judged as one built by a substitution.
            j = i + 1
            while j < n and text[j] != "`":
                j += 2 if text[j] == "\\" else 1
            subs.append(text[i + 1:j].replace("\\`", "`"))
            buf.append(f"__SUBST{len(subs) - 1}__")
            i = j + 1
            continue
        if text.startswith("((", i) and arith_position(buf):
            j = end_of_arith(text, i + 2)
            if text[j - 2:j] == "))":
                i = j
                continue
        if text.startswith("<<", i) and not text.startswith("<<<", i):
            m = HEREDOC.match(text, i)
            if m:
                docs.append({"delim": m.group(3), "strip": m.group(1) == "-", "body": "", "quoted": bool(m.group(2))})
                pending.append(len(docs) - 1)
                buf.append(f" __HEREDOC{len(docs) - 1}__ ")
                i = m.end()
                continue
        if c == "\n":
            buf.append(" ; ")
            i += 1
            for idx in pending:
                lines = []
                while i < n:
                    j = text.find("\n", i)
                    line = text[i:] if j < 0 else text[i:j]
                    i = n if j < 0 else j + 1
                    if (line.lstrip("\t") if docs[idx]["strip"] else line) == docs[idx]["delim"]:
                        break
                    lines.append(line)
                docs[idx]["body"] = "\n".join(lines)
                # An unquoted delimiter lets $( ) and `...` in the body run: queue them as commands.
                if not docs[idx]["quoted"]:
                    subs.extend(expansions_in(docs[idx]["body"]))
            pending = []
            continue
        buf.append(c)
        i += 1
    return "".join(buf), docs


def tokens(code):
    """Shell words with their quotes removed, and operators, in one linear pass. shlex copies its
    token on every character, which made a 2 MB argument take half a minute. ValueError when a
    quote is left open, as shlex raised."""
    toks, word, has, i, n = [], [], False, 0, len(code)
    while i < n:
        c = code[i]
        if c.isspace() or c in ";&|()<>":
            if has:
                toks.append("".join(word))
                word, has = [], False
            if c.isspace():
                i += 1
            else:
                op = next(o for o in OPERATORS + list(";&|()<>") if code.startswith(o, i))
                toks.append(op)
                i += len(op)
            continue
        has = True
        if c == "'":
            j = code.find("'", i + 1)
            if j < 0:
                raise ValueError("No closing quotation")
            word.append(code[i + 1:j])
            i = j + 1
        elif c == '"':
            i += 1
            while True:
                m = DOUBLE_END.search(code, i)
                if m is None:
                    raise ValueError("No closing quotation")
                word.append(code[i:m.start()])
                i = m.start()
                if code[i] == '"':
                    i += 1
                    break
                nxt = code[i + 1:i + 2]
                word.append(nxt if nxt in '$`"\\\n' else "\\" + nxt)
                i += 2
        elif c == "\\":
            word.append(code[i + 1:i + 2])
            i += 2
        else:
            m = UNQUOTED_END.search(code, i)
            j = n if m is None else m.start()
            word.append(code[i:j])
            i = j
    if has:
        toks.append("".join(word))
    return toks


def simple_commands(code):
    """[(words, redirects, operator before it)] per simple command. A file descriptor digit joins
    its operator. The operator before tells `echo ... | bash` from `echo ...; bash`."""
    toks = tokens(code)
    cmds, words, redirects, before, k = [], [], [], ";", 0
    while k < len(toks):
        t = toks[k]
        if t.isdigit() and k + 1 < len(toks) and toks[k + 1] in REDIRECTS:
            k += 1
            continue
        if t in REDIRECTS:
            redirects.append((t, toks[k + 1] if k + 1 < len(toks) else ""))
            k += 2
            continue
        if t in SEPARATORS:
            if words or redirects:
                cmds.append((words, redirects, before))
            words, redirects, before = [], [], t
        else:
            words.append(t)
        k += 1
    if words or redirects:
        cmds.append((words, redirects, before))
    return cmds


def split_words(text):
    try:
        return [t for t in tokens(text) if t not in OPERATORS]
    except ValueError:
        return text.split()


def peel(words):
    """(words without the wrappers and assignments before the command, the assignments, whether
    xargs feeds it, the command word as written)."""
    env, ws, xargs = {}, list(words), False
    while ws:
        if ws[0] in KEYWORDS:
            ws.pop(0)
            continue
        if ws[0] == "function":
            del ws[:2]  # `function name { ...; }`: the body follows as its own words
            continue
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", ws[0]):
            k, v = ws.pop(0).split("=", 1)
            env[k] = v
            continue
        head = os.path.basename(ws[0]).lstrip("\\")
        if head in WRAPPERS:
            ws.pop(0)
            takes = WRAPPER_ARGS.get(head, set())
            while ws and ws[0].startswith("-"):
                opt = ws.pop(0)
                if head == "env" and opt.startswith("-S"):
                    # env -S splits one string into the command and its arguments.
                    rest = opt[2:] or (ws.pop(0) if ws else "")
                    ws = split_words(rest) + ws
                elif opt in takes and ws:
                    ws.pop(0)
            if ws and ws[0] == "--":
                ws.pop(0)
            del ws[:WRAPPER_POSITIONAL.get(head, 0)]
            continue
        if head == "rtk":
            ws.pop(0)
            sub = False
            while ws and (ws[0].startswith("-") or (not sub and ws[0] in RTK_RUNNERS)):
                sub = sub or not ws[0].startswith("-")
                if ws.pop(0) == "--":
                    break
            if not sub and ws and ws[0] in RTK_READERS:
                ws[0] = "cat"
            continue
        if head in CONFIG_WRAPPERS:
            subs, takes = CONFIG_WRAPPERS[head]
            ws.pop(0)
            for sub in subs:
                if ws and ws[0] == sub:
                    ws.pop(0)
            while ws and ws[0].startswith("-"):
                opt = ws.pop(0)
                if opt == "--":
                    break
                if opt in takes and ws:
                    ws.pop(0)
            continue
        if head == "xargs":
            ws.pop(0)
            xargs = True
            while ws and ws[0].startswith("-"):
                opt = ws.pop(0)
                if opt in ("-n", "-I", "-P", "-L", "-s", "-d", "-E", "-J") and ws:
                    ws.pop(0)
            continue
        break
    raw = ws[0] if ws else ""
    if ws:
        ws[0] = os.path.basename(ws[0]).lstrip("\\")
    return ws, env, xargs, raw


def block(reason):
    out.append(f"BLOCK\t{reason}")


def in_temp(p):
    return any(inside(p, t) for t in TEMP)


def throwaway(d):
    """A folder under a temp folder and outside this repo and the workspace: a test fixture, not
    the user's work."""
    p = os.path.realpath(d)
    return in_temp(p) and not any(inside(p, r) for r in REGIONS)


def resolve(t, cwd):
    p = t.replace("${HOME}", "~").replace("$HOME", "~")
    p = os.path.expanduser(p)
    p = os.path.normpath(p if os.path.isabs(p) else os.path.join(cwd, p))
    return p if "$" in p else os.path.realpath(p)


def named(rel):
    """Whether a repo-relative path is, holds or lies under a protected name or path."""
    parts = [x for x in rel.split("/") if x not in ("", ".")]
    if any(x in PROTECTED_NAMES for x in parts):
        return True
    joined = "/".join(parts)
    return any(joined == p or joined.startswith(p + "/") or p.startswith(joined + "/") for p in PROTECTED_PATHS)


def holds_repo(p):
    """Whether p is a git repo, or holds one up to two folders below it."""
    if os.path.exists(os.path.join(p, ".git")):
        return True
    if not os.path.isdir(p) or os.path.basename(p) in HEAVY:
        return False
    level = [p]
    for _ in range(2):
        below = []
        for d in level:
            try:
                with os.scandir(d) as entries:
                    for e in entries:
                        if e.name in HEAVY or not e.is_dir(follow_symlinks=False):
                            continue
                        if os.path.exists(os.path.join(e.path, ".git")):
                            return True
                        below.append(e.path)
            except OSError:
                pass
        level = below
    return False


def protected_target(t, cwd):
    p = resolve(t, cwd)
    if "$" in p:
        # An unexpanded variable: judge the literal path.
        return named(t)
    pattern = any(ch in t for ch in "*?[")
    base = os.path.dirname(p) if pattern else p
    if base in ("/", "") or base == HOME or inside(HOME, base) or os.path.dirname(base) == HOME:
        return True
    if any(inside(r, base) for r in REGIONS):
        return True  # this repo, the workspace, or a folder that holds them
    region = next((r for r in REGIONS if inside(base, r)), None)
    if region is None:
        if in_temp(base):
            return False  # a throwaway under a temp folder
        # Outside this repo: another repo, or files some repo tracks, stay protected.
        return holds_repo(base) or tracked_under(base)
    if pattern:
        return True
    if "/.claude/worktrees/" in p + "/" and os.path.dirname(p).endswith(".claude/worktrees"):
        return False
    # A repo (nested, or a workspace sibling) or a folder git tracks files in is protected whatever
    # it is called, not only the names in protectedPaths.
    if (WORKSPACE and any(inside(repo, p) for repo in workspace_repos(WORKSPACE))) or holds_repo(p) or tracked_under(p):
        return True
    return named(os.path.relpath(p, region))


def tracked_under(p):
    top = git_out(existing(p), "rev-parse", "--show-toplevel")
    return bool(top) and bool(git_out(top, "ls-files", "--", p))


def git_out(d, *args):
    r = subprocess.run(["git", "-C", d, *args], capture_output=True, text=True, errors="surrogateescape")
    return r.stdout.strip() if r.returncode == 0 else None


def existing(p):
    while p and p != "/" and not os.path.isdir(p):
        p = os.path.dirname(p)
    return p or "/"


def unresolved(word, glob=False):
    """A word the analyzer could not expand: a $( ) placeholder, a variable, xargs' {}, or, for a
    folder or a message, a glob no shell expanded for it. A pathspec keeps its glob: git reads it."""
    return any(m in word for m in ("__SUBST", "$", "`", "{}")) or (glob and any(c in word for c in "*?["))


def subject(rest):
    """The subject a git commit call's -m gives its reflog entry, whitespace collapsed as git does;
    empty when the message comes from a file, an editor or text the analyzer could not expand."""
    for i, a in enumerate(rest):
        if a == "--":
            break
        if a in ("-m", "--message"):
            value = rest[i + 1] if i + 1 < len(rest) else ""
        elif a.startswith("--message="):
            value = a[len("--message="):]
        elif re.match(r"-[a-zA-Z]*m", a):
            value = a[a.index("m") + 1:] or (rest[i + 1] if i + 1 < len(rest) else "")
        else:
            continue
        line = next((x for x in value.split("\n") if x.strip()), "")
        return "" if unresolved(value, glob=True) else " ".join(line.split())
    return ""


def reflog_path(top):
    return os.path.join(top, git_out(top, "rev-parse", "--git-path", "logs/HEAD") or ".git/logs/HEAD")


def mark(where):
    """PreToolUse's record for a commit in `where`: for the repo holding it, the size of its HEAD
    reflog, the bytes just before that point, and HEAD. A folder that is not a repo's top yet is
    recorded empty, since the command may create the repo it commits in. Bookkeeping, not a rule:
    a failure here records nothing rather than refusing the command."""
    try:
        top = git_out(existing(where), "rev-parse", "--show-toplevel")
        if top and top not in HEADS:
            log = reflog_path(top)
            size = os.path.getsize(log) if os.path.isfile(log) else -1
            tail = b""
            if size > 0:
                with open(log, "rb") as fh:
                    fh.seek(max(0, size - 64))
                    tail = fh.read(size - max(0, size - 64))
            HEADS[top] = f"{size} {tail.hex()} {git_out(top, 'rev-parse', '--verify', '-q', 'HEAD') or ''}"
        if os.path.realpath(where) != top:
            HEADS.setdefault(os.path.realpath(where), "")
    except Exception:
        pass


PROBE_NAME = re.compile(r"zz([-_].*)?|__probe.*|probe([-_].*)?|.*[-_]probe")


def disposable(t, cwd):
    """A throwaway the session made under a protected folder: named like a probe (zz-*, *-probe,
    __probe*) or ignored by git, and holding nothing git tracks. Never under .git or .claude. A
    pattern that matches nothing is the literal path, as with `src/app/[locale]/x-probe`."""
    p = resolve(t, cwd)
    if "$" in p:
        return False
    matches = glob.glob(p) if any(ch in t for ch in "*?[") else []
    return all(disposable_path(m) for m in matches or [p])


def disposable_path(p):
    if {".git", ".claude", ".agents"} & set(p.split("/")):
        return False
    top = git_out(existing(p), "rev-parse", "--show-toplevel")
    if not top or git_out(top, "ls-files", "--", p) != "":
        return False
    if holds_repo(p):
        return False
    if PROBE_NAME.fullmatch(os.path.basename(p.rstrip("/")).split(".")[0]):
        return True
    return subprocess.run(["git", "-C", top, "check-ignore", "-q", p]).returncode == 0


def hooks_same(value, d):
    """Whether core.hooksPath=value names the hooks directory git already uses here."""
    top = git_out(d, "rev-parse", "--show-toplevel")
    if not top or "$" in value:
        return False
    current = git_out(d, "config", "--get", "core.hooksPath")
    used = os.path.join(top, current) if current else os.path.join(d, git_out(d, "rev-parse", "--git-path", "hooks") or ".git/hooks")
    return os.path.realpath(os.path.join(top, value)) == os.path.realpath(used)


VAR_REF = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*|[0-9@*])\}|\$([A-Za-z_][A-Za-z0-9_]*|[0-9@*])")


def expand(word, scope):
    """$NAME and ${NAME} replaced with values this command line assigned, and ~ with a HOME it
    assigned; unknown ones stay."""
    if "HOME" in scope and (word == "~" or word.startswith("~/")):
        word = scope["HOME"] + word[1:]

    def value(m):
        name = m.group(1) or m.group(2)
        return scope[name] if name in scope else m.group(0)
    return VAR_REF.sub(value, word) if "$" in word else word


def branch_of(d):
    r = subprocess.run(["git", "-C", d, "branch", "--show-current"], capture_output=True, text=True)
    return r.stdout.strip()


# Secrets (docs/unlock.md). The shell never opens a real .env* file, since its text would reach the
# transcript: the agent lists one with scripts/env/show.sh, which masks the secrets, and changes one
# with scripts/env/set.sh while the user has unlocked env. Only the user unlocks, so the agent
# never runs scripts/ops/unlock.sh or its package.json alias, and never writes, links, moves or
# deletes anything in .claude/state/unlock/, whatever the route. A script file the agent writes and
# then runs is not read: see "What the lock does not stop" in docs/unlock.md.
TOKENS = os.path.join(ROOT, ".claude", "state", "unlock").lower()
TOKEN_PARENTS = {os.path.dirname(TOKENS), os.path.dirname(os.path.dirname(TOKENS))}


def token_area(p):
    """Whether a lower-cased path is an unlock folder or in one: this repo's, or another checkout's
    (a sibling worktree has its own .claude/state/unlock/ and its own set.sh)."""
    return inside(p, TOKENS) or "/.claude/state/unlock/" in p + "/"


def token_parent(p):
    return p in TOKEN_PARENTS or p.endswith(("/.claude/state", "/.claude"))


ENV_SCRIPTS = {os.path.join(ROOT, "scripts", "env", n): n for n in ("show.sh", "set.sh")}
# scripts/env/ holds the only code the rules trust with a .env* file, so the shell only reads it.
HELPERS = os.path.join(ROOT, "scripts", "env").lower()


def helper_area(p):
    """Whether a lower-cased path is scripts/env/ or in it: this repo's, or another checkout's."""
    return inside(p, HELPERS) or p.endswith("/scripts/env") or "/scripts/env/" in p


# The files that switch the guards on and set what they protect: a .claude folder's settings.json,
# settings.local.json, agent-config.json and agent-config-kit.lock (this repo's, another checkout's,
# the user's own ~/.claude), and, as a plugin, the record of the projects that opted in (HOOK_OPTIN,
# see hook_gate). The shell may read them; any change goes through the Edit tool, which the
# permission rules put in front of the user. A throwaway fixture under a temp folder is not one.
GUARD_NAMES = {"settings.json", "settings.local.json", "agent-config.json", "agent-config-kit.lock"}
OPTIN = os.path.realpath(os.environ["HOOK_OPTIN"]).lower() if os.environ.get("HOOK_OPTIN") else ""
# The same files named in code, a sed script, a patch or a whole command line.
GUARD_TEXT = re.compile(r"agent-config(?:-kit\.lock|\.json)|\.claude\W{0,8}settings(?:\.local)?\.json|opted-in-projects",
                        re.I)


def config_area(p, parents=False):
    """Whether a path is a guard file; with parents, a folder that holds the opt-in record counts."""
    low = p.lower()
    if OPTIN and (low == OPTIN or (parents and inside(OPTIN, low))):
        return True
    name, folder = os.path.basename(low), os.path.basename(os.path.dirname(low))
    return ((folder == ".claude" and name in GUARD_NAMES) or name == "opted-in-projects") and not throwaway(p)


# The guard scripts: the hooks that are running (HOOK_LIB_DIR, the folder lib.sh is in: .claude/hooks
# as a template, the plugin's scripts/ as a plugin), the plugin's own scripts/ and hooks/
# (CLAUDE_PLUGIN_ROOT), any .claude/hooks/ (this repo's, another checkout's, ~/.claude/hooks), the
# plugins Claude Code installed (.claude/plugins/), and scripts/check/hook-probes.*, the probes that
# prove the hooks. scripts/ops/unlock.sh is guarded by the unlock rules above. The shell may read,
# run and copy them; a changed guard stops guarding, so a change goes through the Edit tool or the
# user's `!`. A throwaway fixture under a temp folder is not one, the running hooks aside.
def physical(p):
    return os.path.realpath(p).lower() if p else ""


PLUGIN_ROOT = physical(os.environ.get("CLAUDE_PLUGIN_ROOT", "").strip())
HOOK_HOMES = sorted({h for h in [physical(os.environ.get("HOOK_LIB_DIR", "").strip())]
                     + ([os.path.join(PLUGIN_ROOT, "scripts"), os.path.join(PLUGIN_ROOT, "hooks")] if PLUGIN_ROOT else [])
                     if h and h not in ("/", HOME.lower())})
# The same places named in code, a sed script, a patch or a whole command line.
HOOKS_TEXT = re.compile(r"\.claude\W{0,8}(?:hooks|plugins)(?![\w-])|hook-probes|CLAUDE_PLUGIN_ROOT", re.I)


def hooks_text(text):
    """Whether text names a guard script: by name, spelled in pieces ('.cl' + 'aude/hooks'), or by
    the running hooks' or the plugin's own path."""
    low = text.lower()
    compact = re.sub(r"[\s'\"\\/+,]+", "", low)
    return bool(HOOKS_TEXT.search(text) or re.search(r"\.claude(?:hooks|plugins)|hook-?probes", compact)
                or any(h in low for h in HOOK_HOMES) or (PLUGIN_ROOT and PLUGIN_ROOT in low))


def hooks_area(p, parents=False):
    """Whether a path is a guard script or in a folder of them; with parents, a folder that holds
    one directly (a .claude folder, scripts/check, the plugin's folder) counts too."""
    low = p.lower()
    if any(inside(low, h) for h in HOOK_HOMES) or (parents and PLUGIN_ROOT and low == PLUGIN_ROOT):
        return True
    padded = low.rstrip("/") + "/"
    named = ("/.claude/hooks/" in padded or "/.claude/plugins/" in padded
             or re.search(r"/scripts/check/hook-probes\.[^/]*\Z", low) is not None
             or (parents and padded.endswith(("/.claude/", "/scripts/check/"))))
    return named and not throwaway(p)


def guard_holder(p):
    """The kind of guarded place a folder holds at any depth ("" for none), for a command that would
    carry it along: moving or linking the folder, changing its modes, checking it out."""
    low = p.lower().rstrip("/") or "/"
    places = [("hooks", h) for h in HOOK_HOMES] + [
        ("hooks", os.path.join(ROOT, ".claude", "hooks").lower()), ("hooks", os.path.join(ROOT, "scripts", "check").lower()),
        ("helpers", HELPERS), ("token", TOKENS), ("config", os.path.join(ROOT, ".claude").lower()),
        ("unlock", os.path.join(ROOT, "scripts", "ops").lower())]
    return next((kind for kind, place in places if inside(place, low)), "")


ANCESTOR_OPS = {"mv", "ln", "link", "chmod", "chown", "chgrp", "chflags", "xattr", "setfacl"}
GIT_CHANGERS = {"rm", "mv", "checkout", "restore", "stash"}
# Commands that change the files they are handed.
CHANGERS = {"rm", "unlink", "rmdir", "shred", "mv", "cp", "gcp", "ln", "link", "install", "rsync", "ditto", "chmod",
            "chown", "chgrp", "chflags", "xattr", "setfacl", "truncate", "tee", "dd"}


def carried_along(head, args, wd):
    """The operands a command carries along with everything under them: what mv, ln and link move
    or link (their sources), every operand of chmod and its kin, and the pathspecs of a git command
    that rewrites the working tree (checkout, restore, stash, rm, mv; the index-only forms aside)."""
    if head in ("mv", "ln", "link"):
        return copy_operands(args)[0]
    if head in ANCESTOR_OPS:
        return [a for a in args if not a.startswith("-")]
    if head == "git":
        sub, k = git_sub(args)
        if sub not in GIT_CHANGERS or config_reader(head, args):
            return []
        rest = args[k + 1:]
        return rest[rest.index("--") + 1:] if "--" in rest else [a for a in rest if not a.startswith("-")]
    return []


def changes_files(head, args):
    """Whether a command changes the files it is handed: one of CHANGERS, sed, perl or ruby editing
    in place, or a git command that rewrites paths in the working tree."""
    if head in CHANGERS:
        return True
    if head in SED_NAMES:
        return any(a.startswith("--in-place") or re.fullmatch(r"-[A-Za-z]*[iI].*", a, re.S) for a in args)
    if head in ("perl", "ruby"):
        return any(re.fullmatch(r"-[A-Za-z0-9]*i.*", a, re.S) for a in args if not a.startswith("--"))
    return head == "git" and git_sub(args)[0] in GIT_CHANGERS and not config_reader(head, args)


def xargs_replacements(words):
    """The strings xargs replaces with each input line (-I, -J, -i, --replace), read from its own
    options in the raw words."""
    found = set()
    k = next((k + 1 for k, w in enumerate(words) if os.path.basename(w) == "xargs"), len(words))
    while k < len(words) and words[k].startswith("-"):
        w = words[k]
        if w in ("-I", "-J") and k + 1 < len(words):
            found.add(words[k + 1])
        elif re.fullmatch(r"-[IJ].+", w):
            found.add(w[2:])
        elif w in ("-i", "--replace"):
            found.add("{}")
        elif w.startswith(("--replace=", "-i")):
            found.add(w.split("=", 1)[1] if "=" in w else w[2:])
        k += 2 if w in ("-n", "-I", "-J", "-P", "-L", "-s", "-d", "-E", "-a") else 1
    return found


# Variables this command line set from a $( ) the analyzer could not compute: a path in one is as
# unknown as the substitution itself. mktemp's new path is the one exception.
TAINTED = set()


def near_guard(cwd):
    """The kind of guarded place a folder is in or directly holds, "" for none: code run there can
    reach one by a bare name (`os.remove('settings.json')` in .claude)."""
    low = cwd.lower().rstrip("/")
    kind = landing(cwd) or ("hooks" if hooks_area(cwd, parents=True) else "")
    if kind:
        return kind
    if low.endswith("/.claude/state"):
        return "token"
    if low.endswith("/scripts") and (low == os.path.dirname(HELPERS) or os.path.isdir(os.path.join(cwd, "env"))):
        return "helpers"
    if low.endswith("/scripts/ops") and (low == os.path.join(ROOT, "scripts", "ops").lower()
                                         or os.path.exists(os.path.join(cwd, "unlock.sh"))):
        return "unlock"
    return ""


def config_reader(head, args):
    """Whether a command only reads the guard files it names, beyond the lookers: jq; sed with no
    in-place flag and no script file (a script naming a guard file is refused apart, since its w
    and e commands write and run); and the git forms that change only the index (rm --cached,
    restore --staged)."""
    if head == "jq":
        return True
    if head == "git":
        sub, k = git_sub(args)
        rest = args[k + 1:]
        if sub == "rm":
            return "--cached" in rest
        return sub == "restore" and bool({"-S", "--staged"} & set(rest)) and not {"-W", "--worktree"} & set(rest)
    if head != "sed":
        return False
    for a in args:
        if a == "--":
            break
        # -i and -I take a backup suffix in the same word (-i.bak), -f a file (-fprog.sed).
        if a.startswith(("--in-place", "--file")) or re.fullmatch(r"-[A-Za-z]*[iIf].*", a, re.S):
            return False
    return True


SED_NAMES = {"sed", "gsed"}


def read_script_file(name, fed, cwd):
    """The text of a script file a program is handed (sed -f, awk -f); stdin means what a heredoc
    or here-string feeds it. None when it cannot be read: a name the analyzer cannot resolve, a
    file that is not there yet (a command before it on the line may write it), stdin from elsewhere."""
    if name in STDIN_PATHS:
        return "\n".join(fed) if fed else None
    if unresolved(name) or unresolved(cwd):
        return None
    try:
        with open(resolve(name, cwd), "rb") as fh:
            return fh.read(1 << 20).decode("utf-8", "surrogateescape")
    except OSError:
        return None


def sed_programs(args, fed, cwd):
    """(the programs a sed call may run, strict): the -e values and -f files joined as sed joins
    them, else its first operand. After a bare -i or -I, BSD sed takes the next word as a backup
    suffix and GNU sed takes it as the program, so both next operands are candidates and strict is
    False. None when a -f file cannot be read."""
    exprs, operands, k, bare_i = [], [], 0, None
    while k < len(args):
        a = args[k]
        if a == "--":
            operands += args[k + 1:]
            break
        name, eq, value = a.partition("=")
        if name in ("--expression", "--file"):
            if not eq:
                value, k = (args[k + 1] if k + 1 < len(args) else ""), k + 1
            text = value if name == "--expression" else read_script_file(value, fed, cwd)
            if text is None:
                return None
            exprs.append(text)
        elif a.startswith("-") and len(a) > 1 and not a.startswith("--"):
            j = 1
            while j < len(a):
                ch, rest = a[j], a[j + 1:]
                if ch in "iI":
                    bare_i = None if rest else len(operands)  # the rest of the cluster is a suffix
                    break
                if ch in "ef":
                    if not rest:
                        rest, k = (args[k + 1] if k + 1 < len(args) else ""), k + 1
                    text = rest if ch == "e" else read_script_file(rest, fed, cwd)
                    if text is None:
                        return None
                    exprs.append(text)
                    break
                if ch == "l":
                    if not rest and k + 1 < len(args) and args[k + 1].isdigit():
                        k += 1
                    break
                j += 1
        elif not a.startswith("--"):
            operands.append(a)
        k += 1
    if exprs:
        return ["\n".join(exprs)], True
    if bare_i == 0 and len(operands) > 1:
        return operands[:2], False
    return operands[:1], True


def sed_parse(script):
    """(the files a sed program writes: w, W and the s///w flag; the files it reads: r and R; the
    commands it runs: e and the s///e flag, None standing for the pattern space) or None when it is
    not a program sed would accept. GNU and BSD commands both count."""
    writes, reads, runs, i, n = [], [], [], 0, len(script)

    def line_end(j):
        k = script.find("\n", j)
        return n if k < 0 else k

    def delimited(j, delim):
        """The index after the closing delimiter of a part that starts at j, or None."""
        while j < n:
            if script[j] == "\\":
                j += 2
                continue
            if script[j] == "\n" and delim != "\n":
                return None
            if script[j] == delim:
                return j + 1
            j += 1
        return None

    def address(j):
        """The index after an address at j (j itself when there is none), or None."""
        if j < n and script[j].isdigit():
            while j < n and (script[j].isdigit() or script[j] == "~"):
                j += 1
            return j
        if j < n and script[j] == "$":
            return j + 1
        if j < n and script[j] in "/\\":
            if script[j] == "\\":
                if j + 1 >= n:
                    return None
                j = delimited(j + 2, script[j + 1])
            else:
                j = delimited(j + 1, "/")
            if j is None:
                return None
            while j < n and script[j] in "IM":
                j += 1
        return j

    while i < n:
        c = script[i]
        if c in " \t\n;":
            i += 1
            continue
        if c == "#":
            i = line_end(i)
            continue
        j = address(i)
        if j is None:
            return None
        if j != i:
            k = j
            while k < n and script[k] in " \t":
                k += 1
            if k < n and script[k] == ",":
                k += 1
                while k < n and script[k] in " \t":
                    k += 1
                if k < n and script[k] in "+~":
                    k += 1
                    while k < n and script[k].isdigit():
                        k += 1
                    j = k
                else:
                    j = address(k)
                    if j is None or j == k:
                        return None
        i = j
        while i < n and script[i] in " \t!":
            i += 1
        if i >= n:
            return None
        cmd, i = script[i], i + 1
        if cmd in "{}=dDgGhHnNpPxzF":
            continue
        if cmd in "aic":
            # Text to the end of the line; a line that ends in a backslash goes on.
            while True:
                i = line_end(i)
                if i >= n or script[i - 1] != "\\":
                    break
                i += 1
        elif cmd in ":btT":
            while i < n and script[i] not in "\n;":
                i += 1
        elif cmd in "rRwW":
            end = line_end(i)
            (writes if cmd in "wW" else reads).append(script[i:end].strip())
            i = end
        elif cmd == "e":
            end = line_end(i)
            runs.append(script[i:end].strip() or None)
            i = end
        elif cmd in "sy":
            if i >= n or script[i] in "\n\\":
                return None
            j = delimited(i + 1, script[i])
            j = delimited(j, script[i]) if j is not None else None
            if j is None:
                return None
            i = j
            while cmd == "s" and i < n and script[i] in "gpeiImM0123456789":
                if script[i] == "e":
                    runs.append(None)
                i += 1
            if cmd == "s" and i < n and script[i] == "w":
                end = line_end(i + 1)
                writes.append(script[i + 1:end].strip())
                i = end
        elif cmd in "qQlLv":
            while i < n and script[i] not in "\n;}":
                i += 1
        else:
            return None
    return writes, reads, runs


AWK_NAMES = {"awk", "gawk", "mawk", "nawk"}
AWK_OPERAND = {"nl", ";", "{", "}", "(", ",", "!", "~", "&&", "||", "?", ":", "=", "==", "!=", "<", "<=", ">", ">=",
               "+", "-", "*", "%", "^", "print", "printf", "return", "in"}


def awk_programs(args, cwd):
    """The program texts of an awk call: its -f files and gawk's -e/--source texts, else its first
    operand. None when a program file cannot be read, or gawk is told to include or load code."""
    texts, files, k = [], [], 0
    while k < len(args):
        a = args[k]
        name, eq, value = a.partition("=")
        if a == "--":
            k += 1
            break
        if name in ("--file", "--source", "--include", "--load") or a in ("-f", "-e", "-i", "-l"):
            if not eq and "=" not in a:
                value, k = (args[k + 1] if k + 1 < len(args) else ""), k + 1
            if name in ("--include", "--load") or a in ("-i", "-l"):
                return None
            (files if name == "--file" or a == "-f" else texts).append(value)
        elif a in ("-F", "-v"):
            k += 1
        elif not a.startswith("-") or a == "-":
            break
        k += 1
    for f in files:
        text = read_script_file(f, [], cwd)
        if text is None:
            return None
        texts.append(text)
    if not files and not texts and k < len(args):
        texts.append(args[k])
    return texts


AWK_WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_]*|[0-9.]+(?:[eE][-+]?[0-9]+)?|\|&|>>|&&|\|\||[<>!=]=|\S")


def awk_io(prog):
    """What an awk program reaches besides its input: (files it writes with print or printf > and
    >>, commands it runs with system(), print | and | getline, files it reads with getline <), each
    as the literal string it names, or None for one built at run time; a command comes with whether
    it reads the program's output (print |). None when it cannot be read (a program that pulls in
    other code with @include or @load)."""
    toks, i, n = [], 0, len(prog)
    while i < n:
        c = prog[i]
        if c in " \t\r" or prog.startswith("\\\n", i):
            i += 1 if c in " \t\r" else 2
        elif c == "\n":
            toks.append(("op", "nl"))
            i += 1
        elif c == "#":
            j = prog.find("\n", i)
            i = n if j < 0 else j
        elif c == "@":
            return None
        elif c == '"':
            j = i + 1
            while j < n and prog[j] != '"':
                j += 2 if prog[j] == "\\" else 1
            toks.append(("str", ansi_decode(prog[i + 1:j])))
            i = j + 1
        elif c == "/" and (not toks or toks[-1][0] == "op" and toks[-1][1] in AWK_OPERAND
                           or toks[-1] in (("id", "print"), ("id", "printf"), ("id", "return"), ("id", "in"))):
            j, bracket = i + 1, False
            while j < n and (bracket or prog[j] != "/") and prog[j] != "\n":
                if prog[j] == "\\":
                    j += 1
                elif prog[j] == "[":
                    bracket = True
                elif prog[j] == "]":
                    bracket = False
                j += 1
            toks.append(("re", prog[i:j + 1]))
            i = j + 1
        else:
            word = AWK_WORD.match(prog, i).group(0)
            toks.append(("id" if word[0].isalpha() or word[0] == "_" else "num" if word[0] in "0123456789." else "op",
                         word))
            i += len(word)

    def is_op(k, *words):
        return 0 <= k < len(toks) and toks[k][0] == "op" and toks[k][1] in words

    def literal(a, b):
        """The string toks[a:b] names when it is only string literals (concatenated) in optional
        parentheses, else None."""
        while b - a >= 2 and is_op(a, "(") and is_op(b - 1, ")"):
            a, b = a + 1, b - 1
        part = toks[a:b]
        return "".join(v for _, v in part) if part and all(t == "str" for t, _ in part) else None

    def group_end(j):
        """The index after the parenthesised group that opens at j."""
        depth = 0
        while j < len(toks):
            depth += 1 if is_op(j, "(") else -1 if is_op(j, ")") else 0
            j += 1
            if depth <= 0:
                break
        return j

    def statement_end(j):
        while j < len(toks) and not is_op(j, "nl", ";", "}"):
            j += 1
        return j

    writes, runs, reads = [], [], []
    for k, tok in enumerate(toks):
        if tok in (("id", "print"), ("id", "printf")):
            # The statement runs to a newline, ; or } outside brackets; its first >, >> or | there
            # sends the output to a file or a command.
            j, depth = k + 1, 0
            while j < len(toks) and not (depth == 0 and is_op(j, "nl", ";", "}")):
                depth += 1 if is_op(j, "(", "[") else -1 if is_op(j, ")", "]") else 0
                if depth == 0 and is_op(j, ">", ">>", "|", "|&"):
                    target = literal(j + 1, statement_end(j + 1))
                    (writes.append(target) if is_op(j, ">", ">>") else runs.append((target, True)))
                    break
                j += 1
        elif tok == ("id", "getline"):
            if is_op(k - 1, "|", "|&"):
                # The command is the operand before the pipe: one string, or a parenthesised group.
                j = k - 2
                if is_op(j, ")"):
                    depth = 0
                    while j >= 0:
                        depth += 1 if is_op(j, ")") else -1 if is_op(j, "(") else 0
                        if depth == 0:
                            break
                        j -= 1
                before_is_operand = j > 0 and not (toks[j - 1][0] == "op" and toks[j - 1][1] not in (")", "]"))
                runs.append((None if j < 0 or before_is_operand else literal(j, k - 1), False))
            j = k + 1
            if j < len(toks) and toks[j][0] == "id":
                j += 1
            if is_op(j, "<"):
                reads.append(literal(j + 1, group_end(j + 1) if is_op(j + 1, "(") else j + 2))
        elif tok == ("id", "system") and is_op(k + 1, "("):
            runs.append((literal(k + 1, group_end(k + 1)), False))
    return writes, runs, reads


# Special files a program may write without writing a file.
STD_STREAMS = {"/dev/stdout", "/dev/stderr", "/dev/null", "/dev/fd/1", "/dev/fd/2", "-"}


def judge_write(target, cwd, what):
    """Refuses a file a program writes by name (a sed w, an awk print >) as a redirect to that name
    is refused; a name built at run time is refused as unknown."""
    t = "" if target is None else target.strip()
    if t in STD_STREAMS:
        return
    if not t or any(m in t for m in ("$", "`", "__SUBST")):
        return block(f"[safety] BLOCKED: {what} writes to a file whose name is built at run time, so safety-check "
                     "cannot tell whether it is a .env* file, an unlock file, scripts/env/, a guard file or a guard "
                     "script. Write to a named path; if it is meant, the user runs it with `!`.")
    name = env_named(t, cwd)
    if name:
        return block(env_message(name))
    if token_word(t, cwd, False):
        return block(token_message())
    kind = kit_word(t, cwd, path=True)
    if kind:
        block(kind_message(kind))


def judge_read(source, cwd, what):
    """Refuses a file a program reads by name (a sed r, an awk getline <) when it is a .env* file,
    or when the name is built at run time."""
    t = "" if source is None else source.strip()
    if t in STD_STREAMS or t in ("/dev/stdin", "/dev/fd/0"):
        return
    if not t or any(m in t for m in ("$", "`", "__SUBST")):
        return block(f"[safety] BLOCKED: {what} reads a file whose name is built at run time, so a .env* read "
                     "cannot be ruled out. Read a named file; if it is meant, the user runs it with `!`.")
    name = env_named(t, cwd)
    if name:
        block(env_message(name))


def landing(p):
    """Which guarded place a path is in: "token" (an unlock folder), "helpers" (scripts/env/),
    "config" (a guard file), "hooks" (a guard script), "unlock" (an unlock.sh) or ""."""
    low = p.lower()
    return ("token" if token_area(low) else "helpers" if helper_area(low) else "config" if config_area(p)
            else "hooks" if hooks_area(p) else "unlock" if os.path.basename(low) == "unlock.sh" and not throwaway(p)
            else "")
# A .env* name: .env, .envrc, .env.<anything>. One holding .example is a template, open to all.
ENV_NAME = re.compile(r"\.env(?:rc)?(?:[._-].*)?\Z", re.I | re.S)
# The same name in code or free text, after no word character (process.env and os.environ are not).
ENV_TEXT = re.compile(r"(?<![\w$.])\.env(?:rc)?(?:[._-][\w.*?-]*)?(?!\w)", re.I)
# What a name can start with and still grow into a .env* name: ".", ".e", ".en", ".envr", ".env.x".
ENV_PREFIX = re.compile(r"\.(?:e(?:n(?:v(?:r(?:c(?:[._-].*)?)?|[._-].*)?)?)?)?\Z", re.I | re.S)
# Commands that look at a name, never at the text behind it; the token folder may also be read.
NAME_ONLY = {"ls", "stat", "test", "[", "[[", "file", "wc", "du", "echo", "printf", "realpath", "readlink",
             "basename", "dirname", "true", "false", ":", "which", "type"}
TOKEN_READERS = NAME_ONLY | {"cat", "head", "tail", "less", "more", "grep", "egrep", "fgrep", "rg"}
# Commands that act on a named folder itself, so naming .claude or .claude/state counts too.
PARENT_OPS = {"mv", "rm", "rmdir", "unlink", "ln", "link", "chmod", "chown", "chflags", "xattr", "setfacl", "find"}
COPIERS = {"cp", "mv", "rsync", "ditto", "install", "ln", "link", "gcp"}
GIT_NAME_ONLY = {"status", "check-ignore", "ls-files"}
GREPS = {"grep", "egrep", "fgrep", "rgrep", "rg"}
GREP_VALUES = {"-e", "--regexp", "-f", "--file", "-m", "--max-count", "-A", "-B", "-C", "--context",
               "--after-context", "--before-context", "-g", "--glob", "--iglob", "-t", "--type", "-T",
               "--type-not", "--include", "--exclude", "--exclude-dir", "-d", "--directories", "-D", "--devices",
               "--label", "-j", "--threads", "-M", "--max-columns"}
FIND_ACTIONS = {"-exec", "-execdir", "-ok", "-okdir", "-delete", "-fprint", "-fprint0", "-fprintf", "-fls"}
INTERPRETER = re.compile(r"(?:python|pypy)[0-9.]*|node(?:js)?|bun|deno|tsx|ts-node|ruby|perl|php|lua|osascript"
                         r"|Rscript|[gmn]?awk")
CODE_FLAGS = {"-c", "-e", "-E", "--eval", "-p", "--print", "-r", "eval"}
PACKAGE_MANAGERS = {"bun", "npm", "pnpm", "yarn"}
PM_RUN = {"run", "run-script", "rum", "urn"}
# Package-runner subcommands that run a command Claude names, and the flags that carry it as one
# string (like `bash -c`): the string is unwrapped and checked, so `npm exec -c '<cmd>'` is read.
PM_EXEC = {"exec", "dlx", "x"}
PM_RUNNERS = {"npx", "bunx", "pnpx"}
PM_CALL_FLAGS = {"-c", "--call", "--shell-mode"}
# The options of those exec forms that take a value, so the command after them is found.
PM_EXEC_VALUES = {"-p", "--package", "--filter", "-F", "-w", "--workspace", "--resume-from", "--allow-build",
                  "--cwd", "-C", "--dir", "--prefix", "--config", "--registry", "--cache", "--userconfig"}
# Words that make a single word shell code rather than a program name.
SHELL_TEXT = re.compile(r"[\s;&|<>()$`\\*?]")
# Commands that read a file's contents (not just its name): a substitution or an operand the
# analyzer cannot resolve as their file argument is refused, since what they would open is unknown.
CONTENT_READERS = {"cat", "head", "tail", "less", "more", "nl", "tac", "strings", "xxd", "od", "hexdump",
                   "hd", "base64", "base32", "basenc", "rev", "fold", "expand", "unexpand", "cut", "tr",
                   "fmt", "col", "column", "pr", "split", "csplit", "sed", "awk", "gawk", "mawk", "nawk",
                   "grep", "egrep", "fgrep", "rg", "sort", "uniq", "wc", "cmp", "diff", "tee", "dd"}
# Content readers whose every non-option operand is a file it opens and prints: a substitution or
# an unresolved operand there could be a .env* read, so it is refused (the git-listing case aside).
FILE_OPERAND_READERS = {"cat", "head", "tail", "less", "more", "tac", "strings", "xxd", "od",
                        "hexdump", "hd", "base64", "base32", "basenc", "rev", "fold"}
# Decoders whose output the analyzer cannot read; feeding it to a shell, interpreter, eval or a file
# command runs or opens something unknown, so that pipeline is refused.
DECODERS = {"base64", "base32", "base16", "basenc", "xxd", "uudecode", "openssl"}
DECODE_FLAGS = {"-d", "-D", "--decode", "-r"}
# Inline interpreter code that opens or lists files, or builds a path: it must go through the env
# helpers, so such a -c/-e payload is refused (the file it reaches cannot be resolved from text).
INLINE_FILE = re.compile(
    r"\bopen\s*\(|\bfopen\b|glob\.glob|iglob|os\.listdir|os\.scandir|os\.walk|\bpathlib\b|\bPath\s*\(|"
    r"\.read_text|\.read_bytes|readFileSync|readFile\b|createReadStream|require\(\s*['\"](?:fs|node:fs)|"
    r"\bimport\b[^\n;]*\bfs\b|File\.(?:read|open)|IO\.read|\bopen\b\s*FH|\bslurp\b|\.readlines\b|\.readline\b",
    re.I)
# Inline code that changes, moves or deletes a file, or runs a command (python, node, bun, deno,
# perl, ruby, php, lua, R, osascript): refused wherever it runs, since the file it reaches cannot be
# read from its text (a name built in pieces, relative to a folder it picks, handed to a shell).
INLINE_CHANGE = re.compile(
    r"\bos\.(?:remove|unlink|rename|renames|replace|rmdir|removedirs|l?chmod|l?chown|chflags|symlink|link|truncate|"
    r"utime|system|popen|exec\w*|spawn\w*|posix_spawn\w*|execute)\b|\bshutil\.|\bsubprocess\b|\bpty\.spawn|"
    r"child_process|\b(?:execSync|execFileSync|spawnSync|writeFile\w*|appendFile\w*|copyFile\w*|rmSync|unlinkSync)\b|"
    r"\bBun\.(?:write|file|spawn\w*|\$)|\bDeno\.\w+|\bFileUtils\b|\bFile\.(?:write|delete|rename|unlink|chmod|symlink)|"
    r"(?<![.\w$])(?:system|exec|unlink|rename|chmod|chown|symlink|truncate|qx|shell_exec|passthru|proc_open|popen)"
    r"\s*[(\"'`{$@]|"
    r"%x[({\[]|\bIO\.popen\b|\bKernel\.|\bio\.(?:open|popen|output)\b|\bfile_put_contents\b|\bdo shell script\b",
    re.I)
# Global glob state: shopt -s dotglob makes a glob match dot files (.env* included).
DOTGLOB = [False]
# The current $( ) / `...` bodies, so a simple command can read what its substitution operand runs.
CUR_SUBS = [[]]
NPM_SCRIPTS = {"test": "test", "t": "test", "tst": "test", "start": "start", "stop": "stop", "restart": "restart"}
PM_VALUES = {"--cwd", "-C", "--dir", "--prefix", "--filter", "-F", "--workspace", "--config"}
# Commands that may name unlock.sh or scripts/env/: they read the file. Anything else, a wrapper
# such as timeout or npm exec included, is refused.
LOOKERS = TOKEN_READERS | {"shellcheck", "diff", "cmp", "md5", "md5sum", "shasum", "sha1sum", "sha256sum", "nl"}
GIT_LOOKS = {"add", "diff", "log", "show", "status", "blame", "ls-files", "check-ignore", "grep", "commit"}
# Inline code that reaches the values a loader took from a .env* file.
ENV_ACCESS = re.compile(r"process\.env|Bun\.env|import\.meta\.env|Deno\.env|os\.environ|getenv|ENV\[|\$ENV\{", re.I)
ENV_LOADER_CODE = re.compile(r"dotenv|load_dotenv|env_file|--env-file", re.I)
# Tools that print what a .env* file holds without being handed its name.
ENV_PRINTERS = {"dotenv": {"get", "list"}, "dotenvx": {"get", "decrypt"}}
# Git settings and environment variables whose value git (or a pager-using tool) runs as a shell
# command: the value is checked as the command it is, like a `!` alias.
GIT_COMMAND_KEY = re.compile(
    r"core\.(?:pager|editor|fsmonitor|sshcommand|gitproxy|askpass)|pager\..+|sequence\.editor"
    r"|credential\.(?:.+\.)?helper|diff\.external|diff\..+\.(?:command|textconv)|merge\..+\.driver"
    r"|filter\..+\.(?:clean|smudge|process)|(?:diff|merge)tool\..+\.(?:cmd|path)|gpg\.(?:.+\.)?program"
    r"|sendemail\..*(?:cmd|sendmail\w*)|uploadpack\.packobjectshook|remote\..+\.(?:receivepack|uploadpack)"
    r"|web\.browser|(?:browser|man)\..+\.(?:cmd|path)|interactive\.difffilter|hook\..+\.command", re.I)
# Git settings that change what git runs, which config it loads, where it connects or where it
# works: an alias or an included file runs commands this check never reads. Set for one call (-c,
# --config-env, GIT_CONFIG_PARAMETERS, GIT_CONFIG_KEY_n) or written with `git config`, each of these
# and each command-carrying key above is refused whatever its value (fail-closed). Allowed: a pager
# or editor that is a plain viewer, core.fsmonitor switched off, and core.hooksPath, which the
# pre-commit gate rule judges. Plain settings (user.*, color.*, core.quotepath, ...) stay allowed.
GIT_BEHAVIOUR_KEY = re.compile(
    r"alias\..+|include\.path|includeif\..+\.path|core\.worktree|init\.templatedir|safe\.directory"
    r"|protocol\.(?:.+\.)?allow|https?\.(?:.+\.)?(?:proxy|sslverify|extraheader)|url\..+\.(?:push)?insteadof"
    r"|submodule\..+\.update", re.I)
GIT_VIEWER_KEY = re.compile(r"core\.(?:pager|editor)|pager\..+|sequence\.editor", re.I)
GIT_VIEWER = re.compile(r"(?:less|more|cat|true|false|:)(?:\s+-[A-Za-z]+)*", re.I)
GIT_SETTING = ("[safety] BLOCKED: this git call sets {key}, a setting that changes what git runs, which config "
               "it loads, where it connects or where it works (an alias, an include, an ssh, proxy, credential, "
               "protocol or hook command, a pager or editor command, ...). safety-check does not follow it, so it "
               "is refused. Drop the setting; plain ones (user.*, color.*) stay allowed. If it is meant, the user "
               "runs it with `!`.")
COMMAND_VARS = {"GIT_PAGER", "PAGER", "MANPAGER", "PSQL_PAGER", "GIT_EDITOR", "EDITOR", "VISUAL",
                "GIT_SEQUENCE_EDITOR", "GIT_SSH_COMMAND", "GIT_SSH", "GIT_ASKPASS", "SSH_ASKPASS",
                "GIT_PROXY_COMMAND", "GIT_EXTERNAL_DIFF", "LESSOPEN", "LESSCLOSE"}
CARRIER_UNKNOWN = ("[safety] BLOCKED: this sets a git setting or variable that git runs as a command (a pager, "
                   "editor, fsmonitor, ssh or diff command, ...) to a value safety-check cannot read, so what it "
                   "would run (a .env* read or an unlock included) is unknown. Give it a literal value; if it is "
                   "meant, the user runs it with `!`.")

STDIN_CODE = ("[safety] BLOCKED: a shell or interpreter here runs code it reads from stdin, from a command or "
              "substitution whose output safety-check cannot read, so what runs (a .env* read or an unlock "
              "included) is unknown. Save the code to a named file, look at it, then run that file; if it is "
              "meant, the user runs it with `!`.")
INTERP_VALUE_FLAGS = {"-W", "-X", "-r", "--require", "-I", "-M", "--import", "--loader", "-C", "--input-type", "-Q"}


STDIN_PATHS = ("-", "/dev/stdin", "/dev/fd/0", "/proc/self/fd/0")


def code_from_stdin(ws):
    """Whether a shell, source or interpreter with these words takes its code from stdin: no -c/-e
    payload, no -m module, and no script operand (or one of STDIN_PATHS)."""
    name, args = ws[0], ws[1:]
    if name in SHELLS or name in ("source", "."):
        return (name in SHELLS and reads_stdin(args)) or script_operand(ws) in STDIN_PATHS
    if not INTERPRETER.fullmatch(name) or name in ("bun", "deno", "tsx", "ts-node"):
        return False
    if name.endswith("awk"):
        return any(a == "-f" and args[k + 1:k + 2] in (["-"], ["/dev/stdin"]) for k, a in enumerate(args))
    k = 0
    while k < len(args) and args[k].startswith("-") and args[k] != "-":
        a = args[k]
        if a in CODE_FLAGS or a == "-m" or re.fullmatch(r"-[A-Za-z]*[cemE]", a) or re.fullmatch(r"-[cem].+", a):
            return False
        k += 2 if a in INTERP_VALUE_FLAGS else 1
    return k >= len(args) or args[k] in STDIN_PATHS


def carried_value(value):
    """The command a command-carrying setting's value runs, or None when it cannot be read."""
    value = value.replace("${HOME}", "~").replace("$HOME", "~")
    if unresolved(value):
        return None
    return value.lstrip("|-!").strip()


def git_carriers(args, env):
    """The commands a git call is handed through its settings: -c key=value, --config-env,
    GIT_CONFIG_PARAMETERS / GIT_CONFIG_KEY_n on the line, and `git config [set] key value`.
    None in the list stands for a value that cannot be read."""
    found, k = [], 0
    while k < len(args) and args[k].startswith("-"):
        a = args[k]
        if a == "-c" and k + 1 < len(args):
            key, _, value = args[k + 1].partition("=")
            if GIT_COMMAND_KEY.fullmatch(key):
                found.append(carried_value(value))
        elif a.startswith("--config-env"):
            spec = a.partition("=")[2] if "=" in a else (args[k + 1] if k + 1 < len(args) else "")
            if GIT_COMMAND_KEY.fullmatch(spec.partition("=")[0]):
                found.append(None)
        k += 2 if a in ("-c", "-C", "--config-env") else 1
    for name, value in env.items():
        if name == "GIT_CONFIG_PARAMETERS" and GIT_COMMAND_KEY.search(value.replace("'", " ")):
            found.append(None)
        m = re.fullmatch(r"GIT_CONFIG_KEY_([0-9]+)", name)
        if m and GIT_COMMAND_KEY.fullmatch(value):
            found.append(carried_value(env.get("GIT_CONFIG_VALUE_" + m.group(1), "")))
    rest = args[k + 1:] if k < len(args) and args[k] == "config" else []
    words, j = [], 0
    while j < len(rest):
        if rest[j] in ("-f", "--file", "--blob", "--type", "--default", "--comment", "--value"):
            j += 2
            continue
        if not rest[j].startswith("-"):
            words.append(rest[j])
        j += 1
    if words[:1] == ["set"]:
        words = words[1:]
    if len(words) >= 2 and GIT_COMMAND_KEY.fullmatch(words[0]):
        found.append(carried_value(words[1]))
    return found


def git_setting_refused(key, value):
    """Whether git setting key, with value (None when it cannot be read), is refused: see
    GIT_BEHAVIOUR_KEY."""
    k = key.strip().lower()
    if k.startswith("section "):
        return True
    if value is not None and GIT_VIEWER_KEY.fullmatch(k) and GIT_VIEWER.fullmatch(value.strip()):
        return False
    if value is not None and k == "core.fsmonitor" and value.strip().lower() in ("false", "0", "no", "off"):
        return False
    return bool(GIT_BEHAVIOUR_KEY.fullmatch(k) or GIT_COMMAND_KEY.fullmatch(k))


def git_settings(args, env):
    """(key, value) for every setting a git call is handed or writes: -c key=value and
    --config-env before the subcommand, GIT_CONFIG_PARAMETERS and GIT_CONFIG_KEY_n on the line, and
    `git config [set|--add|--replace-all] key value`. value is None when it cannot be read."""
    found, k = [], 0
    while k < len(args) and args[k].startswith("-"):
        a = args[k]
        if a == "-c" and k + 1 < len(args):
            key, _, value = args[k + 1].partition("=")
            found.append((key, None if unresolved(value) else value))
        elif a.startswith("--config-env"):
            spec = a.partition("=")[2] if "=" in a else (args[k + 1] if k + 1 < len(args) else "")
            found.append((spec.partition("=")[0], None))
        k += 2 if a in ("-c", "-C", "--config-env") else 1
    for name, value in env.items():
        if name == "GIT_CONFIG_PARAMETERS":
            found += [(key, None) for key in re.findall(r"'([^'=]+)'", value)] or [("alias.unreadable", None)]
        m = re.fullmatch(r"GIT_CONFIG_KEY_([0-9]+)", name)
        if m:
            value = env.get("GIT_CONFIG_VALUE_" + m.group(1))
            found.append((env[name], None if value is None or unresolved(value) else value))
    if k < len(args) and args[k] == "config":
        rest, words, j = args[k + 1:], [], 0
        reads = any(r in ("--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l", "--unset",
                          "--unset-all", "--remove-section") for r in rest)
        while j < len(rest):
            if rest[j] in ("-f", "--file", "--blob", "--type", "--default", "--comment", "--value"):
                j += 2
                continue
            if not rest[j].startswith("-"):
                words.append(rest[j])
            j += 1
        if "--rename-section" in rest or words[:1] == ["rename-section"]:
            # Renaming a section can turn harmless settings into aliases or commands.
            return found + [("section " + (words[-1] if words else "?"), None)]
        if words[:1] == ["set"]:
            words, reads = words[1:], False
        elif words[:1] in (["get"], ["list"], ["unset"], ["remove-section"]):
            reads = True
        if len(words) >= 2 and not reads:
            found.append((words[0], None if unresolved(words[1]) else words[1]))
    return found
# Set per command line: whether its text names a .env* file, or the unlock script or folder.
MENTIONS = set()


def mentions(text):
    compact = re.sub(r"[\s'\"\\/]+", "", text.lower())
    if "stateunlock" in compact or "unlock.sh" in compact:
        MENTIONS.add("token")
    if GUARD_TEXT.search(text):
        MENTIONS.add("config")
    if hooks_text(text):
        MENTIONS.add("hooks")
    if any(".example" not in m.group(0).lower() for m in ENV_TEXT.finditer(text)):
        MENTIONS.add("env")


def brace_forms(word):
    """A word with its {a,b} lists expanded as bash expands them, at most 32 forms."""
    done, todo = [], [word]
    while todo and len(done) + len(todo) <= 32:
        w = todo.pop()
        m = re.search(r"\{([^{}]*,[^{}]*)\}", w)
        if m is None:
            done.append(w)
        else:
            todo += [w[:m.start()] + part + w[m.end():] for part in m.group(1).split(",")]
    return done + todo


def env_name(base):
    return bool(ENV_NAME.match(base)) and ".example" not in base.lower()


def env_named(word, cwd):
    """The .env* file a word names, or "": a path, the value of --opt=path, @path or rev:path, or a
    glob or brace list that can expand to one, whether or not such a file exists yet: its literal
    start must be able to grow into a .env* name. As in the shell, only a pattern whose last part
    starts with a dot matches a dot file. Anything in .claude/state/env-backups/ counts too."""
    if len(word) > 4096:
        return ""
    for w in brace_forms(word):
        for c in {w, w.split("=", 1)[-1], w.split(":")[-1]}:
            c = c.lstrip("@")
            # set.sh's backups hold the old files whole, whatever their names.
            if not unresolved(cwd) and not re.search(r"\s", c) and "/.claude/state/env-backups" in resolve(c, cwd).lower() + "/":
                return c
            base = c.rstrip("/").rsplit("/", 1)[-1]
            globbing = any(ch in base for ch in "*?[")
            if ".example" in base.lower():
                continue
            # A glob need not start with a dot to match .env* once `shopt -s dotglob` is on.
            if not base.startswith(".") and not (DOTGLOB[0] and globbing):
                continue
            if globbing:
                hits = [base] if ENV_PREFIX.match(re.split(r"[*?\[]", base)[0]) else []
                if not unresolved(c):
                    hits += [os.path.basename(g) for g in glob.glob(os.path.join(cwd, c))
                             if env_name(os.path.basename(g))]
                    if DOTGLOB[0]:
                        # With dotglob a glob whose last part has no leading dot still matches dot
                        # files, so match against the directory's hidden entries too.
                        d = os.path.dirname(os.path.join(cwd, c)) or cwd
                        try:
                            hits += [n for n in os.listdir(d) if env_name(n) and fnmatch.fnmatch(n, base)]
                        except OSError:
                            pass
                if hits:
                    return c
            elif env_name(base):
                return c
    return ""


def script_operand(ws):
    """The word a shell or source runs as its script, as written: None when there is none (it reads
    stdin), "" for bash -c."""
    head, args, k = ws[0], ws[1:], 0
    while head in SHELLS and k < len(args) and args[k].startswith(("-", "+")):
        if SHELL_C.match(args[k]):
            return ""
        k += 2 if args[k] in ("-o", "+o", "-O", "+O") else 1
    return args[k] if k < len(args) else None


def script_run(ws, raw, cwd):
    """The script file a simple command runs, resolved: its own path (./x.sh), or the first operand
    of a shell or of source; "" for anything else, bash -c included."""
    if ws[0] in SHELLS or ws[0] in ("source", "."):
        word = script_operand(ws)
        return resolve(word, cwd) if word and not unresolved(word) else ""
    return resolve(raw, cwd) if "/" in raw and not unresolved(raw) else ""


def kit_word(word, cwd, parents=False, path=False):
    """What a path word names: "unlock" for an unlock.sh (any copy), "helpers" for scripts/env/ or
    a file in it (with parents, scripts/ as well), "config" for a guard file (with parents, a
    folder holding the opt-in record as well), "hooks" for a guard script or its folder (with
    parents, a folder holding one directly), else "". A glob counts by what it can expand to here;
    a word holding a space is text, not a path, unless it starts at / or ~ or path says it is one
    (a redirect's target, a file a sed or awk program writes)."""
    if len(word) > 4096 or "\n" in word or unresolved(cwd):
        return ""
    if re.search(r"\s", word) and not path and not word.startswith(("/", "~/")):
        return ""
    for w in brace_forms(word):
        for c in {w, w.split("=", 1)[-1]}:
            if not c or unresolved(c):
                continue
            paths = [resolve(c, cwd)]
            if any(ch in c for ch in "*?["):
                paths += [os.path.realpath(g) for g in glob.glob(os.path.join(cwd, os.path.expanduser(c)))[:200]]
            for path in paths:
                p = path.lower()
                if os.path.basename(p) == "unlock.sh":
                    return "unlock"
                if helper_area(p) or (parents and p == os.path.dirname(HELPERS)):
                    return "helpers"
                if config_area(path, parents):
                    return "config"
                if hooks_area(path, parents):
                    return "hooks"
    return ""


def unknown_script(ws, xargs):
    """Whether a shell or source runs a script this check cannot name, which could be unlock.sh:
    one named by $( ), a variable it cannot expand or find's {}, or one xargs feeds it. A shell
    given -n only reads the script for syntax."""
    if ws[0] in SHELLS and any(re.fullmatch(r"-[A-Za-z]*n[A-Za-z]*", a) and not SHELL_C.match(a) for a in ws[1:]
                               if a.startswith("-")):
        return False
    word = script_operand(ws)
    if word is None:
        return xargs and ws[0] in SHELLS
    return bool(word) and unresolved(word.rsplit("/", 1)[-1])


def git_sub(args):
    k = 0
    while k < len(args) and args[k].startswith("-"):
        k += 2 if args[k] in ("-C", "-c") else 1
    return (args[k], k) if k < len(args) else ("", k)


def git_cwd(args, cwd):
    """The folder a git call works in: cwd, moved by each -C before its subcommand."""
    k = 0
    while k < len(args) and args[k].startswith("-"):
        if args[k] == "-C" and k + 1 < len(args):
            cwd = resolve(args[k + 1], cwd)
        k += 2 if args[k] in ("-C", "-c") else 1
    return cwd


def pattern_index(head, args):
    """Which of a grep's words is its pattern, text rather than a file: -e's value, or the first
    operand when no -e is given."""
    k, first, skip = 0, None, set()
    while k < len(args):
        a = args[k]
        if a == "--":
            if first is None and k + 1 < len(args) and not skip:
                first = k + 1
            break
        if a in ("-e", "--regexp") and k + 1 < len(args):
            skip.add(k + 1)
            k += 2
            continue
        if a.startswith("-") and len(a) > 1:
            k += 2 if a in GREP_VALUES else 1
            continue
        if first is None:
            first = k
        k += 1
    if not skip and first is not None:
        skip.add(first)
    return skip


def loader_values(head, args):
    """The words a loader hands to its program as an env file rather than reading them out:
    --env-file values, and dotenvx run -f, env-cmd -f and dotenv -e ... -- cmd."""
    skip = set()
    for k, a in enumerate(args):
        if a.startswith("--env-file="):
            skip.add(k)
        elif a == "--env-file":
            skip.add(k + 1)
    if (head == "dotenvx" and "run" in args) or head == "env-cmd" or (head == "dotenv" and "--" in args and "-p" not in args):
        skip |= {k + 1 for k, a in enumerate(args) if a in ("-f", "-e", "--file")}
    return skip


def walk_files(top, limit=5000):
    """Relative paths of the files under top, heavy folders skipped, at most limit of them."""
    found = []
    for d, dirs, files in os.walk(top):
        dirs[:] = [x for x in dirs if x not in HEAVY or x == ".claude"]
        found += [os.path.relpath(os.path.join(d, f), top) for f in files]
        if len(found) >= limit:
            break
    return found


def grep_reads_env(head, args, cwd):
    """The .env* file a recursive grep (or an rg that searches hidden files) would read, or "": a
    search folder that holds one its --exclude, --include or -g globs do not leave out."""
    opts, operands, k, globs = [], [], 0, []
    while k < len(args):
        a = args[k]
        if a == "--":
            operands += args[k + 1:]
            break
        if a.startswith("-") and len(a) > 1:
            name, eq, v = a.partition("=")
            if name in GREP_VALUES and not eq and k + 1 < len(args):
                v, k = args[k + 1], k + 1
            if name in ("--exclude", "--include", "-g", "--glob", "--iglob"):
                globs.append((name, v))
            opts.append(a)
        else:
            operands.append(a)
        k += 1
    if head == "rg":
        hidden = any(o in ("--hidden", "--no-ignore", "--no-ignore-dot") or
                     (re.fullmatch(r"-[A-Za-z.]+", o) and ("." in o or o.count("u") >= 2)) for o in opts)
        if not hidden:
            return ""
        roots = operands[1:] if not any(o in ("-e", "--regexp", "-f", "--file") for o in opts) else operands
    else:
        if head != "rgrep" and not any(o in ("--recursive", "--dereference-recursive") or re.fullmatch(r"-[A-Za-z0-9]*[rR][A-Za-z0-9]*", o) for o in opts):
            return ""
        roots = operands[1:] if not any(o in ("-e", "--regexp", "-f", "--file") or o.startswith(("--regexp=", "--file=")) for o in opts) else operands

    def searched(name):
        for kind, g in globs:
            neg = g.startswith("!")
            hit = fnmatch.fnmatch(name, g.lstrip("!"))
            if kind == "--exclude" and hit or kind in ("-g", "--glob", "--iglob") and neg and hit:
                return False
        includes = [g for kind, g in globs if kind == "--include" or (kind in ("-g", "--glob", "--iglob") and not g.startswith("!"))]
        return not includes or any(fnmatch.fnmatch(name, g) for g in includes)

    for r in roots or ["."]:
        p = resolve(r, cwd)
        if unresolved(r) or not os.path.isdir(p):
            continue
        for rel in walk_files(p):
            name = os.path.basename(rel)
            if env_name(name) and searched(name):
                return os.path.join(r, rel)
    return ""


def code_texts(ws, fed, redirects, prev, before):
    """The code an interpreter in this command runs from its words: a -c or -e payload, awk's
    program, and what reaches its stdin from a heredoc, a here-string or an echo piped in."""
    for i, w in enumerate(ws):
        name = os.path.basename(w)
        if not INTERPRETER.fullmatch(name):
            continue
        rest, texts = ws[i + 1:], []
        if name.endswith("awk"):
            k = 0
            while k < len(rest) and rest[k].startswith("-"):
                k += 2 if rest[k] in ("-F", "-v", "-f") else 1
            texts += rest[k:k + 1]
        for k, a in enumerate(rest):
            if (a in CODE_FLAGS or re.fullmatch(r"-[A-Za-z]*[ce]", a)) and k + 1 < len(rest):
                texts.append(rest[k + 1])
            elif re.fullmatch(r"-[ce].+", a):
                texts.append(a[2:])
        texts += fed + [t for op, t in redirects if op == "<<<"]
        if before in ("|", "|&") and prev:
            pws, _, _, _ = peel(prev)
            if pws and pws[0] in ("echo", "printf"):
                texts.append(ansi_decode(" ".join(a for a in pws[1:] if not re.match(r"^-[neE]+$", a))))
        return texts
    return []


def token_word(word, cwd, parents):
    """Whether a word names the unlock folder or a path in it; with parents, .claude or
    .claude/state as well. A word the analyzer cannot expand counts by its literal folder part."""
    low = word.lower()
    if "state/unlock" in re.sub(r"/+(?:\./+)*", "/", low):
        return True
    if len(word) > 4096 or unresolved(cwd):
        return False
    if unresolved(word):
        # The part after the literal folder is unknown and may be the rest of the path.
        lit = re.split(r"__SUBST|\$|`|\{\}", word)[0]
        if "/" not in lit:
            return False
        word, parents = lit.rsplit("/", 1)[0] or "/", True
    p = resolve(word, cwd).lower()
    return token_area(p) or (parents and token_parent(p))


def copy_operands(args):
    """(the sources, the destination) of cp, mv, rsync and kin: -t's value or the last operand. A
    remote (host:path) is neither; the destination is None when there is no source."""
    operands, target, k = [], None, 0
    while k < len(args):
        a = args[k]
        if a in ("-t", "--target-directory") and k + 1 < len(args):
            target, k = args[k + 1], k + 2
            continue
        if a.startswith("--target-directory="):
            target = a.split("=", 1)[1]
        elif not a.startswith("-") and not re.match(r"^[\w.-]+@?[\w.-]*:", a):
            operands.append(a)
        k += 1
    if target is None:
        if len(operands) < 2:
            return operands, None
        target, operands = operands[-1], operands[:-1]
    return operands, target


def lands_in_tokens(head, args, cwd):
    """Where cp, mv, rsync and kin would put a file: "token" when a source tree carries
    .claude/state/unlock/ files that land in an unlock folder, "helpers" when files land in
    scripts/env/, "config" when a file lands on a guard file (a single file too, copied into a
    folder under its own name), else ""."""
    operands, target = copy_operands(args)
    if target is None:
        return ""
    dest = None if unresolved(target) else resolve(target, cwd)
    into = dest is not None and (os.path.isdir(dest) or target.endswith("/") or len(operands) > 1
                                 or any(a in ("-t", "--target-directory") or a.startswith("--target-directory=")
                                        for a in args))
    for s in operands:
        if unresolved(s):
            return "token"
        src = resolve(s, cwd)
        base = os.path.basename(src.rstrip("/"))
        if not os.path.isdir(src):
            kind = landing(os.path.join(dest, base) if into else dest) if dest is not None else ""
            if kind:
                return kind
            continue
        for rel in walk_files(src):
            # The repo's own helpers and guard files copied elsewhere change nothing the rules trust.
            own = inside(os.path.join(src, rel).lower(), HELPERS)
            mine = inside(os.path.join(src, rel), os.path.join(ROOT, ".claude"))
            ours = any(inside(os.path.join(src, rel).lower(), d) for d in HOOK_HOMES + [
                os.path.join(ROOT, *d).lower() for d in ((".claude", "hooks"), ("scripts", "check"), ("scripts", "ops"))])
            if dest is None:
                low = ("/" + base + "/" + rel).lower()
                if "state/unlock/" in low:
                    return "token"
                if not own and "scripts/env/" in low:
                    return "helpers"
                if not mine and os.path.basename(low) in GUARD_NAMES and low.rsplit("/", 2)[-2] == ".claude":
                    return "config"
                if not ours and ("/.claude/hooks/" in low or "/.claude/plugins/" in low or os.path.basename(low) == "unlock.sh"
                                 or re.search(r"/scripts/check/hook-probes\.[^/]*\Z", low)):
                    return "hooks"
                continue
            for land in (dest, os.path.join(dest, base)):
                kind = landing(os.path.normpath(os.path.join(land, rel)))
                if kind:
                    return kind
    return ""


def extracts_to_tokens(head, args, cwd):
    """Where tar or unzip puts a member: "token" for an unlock folder, "helpers" for scripts/env/,
    "config" for a guard file, else "". An archive that cannot be listed counts when it extracts
    above one of them."""
    import tarfile, zipfile
    archive, dest = None, cwd
    if head in ("tar", "bsdtar", "gtar"):
        if not any(a in ("--extract", "--get") or re.fullmatch(r"-?[A-Za-z]*x[A-Za-z]*", a) for a in args[:1] + [a for a in args if a.startswith("-")]):
            return ""
        for k, a in enumerate(args):
            if a in ("-C", "--directory") and k + 1 < len(args):
                dest = resolve(args[k + 1], cwd)
            elif a.startswith("--directory="):
                dest = resolve(a.split("=", 1)[1], cwd)
            elif a.startswith("--file="):
                archive = a.split("=", 1)[1]
            elif (a == "--file" or re.fullmatch(r"-?[A-Za-z]*f", a)) and k + 1 < len(args) and archive is None:
                archive = args[k + 1]
    else:
        operands = [a for a in args if not a.startswith("-")]
        archive = operands[0] if operands else None
        if "-d" in args and args.index("-d") + 1 < len(args):
            dest = resolve(args[args.index("-d") + 1], cwd)
    d = dest.lower()
    if unresolved(dest):
        return ""
    try:
        path = resolve(archive, cwd)
        if head in ("tar", "bsdtar", "gtar"):
            with tarfile.open(path) as tf:
                names = tf.getnames()[:20000]
        else:
            with zipfile.ZipFile(path) as zf:
                names = zf.namelist()[:20000]
    except Exception:
        above = [kind for kind, place in (("token", TOKENS), ("helpers", HELPERS),
                                          ("config", os.path.join(ROOT, ".claude").lower()))
                 if d == place or place.startswith(d.rstrip("/") + "/")]
        return above[0] if above else guard_holder(dest) or ("hooks" if hooks_area(dest) else "")
    return next((kind for kind in (landing(os.path.normpath(os.path.join(dest, n))) for n in names) if kind), "")


def patch_mentions(files, cwd):
    """What a patch touches of the guarded places, by its text: "token", "helpers", "config" or ""."""
    for f in files:
        try:
            with open(resolve(f, cwd), "rb") as fh:
                text = fh.read(4 << 20).decode("utf-8", "replace")
        except OSError:
            continue
        if "stateunlock" in re.sub(r"[\s'\"\\/]+", "", text.lower()):
            return "token"
        if re.search(r"scripts/env/|envfile\.py", text, re.I):
            return "helpers"
        if GUARD_TEXT.search(text):
            return "config"
        if hooks_text(text) or re.search(r"(?:^|/)unlock\.sh\b", text, re.I | re.M):
            return "hooks"
    return ""


def env_message(name=None):
    shown = name or "<file>"
    return (f"[safety] BLOCKED: {name or 'this command reaches a .env* file that'} holds secrets, and the shell "
            "never reads or writes a real .env* file directly: its values would land in the transcript. "
            f"List its keys with `bash scripts/env/show.sh {shown}` (secret values masked). To change a value, the "
            f"user first runs `{unlock_hint(ROOT, 'env')}` themselves; then pipe the value in: "
            f"`printf '%s' \"$VALUE\" | bash scripts/env/set.sh {shown} KEY`. Templates (.env.example, "
            ".env.<target>.example) stay open to every command.")


def helper_message():
    return ("[safety] BLOCKED: scripts/env/ holds the only code the hooks trust with .env* files, so the shell "
            "may read it (cat, grep, git diff, shellcheck) but never change, copy over, move or delete it. Change "
            "it with the Edit tool, which asks the user first.")


def token_message():
    return ("[safety] BLOCKED: only the user unlocks .env* files and database writes. The agent never runs or "
            "changes the unlock script, never runs its package.json alias, and never creates, changes, links or "
            "removes anything in .claude/state/unlock/. When a task needs it, ask the user to run "
            f"`{unlock_hint(ROOT, 'env')}` (db in "
            "place of env for database writes) themselves; docs/unlock.md explains it.")


def config_message():
    return ("[safety] BLOCKED: .claude/settings.json, .claude/settings.local.json, .claude/agent-config.json and "
            ".claude/agent-config-kit.lock turn the guards on and set what they protect (so does the plugin's record "
            "of the projects that opted in), so the shell may read them (cat, grep, jq, git diff) but never write, "
            "truncate, copy over, move, link, chmod or delete them. Change one with the Edit tool, which asks the "
            "user first; if the shell must do it, the user runs it with `!`.")


def hooks_message():
    return ("[safety] BLOCKED: this changes a guard script: the hooks in .claude/hooks/ (as a plugin, the plugin's "
            "scripts/ and hooks/ folders), scripts/check/hook-probes.* that prove them, or scripts/ops/unlock.sh. A "
            "changed guard stops guarding, so the shell may read them (and run and copy out the hooks and probes) but "
            "never write, truncate, copy over, move, link, chmod, delete or check out over them. Change one with the "
            "Edit tool, where the user sees the change; if the shell must do it, the user runs it with `!`.")


# Paths a command changes that arrive from a pipeline (xargs), from find or from $( ): which of them
# is a guard script, scripts/env/, a guard file or an unlock file cannot be checked.
FED_CHANGE = ("[safety] BLOCKED: this hands a command that changes files (rm, mv, cp, ln, chmod, truncate, tee, "
              "sed -i, perl -i, git checkout/restore/rm/mv/stash, ...) paths from xargs, find or a $( ) "
              "substitution, so whether one is a guard script (.claude/hooks/, scripts/check/hook-probes.*, "
              "scripts/ops/unlock.sh), scripts/env/, a file that turns the guards on or an unlock file cannot be "
              "checked. List the paths, check them, then name them; if it is meant, the user runs it with `!`.")


def kind_message(kind):
    """The refusal for what kit_word, landing or patch_mentions found."""
    return {"unlock": token_message, "token": token_message, "helpers": helper_message,
            "config": config_message, "hooks": hooks_message}[kind]()


def package_script(head, args, cwd):
    """(the package.json script a bun, npm, pnpm or yarn command runs, the folder it runs from)."""
    k, d = 0, cwd
    while k < len(args) and args[k].startswith("-"):
        name, eq, v = args[k].partition("=")
        if name in ("--cwd", "-C", "--dir", "--prefix"):
            v = v if eq else (args[k + 1] if k + 1 < len(args) else ".")
            d = resolve(v, d)
        k += 2 if name in PM_VALUES and not eq else 1
    if k >= len(args):
        return "", d
    sub = args[k]
    if sub in PM_RUN:
        k += 1
        while k < len(args) and args[k].startswith("-"):
            k += 1
        return (args[k] if k < len(args) else ""), d
    if head == "npm":
        return NPM_SCRIPTS.get(sub, ""), d
    return sub, d


def package_scripts(d):
    """The scripts of the package.json nearest at or above d, and its folder."""
    d = os.path.realpath(d)
    while True:
        p = os.path.join(d, "package.json")
        if os.path.isfile(p):
            try:
                with open(p, encoding="utf-8") as fh:
                    scripts = json.load(fh).get("scripts")
            except (OSError, ValueError, AttributeError):
                scripts = None
            return (scripts if isinstance(scripts, dict) else {}), d
        if d in (ROOT, "/", os.path.dirname(d)):
            return {}, d
        d = os.path.dirname(d)


def subst_body(word):
    """The command a word that is exactly one $( ) / `...` / <( ) placeholder runs, or None."""
    m = re.fullmatch(r"__SUBST([0-9]+)__", word.strip())
    if m is None:
        return None
    idx, subs = int(m.group(1)), CUR_SUBS[0]
    return subs[idx] if 0 <= idx < len(subs) else ""


def safe_file_list(body, cwd, changing=False):
    """Whether a substitution body only lists tracked files that are not .env* files: a
    `git ls-files <pathspec>` or `git diff --name-only …`, possibly piped into line filters
    (head, tail, sort, uniq, cat, tr, cut, sed, grep, wc), whose output holds no .env* name.
    The git command is run read-only to confirm; anything else, or any .env* in the output, is
    not safe. Keeps the legitimate `cat $(git ls-files '*.md' | head)` case. changing: the list
    goes to a command that changes files, so it may hold no guarded place either (a guard script,
    scripts/env/, a guard file, an unlock file)."""
    if body is None or unresolved(cwd):
        return False
    stages = [s.strip() for s in re.split(r"\|(?!\|)", body) if s.strip()]
    if not stages:
        return False
    try:
        first = split_words(stages[0])
    except ValueError:
        return False
    if len(first) < 2 or os.path.basename(first[0]) != "git":
        return False
    # The subcommand comes first: an option before it (-c, -C, --exec-path, ...) could make the
    # confirming run below execute something, so it is not a plain listing.
    sub, k = git_sub(first[1:])
    if k:
        return False
    args = first[1 + k + 1:]
    if sub == "ls-files":
        pass
    elif sub == "diff" and ("--name-only" in args or "--name-status" in args):
        pass
    else:
        return False
    if any(unresolved(a) or a.startswith(("--output", "-o")) or "@" in a for a in args):
        return False
    filters = {"head", "tail", "sort", "uniq", "cat", "tr", "cut", "sed", "grep", "egrep", "fgrep",
               "wc", "tac", "nl", "awk", "xargs"}
    if changing:
        # Only filters that pass names through unchanged: sed, awk, tr or cut could rewrite a
        # listed name into a guarded one after the check below.
        filters = {"head", "tail", "sort", "uniq", "cat", "grep", "egrep", "fgrep", "tac"}
    for st in stages[1:]:
        try:
            w = split_words(st)
        except ValueError:
            return False
        if not w or os.path.basename(w[0]) not in filters:
            return False
    try:
        r = subprocess.run(["git", "-C", existing(resolve(".", cwd)), *first[1:]],
                           capture_output=True, text=True, errors="surrogateescape", timeout=3)
    except (OSError, subprocess.SubprocessError):
        return False
    if r.returncode != 0:
        return False
    lines = r.stdout.split("\x00") if "-z" in args or "--name-only\x00" in r.stdout else r.stdout.splitlines()
    if any(env_name(os.path.basename(x.strip())) for x in lines if x.strip()):
        return False
    if changing:
        # ls-files prints paths from the folder it runs in, diff --name-only from the repo's top.
        base = existing(resolve(".", cwd))
        if sub == "diff" and "--relative" not in args:
            base = git_out(base, "rev-parse", "--show-toplevel") or base
        for x in [x.strip() for x in lines if x.strip()]:
            p = os.path.normpath(os.path.join(base, x))
            if landing(p) or hooks_area(p) or guard_holder(p):
                return False
    return True


def literal_value(word, cwd):
    """The text a word that is exactly one $( ) / `...` printf-or-echo of literals produces, or
    None: so `$(printf '.%s' env)` and `$(printf '.claude/%s/unlock' state)` resolve. No further
    substitution, redirection or variable inside; a best-effort of what bash would print."""
    body = subst_body(word)
    if body is None or "__SUBST" in (body or "") or re.search(r"[|&;<>$`\n]", body or ""):
        return None  # only a single printf/echo of literals, never a pipeline or another command
    try:
        w = split_words(body)
    except ValueError:
        return None
    if not w:
        return None
    head = os.path.basename(w[0])
    if head == "echo":
        rest = w[1:]
        flags = 0
        while flags < len(rest) and re.fullmatch(r"-[neE]+", rest[flags]):
            flags += 1
        text = " ".join(rest[flags:])
        return ansi_decode(text) if any("e" in f for f in rest[:flags]) else text
    if head == "printf" and len(w) >= 2:
        fmt = ansi_decode(w[1])
        argv = w[2:]
        spec = re.compile(r"%[-+ 0#]*\d*(?:\.\d+)?[sd%]")
        # Only %s, %d and %% are resolved; any other conversion means we cannot say what it prints.
        if re.search(r"%[-+ 0#]*\d*(?:\.\d+)?[a-zA-Z]", re.sub(spec, "", fmt)):
            return None  # an unsupported conversion is left in the format after removing the safe ones
        out_s, ai, i = [], 0, 0
        for m in spec.finditer(fmt):
            out_s.append(fmt[i:m.start()])
            if m.group(0).endswith("%"):
                out_s.append("%")
            else:
                out_s.append(argv[ai] if ai < len(argv) else "")
                ai += 1
            i = m.end()
        out_s.append(fmt[i:])
        return "".join(out_s)
    return None


def resolve_substs(word, cwd):
    """A word with each $( )/`...` placeholder that is a printf/echo of literals replaced by what
    it prints, so `.en$(echo v)` becomes `.env` and `$(printf '.claude/%s/unlock' state)` becomes
    the token path. A placeholder the analyzer cannot compute is left as it is."""
    if "__SUBST" not in word:
        return word

    def repl(m):
        v = literal_value(m.group(0), cwd)
        return v if v is not None else m.group(0)
    return re.sub(r"__SUBST[0-9]+__", repl, word)


ARRAY_INDEX = re.compile(r"\$\{?[A-Za-z_][A-Za-z0-9_]*\[")


def bad_read_operand(word, cwd):
    """Whether a word given to a file-reading command cannot be resolved to a safe file: a
    substitution that is not the git-listing allowance, or an array index / variable the analyzer
    could not expand. A plain literal path, even a missing one, is fine (env_named judges it)."""
    if "__SUBST" in word:
        if word.strip() == "" or subst_body(word) is None:
            return True
        return not safe_file_list(subst_body(word), cwd)
    if ARRAY_INDEX.search(word):
        return True
    return False


def decodes(pws):
    """Whether a peeled command decodes bytes the analyzer cannot read (base64 -d, xxd -r, ...)."""
    head = os.path.basename(pws[0]) if pws else ""
    if head not in DECODERS:
        return False
    return head == "uudecode" or head == "openssl" or any(a in DECODE_FLAGS for a in pws[1:])


def pm_inner(head, args):
    """What a package runner's exec form runs (npm/pnpm/yarn/bun exec|dlx|x, npx, bunx, pnpx), as
    [(text, shell)]: shell is True for text that runs as shell code, False for a command and its
    arguments. Shell code: a -c/--call/--shell-mode string (npm reads its own options anywhere,
    so one counts wherever it stands), every word of `bun exec` and `yarn exec` (they join their
    words into one script), and a command word that is itself shell text. [] for anything else."""
    if head in PM_RUNNERS:
        sub, rest = head, args
    elif head in PACKAGE_MANAGERS:
        j = 0
        while j < len(args) and args[j].startswith("-"):
            name = args[j].partition("=")[0]
            j += 2 if name in PM_VALUES and "=" not in args[j] else 1
        if j >= len(args) or args[j] not in PM_EXEC:
            return []
        sub, rest = args[j], args[j + 1:]
    else:
        return []
    found = []
    for i, a in enumerate(rest):
        name, eq, v = a.partition("=")
        if name in PM_CALL_FLAGS:
            found.append((v if eq else (rest[i + 1] if i + 1 < len(rest) else ""), True))
    k = 0
    while k < len(rest) and rest[k].startswith("-") and rest[k] != "--":
        name, eq, _ = rest[k].partition("=")
        k += 2 if (name in PM_EXEC_VALUES or name in PM_CALL_FLAGS) and not eq else 1
    words = rest[k + 1:] if rest[k:k + 1] == ["--"] else rest[k:]
    if words:
        if sub == "exec" and head in ("bun", "yarn"):
            found.append((" ".join(words), True))
        else:
            found.append((" ".join(shlex.quote(w) for w in words), False))
            if SHELL_TEXT.search(words[0]):
                found.append((words[0], True))
    return found


def secrets(words, ws, raw, env, redirects, fed, prev, before, xargs, cwd, depth):
    """The .env* and unlock rules for one simple command (see the note above TOKENS)."""
    head, args = ws[0], ws[1:]
    script = script_run(ws, raw, cwd)
    # The helpers run as they are: a variable set or exported on the line (PATH, BASH_ENV,
    # PYTHONPATH, an exported function) could put other code in their place.
    runner = ENV_SCRIPTS.get(script, "") if not env and not EXPORTED else ""
    reads_code = code_texts(ws, fed, redirects, prev, before)
    piped = before in ("|", "|&") and (head in SHELLS or INTERPRETER.fullmatch(head) is not None)
    risky = xargs or piped or unresolved(cwd) or any(unresolved(a) for a in args)

    # A command whose NAME is produced by $( )/`...`: what would run is unknown, so it is refused.
    if "__SUBST" in raw:
        block("[safety] BLOCKED: the command name is built by $( ) or `...`, so safety-check cannot tell what "
              "runs, .env* reads and unlock writes included. Name the command; if it is meant, the user runs it "
              "with `!`.")

    # Package runners are wrappers: what their exec form runs (a -c string, `bun exec '<script>'`,
    # `npx <cmd> ...`) is unwrapped and checked like `bash -c`. Shell code or a command name that
    # cannot be resolved is refused, since what runs is unknown.
    for body, shell in pm_inner(head, args):
        if shell and ("__SUBST" in body or unresolved(body)) or not shell and unresolved(body.split(" ", 1)[0]):
            block("[safety] BLOCKED: this package runner runs a command or shell text built by $( ), `...` or a "
                  "variable safety-check cannot resolve, so what it runs (a .env* read or an unlock included) is "
                  "unknown. Name the command; if it is meant, the user runs it with `!`.")
        mentions(body)
        analyse(body, cwd, depth + 1, {})

    # make/just/task reading a recipe from stdin: its lines run in a shell the analyzer never sees.
    if head in ("make", "gmake", "bmake", "just", "task", "mise") and (fed or before in ("|", "|&")) and \
            any(a in ("-", "/dev/stdin", "/proc/self/fd/0") for a in args):
        block("[safety] BLOCKED: this reads its recipe from stdin, so the commands it runs (an unlock or a .env* "
              "read included) cannot be checked. Put the recipe in a named file, or the user runs it with `!`.")

    # A decoder's output piped into a shell, interpreter, eval, xargs or a file command runs or
    # opens something the analyzer cannot read.
    if before in ("|", "|&") and prev is not None:
        if decodes(peel(prev)[0]) and (head in SHELLS or head in ("eval", "source", ".") or xargs
                                       or INTERPRETER.fullmatch(head) is not None or head in CONTENT_READERS
                                       or head in COPIERS or head in ("mkdir", "install", "tee", "dd", "ln", "touch")):
            block("[safety] BLOCKED: a decoder's output is piped into a command, so what it runs or the file it "
                  "reaches (a .env* read or an unlock write included) cannot be checked. Decode to a named file "
                  "and inspect it first; if it is meant, the user runs it with `!`.")

    # Code a shell or interpreter reads from stdin, fed by a command whose output cannot be read
    # (echo/printf text is read and checked; a shell's pipe is handled in run) or by `< <( )`.
    if code_from_stdin(ws):
        piped_in = before in ("|", "|&") and prev is not None
        pws = peel(prev)[0] if piped_in else []
        shell = head in SHELLS or head in ("source", ".")
        readable = bool(pws) and (pws[0] in ("echo", "printf") or (shell and any("__HEREDOC" in w for w in prev)))
        if (piped_in and not readable) or any(op == "<" and "__SUBST" in t for op, t in redirects):
            block(STDIN_CODE)

    # A file-reading command handed a substitution, or an operand safety-check cannot resolve: the
    # file it opens is unknown. The one allowance is a git file-listing that holds no .env*.
    if head in FILE_OPERAND_READERS:
        for a in args:
            if not a.startswith("-") and bad_read_operand(a, cwd):
                block("[safety] BLOCKED: this reads a file whose name comes from $( )/`...` or an expansion "
                      "safety-check cannot resolve, so a .env* file cannot be ruled out. Name the file, or list "
                      "tracked files with `git ls-files <pathspec>`; if it is meant, the user runs it with `!`.")

    # xargs feeding a file reader: the paths arrive on stdin and cannot be checked.
    if xargs and head in FILE_OPERAND_READERS:
        block("[safety] BLOCKED: xargs feeds a file reader paths from a pipeline, so what it opens (a .env* file "
              "included) cannot be checked. List the files, check them, then read named paths.")

    # sqlite3 reaching a .env* file (for example `.read .env`).
    if head in ("sqlite3", "sqlite") and any(ENV_TEXT.search(a) and ".example" not in a.lower() for a in args):
        block(env_message())

    # docker/compose reading a .env* file for `config`, which prints the resolved values.
    if head in ("docker", "docker-compose", "podman", "podman-compose") and "config" in args:
        for k, a in enumerate(args):
            v = (a.split("=", 1)[1] if a.startswith("--env-file=")
                 else args[k + 1] if a == "--env-file" and k + 1 < len(args) else "")
            hit = env_named(v, cwd) if v else ""
            if hit:
                block(env_message(hit))

    # Only the user unlocks.
    fed_script = head in SHELLS and any(op == "<" and os.path.basename(t) == "unlock.sh" for op, t in redirects)
    copied = head in COPIERS and any(os.path.basename(a) == "unlock.sh" for a in args if not a.startswith("-"))
    if head == "unlock.sh" or os.path.basename(script) == "unlock.sh" or fed_script or copied:
        block(token_message())
    if head in PACKAGE_MANAGERS:
        name, where = package_script(head, args, cwd)
        if name == "unlock":
            block(token_message())
        elif name:
            scripts, pkg = package_scripts(where)
            for key in ("pre" + name, name, "post" + name):
                if isinstance(scripts.get(key), str):
                    mentions(scripts[key])
                    analyse(scripts[key], pkg, depth + 1, {})
    if head == "git" and git_sub(args)[0] == "stash" and any(a in ("-a", "--all") or re.fullmatch(r"-[A-Za-z]*a[A-Za-z]*", a) for a in args):
        block("[safety] BLOCKED: git stash --all takes ignored files too (.env* files and .claude/state/), and a "
              "later pop puts them back. Stash tracked work by path: git stash push -- <paths>.")
    reader = head in TOKEN_READERS or (head == "find" and not FIND_ACTIONS & set(args))
    if not reader:
        if any(token_word(a, cwd, head in PARENT_OPS) for a in args):
            block(token_message())
        kind = ""
        if head in COPIERS:
            # A copy, move or link whose destination is an unlock folder, .claude/state or .claude
            # would put the agent's own file where a token lives, so it is refused.
            tgt = copy_operands(args)[1]
            if tgt and not unresolved(tgt) and "__SUBST" not in tgt:
                dp = resolve(tgt, cwd).lower()
                if token_area(dp) or token_parent(dp):
                    block(token_message())
            kind = lands_in_tokens(head, args, cwd)
        elif head in ("tar", "bsdtar", "gtar", "unzip"):
            kind = extracts_to_tokens(head, args, cwd)
        elif head == "patch" or (head == "git" and git_sub(args)[0] in ("apply", "am")):
            kind = patch_mentions([a for a in args if not a.startswith("-")] + [t for op, t in redirects if op == "<"], cwd)
            # patch finds its files from the folder it runs in: there a bare name reaches a guarded place.
            kind = kind or (near_guard(cwd) if head == "patch" else "")
        if kind:
            block(kind_message(kind))
        if risky and "token" in MENTIONS:
            block(token_message())
    # sed and awk name the files they write and read, and the commands they run, inside their
    # program: a sed w, W or s///w, r or R, e or s///e; an awk print > or >>, print |, | getline,
    # getline < or system(). Each is judged as the redirect or command it is; one built at run time,
    # or a program that cannot be read, is refused.
    only_reads = False
    if head in SED_NAMES:
        found = sed_programs(args, fed + [t for op, t in redirects if op == "<<<"], cwd)
        texts, strict = found if found is not None else ([], True)
        parsed = [sed_parse(t) for t in texts]
        if found is None or texts and ((strict and None in parsed) or all(p is None for p in parsed)):
            block("[safety] BLOCKED: safety-check cannot read this sed program (a -f file it cannot open, or a script "
                  "sed would not accept), so what it writes, reads or runs is unknown. Name the program inline; if it "
                  "is meant, the user runs it with `!`.")
        for text in texts:
            # A program that names a guard file is refused apart (config_reader lets sed read one).
            if GUARD_TEXT.search(text):
                block(config_message())
        for p in parsed:
            for t in p[0] if p else []:
                judge_write(t, cwd, "this sed program (w, W or s///w)")
            for t in p[1] if p else []:
                judge_read(t, cwd, "this sed program (r or R)")
            for body in p[2] if p else []:
                if body is None:
                    block("[safety] BLOCKED: this sed program runs its pattern space as a command (s///e, or e with no "
                          "command), text safety-check cannot read. If it is meant, the user runs it with `!`.")
                else:
                    mentions(body)
                    analyse(body, cwd, depth + 1, {})
    if head in AWK_NAMES:
        programs = awk_programs(args, cwd)
        found = [awk_io(p) for p in programs or []]
        if programs is None or any(f is None for f in found):
            block("[safety] BLOCKED: safety-check cannot read this awk program (a -f file it cannot open, or code it "
                  "pulls in with -i, -l, @include or @load), so what it writes or runs is unknown. Name the program "
                  "inline; if it is meant, the user runs it with `!`.")
        reads_code += [p for p in programs or [] if p not in reads_code]
        only_reads = bool(found) and all(f and not f[0] and not f[1] for f in found)
        for writes, runs, sources in [f for f in found if f]:
            for t in writes:
                judge_write(t, cwd, "this awk program (print or printf > or >>)")
            for t in sources:
                judge_read(t, cwd, "this awk program (getline <)")
            for body, fed_output in runs:
                if body is None:
                    block("[safety] BLOCKED: this awk program runs a command built at run time (system(), print | or "
                          "| getline), so what it runs is unknown. Run the command directly; if it is meant, the user "
                          "runs it with `!`.")
                elif body.strip():
                    mentions(body)
                    # print | "cmd" feeds cmd the program's output: a shell reading it runs unread code.
                    analyse(": | " + body if fed_output else body, cwd, depth + 1, {})
    # unlock.sh, scripts/env/, the guard files and the guard scripts: a command that names one may
    # only read it. The helper a command runs as its script is not counted; whether it may run is
    # decided below.
    looks = (head in LOOKERS or (head == "git" and git_sub(args)[0] in GIT_LOOKS)
             or (head == "find" and not FIND_ACTIONS & set(args)))
    config_reads = looks or config_reader(head, args) or only_reads
    # git -C moves the folder its path operands are read from.
    wd = git_cwd(args, cwd) if head == "git" else cwd
    if not looks:
        # A copy leaves its source as it was: for scripts/env/, the guard files and the guard
        # scripts only where it lands counts.
        sources = copy_operands(args)[0] if head in COPIERS - {"mv", "ln", "link"} else []
        # Only show.sh, set.sh and envfile.py are privileged; running any other project script under
        # scripts/env/ is an ordinary run, not a change to a helper. The file a command executes (a
        # shell/source script, or a package-runner's file target) is exempt from the change block.
        executed = {script} if script else set()
        if head in PACKAGE_MANAGERS:
            run_name, run_where = package_script(head, args, cwd)
            if run_name and "/" in run_name and not unresolved(run_name):
                executed.add(resolve(run_name, run_where))
        for a in args:
            if re.fullmatch(r"-[A-Za-z0-9-]*", a):
                continue  # a flag names no file
            kind = kit_word(a, wd, head in PARENT_OPS)
            if kind in ("helpers", "config", "hooks") and a in sources:
                continue
            if kind in ("config", "hooks") and config_reads:
                continue
            # Running a non-privileged script under scripts/env/, or a hook, is a normal run, not a
            # change to it. Executing unlock.sh is never exempt: kind == "unlock" still blocks.
            if kind in ("helpers", "hooks") and not unresolved(a) and resolve(a, wd) in executed:
                continue
            if kind:
                block(kind_message(kind))
                break
        # Moving or linking a folder, changing modes under it, or checking it out carries along
        # every guarded place it holds: the repo itself, .claude, scripts, a plugin's folder.
        for a in carried_along(head, args, wd):
            kind = "" if unresolved(a) else guard_holder(resolve(a, wd))
            if kind:
                block(kind_message(kind))
                break
    # A guarded place named where the analyzer cannot follow it: a path xargs feeds or one built by
    # $( ) or a variable.
    if not config_reads and (xargs or unresolved(cwd) or any(unresolved(a) for a in args)):
        if "config" in MENTIONS:
            block(config_message())
        if "hooks" in MENTIONS:
            block(hooks_message())
    # A command that changes files, handed paths the analyzer cannot see: from xargs, or built by $( )
    # or a variable set from one. Copying out stays open: a cp, rsync, install or ln whose sources
    # arrive that way but whose destination is named. A git listing that names none of the guarded
    # places (the git-listing allowance) is seen.
    if changes_files(head, args):
        copy_like = head in COPIERS - {"mv"}
        reps = xargs_replacements(words) if xargs else set()
        operands, dest = copy_operands(args) if copy_like else ([], None)
        dest_known = dest is not None and not unresolved(dest) and not any(r in dest for r in reps)
        if xargs and not (copy_like and dest_known):
            block(FED_CHANGE)
        # A sed, perl or ruby program is code, not a path.
        found = sed_programs(args, [], cwd) if head in SED_NAMES else None
        code = set(found[0] if found else [])
        code |= {args[k + 1] for k, a in enumerate(args[:-1])
                 if a in ("-e", "--expression") or re.fullmatch(r"-[A-Za-z]*[eE]", a)}
        paths = carried_along(head, args, cwd) if head == "git" else [a for a in args if a not in code]
        for a in paths:
            if "__SUBST" not in a and not any(refers(name, a) for name in TAINTED):
                continue
            if copy_like and dest_known and a != dest:
                continue
            body = subst_body(a)
            if body is not None and safe_file_list(body, cwd, changing=True):
                continue
            block(FED_CHANGE)
            break
    # find -exec or -execdir running a command that changes files, over a tree that holds a guarded
    # place: the files it reaches there are unknown. Shells and interpreters are carried below.
    if head == "find":
        roots = []
        for a in args:
            if a.startswith("-") or a in ("!", "(", "__ESCAPED__"):
                break
            roots.append(a)
        k = 0
        while k < len(args):
            if args[k] in ("-exec", "-execdir", "-ok", "-okdir"):
                j = k + 1
                while j < len(args) and args[j] not in (";", "+", "\\;"):
                    j += 1
                seg = peel(args[k + 1:j])[0]
                if seg and changes_files(seg[0], seg[1:]):
                    for r in roots or ["."]:
                        p = None if unresolved(r, glob=True) else resolve(r, cwd)
                        kind = "" if p is None else guard_holder(p) or landing(p) or ("hooks" if hooks_area(p) else "")
                        if p is None or kind:
                            block(kind_message(kind) if kind else FED_CHANGE)
                            break
                k = j
            k += 1
    if (head in SHELLS or head in ("source", ".")) and unknown_script(ws, xargs):
        block("[safety] BLOCKED: this runs a script whose file safety-check cannot name (from $( ), a variable, "
              "find's {} or xargs), so it cannot tell it apart from scripts/ops/unlock.sh, which only the user runs. "
              "Name the script file.")
    # Commands that carry another command: find -exec with a shell or an interpreter, and git
    # aliases that start with ! (git -c alias.x='!cmd', git config alias.x '!cmd').
    carried = []
    if head == "find":
        k = 0
        while k < len(args):
            if args[k] in ("-exec", "-execdir", "-ok", "-okdir"):
                j = k + 1
                while j < len(args) and args[j] not in (";", "+", "\\;"):
                    j += 1
                seg = args[k + 1:j]
                if seg and (os.path.basename(seg[0]) in SHELLS or os.path.basename(seg[0]) in ("source", ".")
                            or INTERPRETER.fullmatch(os.path.basename(seg[0]))):
                    carried.append(" ".join(shlex.quote(w) for w in seg))
                k = j
            k += 1
    if head == "git":
        for k, a in enumerate(args):
            name, eq, value = a.partition("=")
            if args[k - 1:k] == ["-c"] and name.lower().startswith("alias.") and value.startswith("!"):
                carried.append(value[1:])
            elif a.lower().startswith("alias.") and not eq and k + 1 < len(args) and args[k + 1].startswith("!"):
                carried.append(args[k + 1][1:])
        # Settings git runs as a command (core.pager, core.fsmonitor, diff.external, ...).
        for body in git_carriers(args, {**EXPORTED, **env}):
            if body is None:
                block(CARRIER_UNKNOWN)
            elif body:
                carried.append(body)
    # Variables a tool runs as a command (GIT_PAGER, EDITOR, GIT_SSH_COMMAND, LESSOPEN, ...), set on
    # this line or exported earlier on it.
    for name, value in {**EXPORTED, **env}.items():
        if name in COMMAND_VARS:
            body = carried_value(value)
            if body is None:
                block(CARRIER_UNKNOWN)
            elif body:
                carried.append(body)
    for body in carried:
        mentions(body)
        analyse(body, cwd, depth + 1, {})
    for text in reads_code:
        if "stateunlock" in re.sub(r"[\s'\"\\/+,]+", "", text.lower()) or "unlock.sh" in text.lower():
            block(token_message())
        if re.search(r"scripts\W{0,8}env(?!\w)|envfile", text, re.I):
            block(helper_message())
        if GUARD_TEXT.search(text):
            block(config_message())
        if hooks_text(text):
            block(hooks_message())
    # Inline code (python -c, node -e, a heredoc fed to perl, ...) that changes or deletes a file or
    # runs a command: which file it reaches cannot be read from its text, since a name can be built
    # or relative to a folder the code picks. awk is read above instead.
    interp = next((os.path.basename(w) for w in ws if INTERPRETER.fullmatch(os.path.basename(w))), "")
    if reads_code and not interp.endswith("awk"):
        kind = near_guard(cwd)
        if kind:
            block(kind_message(kind))
        for text in reads_code:
            if INLINE_CHANGE.search(text) or (interp in ("perl", "ruby") and "`" in text):
                block("[safety] BLOCKED: this inline code changes, moves or deletes a file or runs a command, so "
                      "whether it reaches a guard script, scripts/env/, a guard file, an unlock file or a .env* file "
                      "cannot be read from its text. Use the shell command for it (rm, mv, git ...), which "
                      "safety-check can read, or the Edit tool; if it is meant, the user runs it with `!`.")
                break

    # .env* files: only the two helper scripts open them, set.sh only while env is unlocked.
    if runner == "set.sh" and not unlock_until(ROOT, "env"):
        block(f"[safety] BLOCKED: .env* files are locked, so scripts/env/set.sh may not change them now. Ask the user "
              f"to run `{unlock_hint(ROOT, 'env')}` themselves (it stays open 20 minutes), then run set.sh again.")
    if runner:
        return
    for text in reads_code:
        found = next((m.group(0) for m in ENV_TEXT.finditer(text) if ".example" not in m.group(0).lower()), "")
        if found or "env-backups" in text.lower():
            block(env_message(found or None))
    # A program that loaded a .env* file (bun always does; --env-file, dotenv) hands its values to
    # the code it runs, and printing them is reading the file.
    loaded = head in ("bun", "bunx") or any(a == "--env" or a.startswith("--env-file") for a in args)
    for text in reads_code:
        if ENV_LOADER_CODE.search(text) or (loaded and ENV_ACCESS.search(text)):
            block("[safety] BLOCKED: this code reads values loaded from a .env* file (bun loads the .env* files "
                  "by itself; so do --env-file and dotenv), and they would land in the transcript. See which keys "
                  "are set, masked, with `bash scripts/env/show.sh <file>`.")
    # Inline interpreter code that opens or lists files, or builds a path to one: safety-check
    # cannot tell it apart from reading or writing a .env* file, so it is refused.
    for text in reads_code:
        if INLINE_FILE.search(text):
            block("[safety] BLOCKED: this inline code opens, lists or builds a path to a file, so a .env* read or "
                  "write cannot be ruled out. Read a file with the Read/Edit tools, or list env keys (masked) with "
                  "`bash scripts/env/show.sh <file>`; if this is really meant, the user runs it with `!`.")
    tool = next((k for k, w in enumerate(ws) if os.path.basename(w) in ENV_PRINTERS), None)
    if tool is not None:
        sub = next((w for w in ws[tool + 1:] if not w.startswith("-")), "")
        if sub in ENV_PRINTERS[os.path.basename(ws[tool])]:
            block(env_message())
    if head in NAME_ONLY:
        return
    sub, at = git_sub(args) if head == "git" else ("", 0)
    if head == "git" and sub in GIT_NAME_ONLY:
        return
    if head == "find" and not FIND_ACTIONS & set(args):
        return
    skip = loader_values(head, args)
    # An --exclude glob leaves files out rather than naming one (grep, rsync, tar); grep's
    # --include and -g globs go to grep_reads_env below.
    globs = ("--exclude", "--include", "-g", "--glob", "--iglob") if head in GREPS else ("--exclude",)
    for k, a in enumerate(args):
        if a.partition("=")[0] in globs:
            skip.add(k if "=" in a else k + 1)
    if head in GREPS:
        skip |= pattern_index(head, args)
    elif head == "git" and sub == "grep":
        skip |= {at + 1 + k for k in pattern_index("grep", args[at + 1:])}
    for k, a in enumerate(args):
        name = "" if k in skip else env_named(a, cwd)
        if name:
            return block(env_message(name))
    if head in GREPS:
        name = grep_reads_env(head, args, cwd)
        if name:
            return block(f"[safety] BLOCKED: this recursive search reads {name}, a secrets file. Leave .env* files out "
                         "(grep: --exclude='.env*'; rg: drop --hidden or add -g '!.env*'), or search named folders.")
    if head == "git" and sub == "grep" and "--no-exclude-standard" in args:
        return block("[safety] BLOCKED: git grep --no-exclude-standard searches ignored files, .env* included. "
                     "Drop the flag.")
    if risky and "env" in MENTIONS:
        block(env_message())


def gh_flags(args, values):
    """(name, value) for each option gh (pflag) reads: `--name=v`, `--name v` when name takes a
    value, `-abc` as -a -b -c, and `-Xv` or `-X v` when X takes one. value is None for a switch."""
    found, k = [], 0
    while k < len(args):
        a = args[k]
        k += 1
        if a == "--":
            break
        if a.startswith("--"):
            name, eq, v = a.partition("=")
            if not eq and name in values and k < len(args):
                v, k = args[k], k + 1
            found.append((name, v if eq or name in values else None))
        elif a.startswith("-") and len(a) > 1:
            for j, ch in enumerate(a[1:], 1):
                if "-" + ch in values:
                    v = a[j + 1:]
                    if not v and k < len(args):
                        v, k = args[k], k + 1
                    found.append(("-" + ch, v))
                    break
                found.append(("-" + ch, None))
    return found


GH_MERGE_VALUES = {"-b", "--body", "-F", "--body-file", "-t", "--subject", "-A", "--author-email",
                   "--match-head-commit", "-R", "--repo"}
GH_API_VALUES = {"-X", "--method", "-H", "--header", "-f", "--raw-field", "-F", "--field", "-p", "--preview",
                 "-q", "--jq", "-t", "--template", "--input", "--hostname", "--cache"}
ALEMBIC_VALUES = {"-c", "--config", "-n", "--name", "-x"}
FALSE = {"false", "0", "f"}


def check_push(rest, d):
    reason = (f"[safety] BLOCKED: pushing to a protected branch ({BRANCH_TEXT}) is not allowed. Push your work "
              "branch and open a PR; when a release needs this push, the user runs it with `!`.")
    words = [w for w in rest if not w.startswith("-")]
    if any(w in ("--all", "--mirror", "--branches") for w in rest):
        return block(reason)
    deleting = any(w in ("-d", "--delete") for w in rest)
    refs = words[1:]
    for r in refs:
        dst = r.split(":")[-1].lstrip("+")
        dst = dst[len("refs/heads/"):] if dst.startswith("refs/heads/") else dst
        if dst in BRANCH_SET or (deleting and r in BRANCH_SET):
            return block(reason)
    literal = [r for r in refs if not re.search(r"[$`@]|^HEAD$|^HEAD:|__SUBST", r)]
    if not refs or len(literal) < len(refs):
        on = branch_of(d)
        if on in BRANCH_SET:
            block(f"{reason} (the checkout at {d} is on {on})")


SHELL_C = re.compile(r"^-[a-zA-Z]*c[a-zA-Z]*$")


def check(ws, env, xargs, cwd, depth, scope):
    if not ws:
        return
    head, args = ws[0], ws[1:]
    if head in SHELLS:
        flag = next((k for k, a in enumerate(args) if SHELL_C.match(a)), None)
        if flag is not None and flag + 1 < len(args):
            # `sh -c 'rm -rf "$1"' _ src`: the words after the payload are $0, $1, ...
            positional = args[flag + 2:]
            params = {str(k): v for k, v in enumerate(positional)}
            params["@"] = params["*"] = " ".join(positional[1:])
            return analyse(args[flag + 1], cwd, depth + 1, params)
    if head == "eval":
        joined = " ".join(args)
        if "__SUBST" in joined or unresolved(joined):
            block("[safety] BLOCKED: eval runs text built by $( )/`...` or an expansion safety-check cannot "
                  "resolve, so what it executes (a .env* read or an unlock included) is unknown. Run the command "
                  "directly; if it is really meant, the user runs it with `!`.")
        return analyse(joined, cwd, depth + 1, scope)

    if head == "rm":
        flags = [a for a in args if a.startswith("-") and a != "--"]
        targets = [a for a in args if not a.startswith("-")]
        recursive = any(a == "--recursive" or re.match(r"^-[A-Za-z]*[rR]", a) for a in flags)
        if recursive and xargs and not targets:
            block("[safety] BLOCKED: recursive rm fed by xargs; the paths it deletes cannot be checked. Delete named paths.")
        for t in targets:
            if recursive and protected_target(t, cwd) and not disposable(t, cwd):
                block(f"[safety] BLOCKED: recursive rm on a protected path: {t}. Tracked files go with `git rm -r <path>`, "
                      "which stays recoverable; a throwaway you made goes freely when it is named zz-* or *-probe and "
                      "holds nothing git tracks; a disposable worktree goes with `git worktree remove --force <dir>`.")
    if head in ("rmdir", "unlink", "shred") and xargs:
        block(f"[safety] BLOCKED: {head} fed by xargs; list the paths, then delete them by name.")
    if head == "find":
        execs = [args[k + 1] for k, a in enumerate(args) if a in ("-exec", "-execdir", "-ok", "-okdir") and k + 1 < len(args)]
        roots = []
        for a in args:
            if a.startswith("-") or a in ("!", "__ESCAPED__"):
                break
            roots.append(a)
        temp_only = all("$" not in r and not any(ch in r for ch in "*?[") and throwaway(resolve(r, cwd)) for r in roots or ["."])
        if not temp_only and ("-delete" in args or any(os.path.basename(e) in ("rm", "rmdir", "unlink", "shred") for e in execs)):
            block("[safety] BLOCKED: find that deletes. Print the list with -print, check it, then delete named paths.")

    if head == "git":
        i, gdir, configs = 0, cwd, []
        while i < len(args):
            a = args[i]
            if a == "-C" and i + 1 < len(args):
                gdir = resolve(args[i + 1], gdir)
                i += 2
            elif a == "-c" and i + 1 < len(args):
                configs.append(args[i + 1])
                i += 2
            elif a.startswith("-"):
                i += 1
            else:
                break
        sub, rest = (args[i], args[i + 1:]) if i < len(args) else ("", [])
        # A help flag (`--help`, `-h`) right after `commit` or `push` prints help and does nothing
        # else. Only as the first word: after `-m` the same word is a commit message.
        helping = rest[:1] in (["--help"], ["-h"]) or any(a in ("--help", "-h") for a in args[:i])
        # A throwaway repo under a temp folder is a fixture: its gates and its work are its own.
        refuse = (lambda reason: None) if throwaway(gdir) else block
        # `export HUSKY=0` earlier on the line reaches this git as surely as `HUSKY=0 git`.
        env = {**EXPORTED, **env}
        bypass = "[safety] BLOCKED: skipping the pre-commit gate is not allowed. Fix what it reports."
        for c in configs:
            key, _, value = c.partition("=")
            if key.lower() == "core.hookspath" and not hooks_same(value, gdir):
                refuse(bypass)
        for key, value in git_settings(args, env):
            if git_setting_refused(key, value):
                block(GIT_SETTING.format(key=key))
        if sub == "config":
            keys = [r for r in rest if not r.startswith("-")]
            writes = any(r in ("--unset", "--unset-all", "--replace-all", "--add", "--edit", "-e") for r in rest)
            reads = any(r in ("--get", "--get-all", "--get-regexp", "--list", "-l") for r in rest)
            if any(k.lower() == "core.hookspath" for k in keys) and (writes or (len(keys) > 1 and not reads)):
                if writes or not hooks_same(keys[1], gdir):
                    refuse(bypass)
        if env.get("HUSKY") == "0" or ("SKIP" in env and sub == "commit"):
            refuse(bypass)
        if sub in ("commit", "push", "merge") and ("--no-verify" in rest or (sub == "commit" and any(re.match(r"^-[a-zA-Z]*n[a-zA-Z]*$", r) for r in rest))):
            refuse(bypass)
        wipe = "[safety] BLOCKED: this wipes uncommitted work, including other sessions' in a shared checkout. Name the paths you own."
        whole = lambda paths: any(p in (".", ":/", ":", "*", "./") for p in paths)
        if sub == "clean" and any(r == "--force" or re.match(r"^-[a-zA-Z]*f", r) for r in rest):
            scoped = rest[rest.index("--") + 1:] if "--" in rest else []
            if not scoped or whole(scoped) or any(protected_target(p, gdir) for p in scoped):
                refuse(wipe)
        if sub == "reset" and "--hard" in rest:
            refuse(wipe)
        if sub == "checkout":
            paths = rest[rest.index("--") + 1:] if "--" in rest else []
            if "-f" in rest or "--force" in rest or whole(paths) or ("--" not in rest and "." in rest):
                refuse(wipe)
        if sub == "restore" and whole([r for r in rest if not r.startswith("-")]):
            refuse(wipe)
        if sub == "stash":
            action = rest[0] if rest and not rest[0].startswith("-") else "push"
            if action == "clear":
                refuse(wipe)
            if action in ("push", "save") and not ("--" in rest and rest.index("--") + 1 < len(rest)):
                refuse("[safety] BLOCKED: git stash without a pathspec takes every session's work. Use: git stash push -- <your paths>.")
        if sub == "branch":
            names = [r for r in rest if not r.startswith("-")]
            deleting = any(r in ("-d", "-D", "--delete") or re.match(r"^-[a-zA-Z]*[dD]", r) for r in rest)
            if deleting and any(n in BRANCH_SET for n in names):
                block(f"[safety] BLOCKED: deleting a protected branch ({BRANCH_TEXT}).")
        if sub == "update-ref" and any(r in ("-d", "--delete") for r in rest) and any(BRANCH_REF.search(r) for r in rest):
            block(f"[safety] BLOCKED: deleting a protected branch ({BRANCH_TEXT}).")
        if sub == "commit" and "--dry-run" not in rest and not helping:
            guessed = unresolved(gdir, glob=True)
            where = (os.environ.get("HOOK_CWD") or cwd) if guessed else gdir
            if MODE == "commits":
                paths = rest[rest.index("--") + 1:] if "--" in rest else []
                paths = [] if any(unresolved(x) for x in paths) else paths
                out.append("\t".join(["COMMIT", where, "\x1f".join(paths), subject(rest), "guessed" if guessed else ""]))
            else:
                mark(where)
        if sub == "push" and "--dry-run" not in rest and "-n" not in rest and not helping:
            check_push(rest, gdir)

    if head == "gh" and len(args) > 1:
        # gh reaches GitHub from any folder, so a temp cwd exempts nothing. `--help` and `-h` right
        # after the subcommand print help; elsewhere they may be a flag's value (`--body -h`).
        helping = args[2:3] in (["--help"], ["-h"])
        if args[:2] == ["pr", "merge"] and not helping:
            flags = gh_flags(args[2:], GH_MERGE_VALUES)
            if any(n in ("-d", "--delete-branch") and (v is None or v.lower() not in FALSE) for n, v in flags):
                block("[safety] BLOCKED: gh pr merge --delete-branch deletes the PR's head branch, a protected one "
                      "when it is the head. Merge, then delete the work branch by name: git push origin --delete <branch>.")
        if args[0] == "api":
            method = next((v.upper() for n, v in reversed(gh_flags(args[1:], GH_API_VALUES)) if n in ("-X", "--method") and v), "")
            if method == "DELETE" and any(BRANCH_REF.search(a) for a in args):
                block(f"[safety] BLOCKED: deleting a protected branch ({BRANCH_TEXT}).")

    # Alembic, only where the repo (or the folder the command runs in) has an alembic.ini.
    alembic = head == "alembic" or (head in ("uv", "poetry", "python", "python3") and "alembic" in args)
    if alembic and (os.path.exists(os.path.join(ROOT, "alembic.ini")) or os.path.exists(os.path.join(cwd, "alembic.ini"))):
        rest, k, sub = args[args.index("alembic") + 1:] if "alembic" in args else args, 0, ""
        while k < len(rest):
            if rest[k] in ALEMBIC_VALUES:
                k += 2
            elif rest[k].startswith("-"):
                k += 1
            else:
                sub = rest[k]
                break
        if sub == "downgrade":
            block("[safety] BLOCKED: alembic downgrade drops columns and the data in them. Write a new forward revision.")


def plain_text_rules(text, cwd):
    """The last resort for a command no closing quote makes tokenisable. The same rules as
    safety-check.sh's fallback for a machine without python3, and no weaker."""
    out.append("WARN\tsafety-check could not tokenise this command, so only its plain-text rules ran.")
    names = "|".join(re.escape(n) for n in sorted(PROTECTED_NAMES | set(PROTECTED_PATHS))) or r"(?!)"
    rm = r"(^|[;&|\s])rm\s+-[a-zA-Z]*[rR]"
    if re.search(rm, text) and re.search(r"(^|[\s/\"'])(" + names + r")(/|[\s\"']|$)", text):
        block("[safety] BLOCKED: rm -r on a protected path (unparseable command).")
    if re.search(rm + r"[a-zA-Z]*\s+(\.|\./|/|~|~/|\*|\./\*|\.\.)([\s\"';&|]|$)", text):
        block("[safety] BLOCKED: rm -r on the repo, a parent folder or the home folder (unparseable command).")
    if re.search(r"git\s[^;&|]*push[^;&|]*[\s:+](" + BRANCH_ALT + r")([\s\"';&|]|$)", text):
        block(f"[safety] BLOCKED: pushing to a protected branch ({BRANCH_TEXT}) is not allowed.")
    if re.search(r"git\s+([^;&|]*\s)?(reset\s[^;&|]*--hard|clean(\s[^;&|]*)?\s(-[a-zA-Z]*f[a-zA-Z]*|--force)([^\w-]|$))|--no-verify|HUSKY=0",
                 text):
        block("[safety] BLOCKED: a hard reset, a forced clean or a skipped pre-commit gate (unparseable command).")
    if "env" in MENTIONS:
        block(env_message())
    if "token" in MENTIONS or re.search(r"state/+(\./+)*unlock|\b(bun|npm|pnpm|yarn)\s+(run\s+|run-script\s+)?unlock\b",
                                        text, re.I):
        block(token_message())
    if re.search(r"scripts/+(\./+)*env(/|\s|$)|envfile\.py", text, re.I):
        block(helper_message())
    if "config" in MENTIONS:
        block(config_message())
    if "hooks" in MENTIONS:
        block(hooks_message())


def reads_stdin(args):
    """Whether a shell with these arguments runs what arrives on stdin: no -c and no script."""
    for a in args:
        if a in ("-s", "-"):
            return True
        if SHELL_C.match(a) or not a.startswith(("-", "+")):
            return False
    return True


def taint(name, value):
    """Records whether a variable now holds text from a $( ) the analyzer could not compute (or from
    another such variable); mktemp's new path is not counted."""
    bodies = [subst_body(m) for m in re.findall(r"__SUBST[0-9]+__", value)]
    if (any(b is None or not re.match(r"\s*mktemp(\s|$)", b) for b in bodies)
            or any(refers(other, value) for other in TAINTED)):
        TAINTED.add(name)
    else:
        TAINTED.discard(name)


def refers(name, word):
    return re.search(r"\$\{?" + re.escape(name) + r"(?![A-Za-z0-9_])", word) is not None


def run(words, redirects, before, prev, docs, cwd, depth, scope, loops, aliases, subs=None):
    """Applies the rules to one simple command whose words are already expanded; returns the cwd
    the commands after it run in."""
    CUR_SUBS[0] = subs if subs is not None else CUR_SUBS[0]
    for op, t in redirects:
        if op == "<<<" or (op in (">&", "<&") and re.fullmatch(r"[0-9]*-?", t)):
            continue  # a here-string is text; >&2 and <&0 name descriptors, not files
        name = env_named(t, cwd)
        if name:
            block(env_message(name))
        if op != "<" and token_word(t, cwd, False):
            block(token_message())
        kind = kit_word(t, cwd, path=True) if op != "<" else ""
        if kind:
            block(kind_message(kind))
        # A write whose target is built by a substitution the analyzer cannot compute (or by a
        # variable set from one): where it lands is unknown, and it could be a .env* file, a token
        # or a guard script, so it is refused.
        if op not in ("<", "<<<") and ("__SUBST" in t or any(refers(n, t) for n in TAINTED)):
            block("[safety] BLOCKED: this writes to a file whose name is built by $( ) or `...`, so safety-check "
                  "cannot tell whether it is a .env* file or an unlock token. Write to a named path; if it is "
                  "really meant, the user runs it themselves with `!`.")
    ws, env, xargs, raw = peel(words)
    if not ws:
        # `S=/tmp/x` on its own: the words after it in this command line see the value. A value from
        # a printf/echo substitution of literals is computed, so `S=$(printf '.claude/%s/unlock' …)`
        # reaches the later `> "$S/env"`.
        for k, v in env.items():
            v = resolve_substs(v, cwd)
            if k in COMMAND_VARS:
                EXPORTED[k] = v  # usually exported already, so the new value reaches every later tool
            taint(k, v)
            if re.search(r"[$`]|__SUBST|__ARITH|__HEREDOC", v):
                scope.pop(k, None)
            else:
                scope[k] = v
        return cwd
    head = ws[0]
    if head == "cd":
        if len(ws) == 1:
            return resolve(scope["HOME"], cwd) if "HOME" in scope else HOME
        return cwd if ws[1] == "-" else resolve(ws[1], cwd)
    if head == "pushd":
        target = next((w for w in ws[1:] if not w.startswith(("-", "+"))), None)
        if target is None:
            return cwd
        DIRSTACK.append(cwd)
        return resolve(target, cwd)
    if head == "popd":
        return DIRSTACK.pop() if DIRSTACK else cwd
    if head in ("export", "declare", "typeset", "local", "readonly"):
        # `export B=dev` assigns like `B=dev`, and exports: a later git sees it in its environment.
        exporting = head == "export" or any(w.startswith("-") and "x" in w for w in ws[1:])
        for w in ws[1:]:
            name, eq, value = w.partition("=")
            if w.startswith(("-", "+")) or not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", name):
                continue
            if eq:
                value = resolve_substs(value, cwd)
                taint(name, value)
                if re.search(r"[$`]|__SUBST|__ARITH|__HEREDOC", value):
                    scope.pop(name, None)
                else:
                    scope[name] = value
            if exporting:
                EXPORTED[name] = value if eq else scope.get(name, "")
        return cwd
    if head == "shopt":
        # dotglob makes a bare glob match dot files (.env* among them); track it for env_named.
        if "dotglob" in ws[1:]:
            if any(a == "-s" for a in ws[1:]):
                DOTGLOB[0] = True
            elif any(a == "-u" for a in ws[1:]):
                DOTGLOB[0] = False
        return cwd
    if head in ("for", "select") and len(ws) > 2 and ws[2] == "in":
        loops[ws[1]] = ws[3:]
        return cwd
    if head == "alias":
        for a in ws[1:]:
            name, eq, value = a.partition("=")
            if eq:
                aliases[name] = value
        return cwd
    if head in aliases:
        analyse(aliases[head] + " " + " ".join(ws[1:]), cwd, depth + 1, scope)
        return cwd
    fed = [docs[k]["body"] for k in range(len(docs)) if f"__HEREDOC{k}__" in words]
    if head in SHELLS or head in ("eval", "source", "."):
        for body in fed + [t for op, t in redirects if op == "<<<"]:
            analyse(body, cwd, depth + 1, scope)
    if (head in SHELLS or head in ("source", ".")) and before in ("|", "|&") and prev is not None and code_from_stdin(ws):
        # `echo 'cmd' | bash` and `cat <<EOF | sh` run the text on the left.
        pws, _, _, _ = peel(prev)
        piped = [docs[k]["body"] for k in range(len(docs)) if f"__HEREDOC{k}__" in prev]
        if pws and pws[0] in ("echo", "printf"):
            piped.append(ansi_decode(" ".join(a for a in pws[1:] if not re.match(r"^-[neE]+$", a))))
        for body in piped:
            analyse(body, cwd, depth + 1, scope)
        if not piped:
            block(STDIN_CODE)
    secrets(words, ws, raw, env, redirects, fed, prev, before, xargs, cwd, depth)
    check(ws, env, xargs, cwd, depth, scope)
    return cwd


def analyse(text, cwd, depth=0, scope=None):
    if depth > 6:
        return block("[safety] BLOCKED: this command nests $( ), bash -c or eval too deep to check. Flatten it.")
    subs = []
    code, docs = lex(text, subs)
    try:
        cmds = simple_commands(code)
    except ValueError:
        # A quote left open: bash refuses the command, but a quoting form the lexer does not know
        # would land here too. Close it and apply every rule rather than a few regexes.
        cmds = None
        for tail in ("'", '"', "'\"", "\"'"):
            try:
                cmds = simple_commands(code + tail)
                break
            except ValueError:
                continue
        if cmds is None:
            return plain_text_rules(text, cwd)
        out.append("WARN\tsafety-check found a quote left open in this command and checked it as if closed.")
    scope, loops, aliases, prev = dict(scope or {}), {}, {}, None
    for words, redirects, before in cmds:
        CUR_SUBS[0] = subs
        # A loop variable is checked with each value it takes, up to 16 combinations.
        combos = [{}]
        for name in [n for n in loops if loops[n] and any(refers(n, w) for w in words)]:
            combos = [dict(c, **{name: v}) for c in combos for v in loops[name]][:16]
        # A non-whitespace IFS word-splits an unquoted expansion, so `IFS=_; c=cat_.env; $c` runs
        # `cat .env`. When IFS is set to such a value, split each expanded word that came from an
        # expansion on those characters, the way bash would.
        ifs = scope.get("IFS", "")
        custom = "".join(sorted(set(ifs) - set(" \t\n"))) if ifs else ""
        next_cwd = cwd
        for n, combo in enumerate(combos):
            values = {"PWD": cwd, **scope, **combo}
            exp_words = []
            for w in words:
                ev = expand(w, values)
                if custom and "$" in w and any(ch in ev for ch in custom):
                    exp_words.extend(p for p in re.split("[" + re.escape(custom) + "]+", ev) if p != "")
                else:
                    exp_words.append(ev)
            moved = run(exp_words, [(op, expand(t, values)) for op, t in redirects],
                        before, prev, docs, cwd, depth, scope, loops, aliases, subs)
            next_cwd = moved if n == 0 else next_cwd
        cwd, prev = next_cwd, [expand(w, {"PWD": cwd, **scope}) for w in words]
    for body in subs:
        CUR_SUBS[0] = subs
        analyse(body, cwd, depth + 1, scope)


try:
    if os.environ.get("HOOK_PROBE_CRASH"):
        raise RuntimeError("hook-probes.sh asked for a crash")  # proves the next line; can only block
    mentions(CMD)
    analyse(CMD, os.path.realpath(os.environ.get("HOOK_CWD") or os.getcwd()))
except Exception as exc:  # a crash refuses the command rather than waving it through
    out.append(f"BLOCK\t[safety] BLOCKED: safety-check failed on this command ({type(exc).__name__}). "
               "Split it into simpler commands; if it must run as is, the user runs it with `!`.")


def heads_record():
    """Where PreToolUse leaves each repo's HEAD for PostToolUse, keyed by the tool call's id. The
    command text is only the fallback for input without one: another PreToolUse hook may rewrite
    the command after this hook reads it (to add a wrapper, say), and PostToolUse then sees the
    rewritten text."""
    import hashlib
    key = hashlib.sha1((SESSION + "\0" + (TOOL_USE or CMD)).encode("utf-8", "surrogateescape")).hexdigest()
    return os.path.join(STATE, SESSION, "heads", key)


def reflog_entries(data):
    """(old, new, action, subject) per HEAD reflog line. Bytes in, so no encoding can raise."""
    for raw in data.split(b"\n"):
        head, tab, msg = raw.partition(b"\t")
        ids = head.split(b" ")
        if tab and len(ids) >= 2:
            action, _, text = msg.decode("utf-8", "surrogateescape").partition(": ")
            yield ids[0].decode("ascii", "replace"), ids[1].decode("ascii", "replace"), action, " ".join(text.split())


def landed(calls):
    """COMMIT<TAB>dir<TAB>sha<TAB>base<TAB>paths for each commit this command made, read from the
    repo's HEAD reflog past the point PreToolUse recorded. Only `commit` entries count, each against
    the HEAD it moved from: the parent, the commit an --amend replaced, or nothing for a root. A
    reset, switch, pull or merge moves HEAD without one. Without a usable reflog (logging off, or
    expired meanwhile) the commits since the recorded HEAD stand in. A commit pairs with the call
    whose -m subject is its own and no other call's, else with the call at its position when the
    counts agree; one no call claims is shown without a pathspec. In a repo reached only through
    the cwd, because the command's folder could not be resolved, a commit that none of the calls'
    subjects names is left out: another session made it. No record, no line: taking HEAD as new
    reported the previous commit for a commit still running in the background."""
    try:
        with open(heads_record()) as fh:
            before = dict(line.rstrip("\n").split("\t", 1) for line in fh if "\t" in line)
        os.remove(heads_record())
    except (OSError, ValueError):
        before = {}
    lines, repos = [], {}
    for c in calls:
        repos.setdefault(git_out(c[1], "rev-parse", "--show-toplevel") or os.path.realpath(c[1]), []).append(c)
    for top, mine in repos.items():
        if top not in before:
            continue
        size, tail, head = (before[top].split(" ") + ["", ""])[:3] if before[top] else ("0", "", "")
        size, tail = int(size), bytes.fromhex(tail)
        try:
            with open(reflog_path(top), "rb") as fh:
                data = fh.read()
        except OSError:
            data = None
        if data is not None and 0 <= size <= len(data) and data[size - len(tail):size] == tail:
            made = [(new, "-" if set(old) == {"0"} else old, text)
                    for old, new, action, text in reflog_entries(data[size:]) if action.startswith("commit")]
        else:
            shas = (git_out(top, "rev-list", "--reverse", head + "..HEAD" if head else "HEAD", "--") or "").split()
            made = [(sha, shas[k - 1] if k else (head or "-"), None) for k, sha in enumerate(shas)]
        if len(made) > 20:
            made = made[-1:]
        subjects = [c[3] for c in mine]
        own = [bool(t) and subjects.count(t) == 1 for t in subjects]
        stranger = all(own) and all(c[4] for c in mine)
        claimed = set()
        for k, (sha, base, text) in enumerate(made):
            j = next((i for i in range(len(mine)) if i not in claimed and own[i] and subjects[i] == text), None)
            if j is None and len(made) == len(mine) and k not in claimed and (text is None or not own[k]):
                j = k
            if j is not None:
                claimed.add(j)
                lines.append("\t".join(["COMMIT", mine[j][1], sha, base, mine[j][2]]))
            elif text is None or not stranger:
                lines.append("\t".join(["COMMIT", top, sha, base, ""]))
    return lines


try:
    if MODE == "commits":
        calls = [line.split("\t") for line in out if line.startswith("COMMIT\t")]
        out = [line for line in out if not line.startswith("COMMIT\t")]
        out += landed(calls) if calls else []
    elif HEADS and STATE and SESSION and not any(line.startswith("BLOCK\t") for line in out):
        os.makedirs(os.path.dirname(heads_record()), exist_ok=True)
        with open(heads_record(), "w") as fh:
            fh.write("".join(f"{d}\t{sha}\n" for d, sha in HEADS.items()))
except Exception:
    pass  # a report after the fact, never a reason to refuse a command
seen = set()
for line in out:
    if line not in seen:
        seen.add(line)
        print(line)
print("END")
PY

# Capped at 8 s, and for a guard at what is left of its deadline once the fields are read.
analyze_command() {
  local session tool_use
  session="$(hook_field .session_id)"
  tool_use="$(hook_field .tool_use_id)"
  printf '%s' "$1" | PYTHONIOENCODING=utf-8:surrogateescape \
    HOOK_CWD="${2:-$PWD}" HOOK_ROOT="${ROOT:-$PWD}" HOOK_MODE="${HOOK_MODE:-check}" HOOK_DEFAULTS="$HOOK_DEFAULTS" \
    HOOK_SESSION="$session" HOOK_TOOL_USE_ID="$tool_use" HOOK_STATE="$(hook_state_dir)" \
    HOOK_OPTIN="$(hook_optin_file)" HOOK_LIB_DIR="$HOOK_LIB_DIR" \
    run_capped "$(hook_cap 8)" python3 -c "$HOOK_PY_PRELUDE"$'\n'"$HOOK_ANALYZER"
}
