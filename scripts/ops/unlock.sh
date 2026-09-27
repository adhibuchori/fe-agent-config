#!/usr/bin/env bash
# Opens one of the locks the hooks keep shut, for a few minutes, or shows or closes them:
#
#   unlock.sh env [minutes]   scripts/env/set.sh may change .env files (default 20 minutes)
#   unlock.sh db [minutes]    SQL that writes may reach the production database (default 15 minutes)
#   unlock.sh status          what is open, and until when
#   unlock.sh off [target]    lock one target now, or every target
#
# Only the user runs it: with `!` in Claude Code, or in their own terminal. The hooks refuse it,
# and its package.json alias, from the agent. docs/unlock.md explains the whole mechanism.
# A target is open while .claude/state/unlock/<target> holds a time still to come. The folder is
# private (0700) and each file 0600; an expired or malformed file counts as locked, and the next run
# removes it. Minutes run from 1 to 240. Needs bash 3.2+ and python3; no package manager.
set -euo pipefail

die() {
  printf 'unlock: %s\n' "$1" >&2
  exit 2
}

self="${BASH_SOURCE[0]}"
# A link or a copy elsewhere would compute another repo root, so only the file itself runs.
[[ ! -L "$self" ]] || die "run scripts/ops/unlock.sh itself, not a link to it."
root="$(cd "$(dirname "$self")/../.." && pwd -P)"
[[ "$self" -ef "$root/scripts/ops/unlock.sh" ]] || die "run the repo's own scripts/ops/unlock.sh, not a copy."
command -v python3 >/dev/null 2>&1 || die "python3 is required."

# The command the user typed, so the messages repeat it (npm and friends set npm_config_user_agent).
case "${npm_config_user_agent:-}" in
bun/*) run="bun unlock" ;;
pnpm/*) run="pnpm unlock" ;;
yarn/*) run="yarn unlock" ;;
npm/*) run="npm run unlock" ;;
*) run="./scripts/ops/unlock.sh" ;;
esac

python3 - "$root" "$run" "$@" <<'PY'
import os, stat, subprocess, sys, tempfile, time

root, run, args = sys.argv[1], sys.argv[2], sys.argv[3:]
if os.stat(os.path.join(root, "scripts", "ops", "unlock.sh")).st_nlink != 1:
    print("unlock: scripts/ops/unlock.sh has another hard link; remove the link, then run this again.", file=sys.stderr)
    sys.exit(2)
# target: (default minutes, what it opens)
TARGETS = {"env": (20, ".env"), "db": (15, "db writes")}
LONGEST = 240
state = os.path.join(root, ".claude", "state")
folder = os.path.join(state, "unlock")
USAGE = f"""usage: {run} <env|db> [minutes] | status | off [env|db]
  env [minutes]  let scripts/env/set.sh change .env files (default 20 minutes, at most {LONGEST})
  db [minutes]   let SQL that writes reach the production database (default 15 minutes)
  status         what is open, and until when
  off [target]   lock one target now, or every target"""


def fail(message):
    print(f"unlock: {message}", file=sys.stderr)
    sys.exit(2)


def until(target):
    """The epoch target's unlock ends at, or 0: the rules of unlock_until in .claude/hooks/lib.sh."""
    uid = os.geteuid()
    try:
        for d in (state, folder):
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
                or not text.rstrip(b"\n").isdigit() or text.count(b"\n") > 1 or len(text) > 13):
            return 0
        end, now = int(text), time.time()
        if end <= now or end > now + LONGEST * 60 + 60 or end > info.st_mtime + LONGEST * 60 + 60:
            return 0
    except (OSError, ValueError):
        return 0
    tracked = subprocess.run(["git", "-C", root, "ls-files", "--", os.path.join(folder, target)],
                             capture_output=True, text=True)
    return 0 if tracked.returncode == 0 and tracked.stdout.strip() else end


def clock(epoch):
    """14:32, or Tue 00:10 when the time falls on another day."""
    when = time.localtime(epoch)
    return time.strftime("%H:%M" if when[:3] == time.localtime()[:3] else "%a %H:%M", when)


def left(epoch):
    return max(1, -(-int(epoch - time.time()) // 60))


def prune():
    """Removes whatever in the folder is not a live token: expired, malformed or unknown files."""
    if not os.path.isdir(folder) or os.path.islink(folder):
        return
    for name in os.listdir(folder):
        path = os.path.join(folder, name)
        if name in TARGETS and until(name):
            continue
        if os.path.islink(path) or not os.path.isdir(path):
            os.unlink(path)


def ensure_folder():
    for d in (os.path.join(root, ".claude"), state, folder):
        if os.path.islink(d):
            fail(f"{os.path.relpath(d, root)} is a symbolic link; remove it, then run this again.")
    os.makedirs(folder, mode=0o700, exist_ok=True)
    for d in (state, folder):
        if os.lstat(d).st_uid != os.geteuid():
            fail(f"{os.path.relpath(d, root)} belongs to another user.")
        os.chmod(d, 0o700)


def ignored():
    probe = os.path.join(folder, "env")
    r = subprocess.run(["git", "-C", root, "check-ignore", "-q", "--no-index", probe], capture_output=True)
    return r.returncode != 1  # 0 ignored; 128 not a git repo, where nothing can be committed


def open_target(target, minutes):
    ensure_folder()
    prune()
    end = int(time.time()) + minutes * 60
    fd, tmp = tempfile.mkstemp(dir=folder, prefix=".new-")
    try:
        os.write(fd, f"{end}\n".encode())
        os.fsync(fd)
    finally:
        os.close(fd)
    os.replace(tmp, os.path.join(folder, target))
    if until(target) != end:
        os.unlink(os.path.join(folder, target))
        fail(f"could not open {target}: .claude/state/unlock/{target} is tracked by git or not private. "
             "Untrack it (git rm --cached) and check the folder's owner.")
    label = TARGETS[target][1]
    print(f"🔓 {label} unlocked until {clock(end)} ({minutes} min) — lock now: {run} off {target}")
    if not ignored():
        print("   note: .claude/state/ is not in .gitignore; add it so unlock files and .env backups are never committed.")


def status():
    prune()
    for target, (_, label) in TARGETS.items():
        end = until(target)
        if end:
            print(f"🔓 {target:<3}  {label} open until {clock(end)} ({left(end)} min left) — lock now: {run} off {target}")
        else:
            print(f"🔒 {target:<3}  {label} locked")


def off(targets):
    for target in targets:
        path = os.path.join(folder, target)
        if os.path.lexists(path) and not os.path.isdir(path) and not os.path.islink(folder):
            os.unlink(path)
    prune()
    if len(targets) == 1:
        print(f"🔒 {TARGETS[targets[0]][1]} locked")
    else:
        print(f"🔒 everything locked ({', '.join(TARGETS)})")


if not args:
    fail("say what to unlock.\n" + USAGE)
cmd, rest = args[0], args[1:]
if cmd in ("-h", "--help", "help"):
    print(USAGE)
elif cmd in TARGETS:
    if len(rest) > 1:
        fail(f"too many arguments.\n{USAGE}")
    text = rest[0] if rest else str(TARGETS[cmd][0])
    if not (text.isascii() and text.isdigit()) or not 1 <= int(text) <= LONGEST:
        fail(f'minutes must be a whole number from 1 to {LONGEST}, not "{text}".')
    open_target(cmd, int(text))
elif cmd == "status":
    if rest:
        fail(f"status takes no arguments.\n{USAGE}")
    status()
elif cmd == "off":
    if len(rest) > 1 or (rest and rest[0] not in TARGETS):
        fail(f"off takes one target ({', '.join(TARGETS)}) or none, not \"{' '.join(rest)}\".")
    off(rest or list(TARGETS))
else:
    fail(f'unknown target "{cmd}". Targets: {", ".join(TARGETS)}; also status and off.\n{USAGE}')
PY
