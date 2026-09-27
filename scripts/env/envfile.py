"""Reads and changes .env files without printing their secrets (docs/unlock.md).

Run through scripts/env/show.sh and scripts/env/set.sh:

  show <file>        every key; plain settings (booleans, numbers, host names, URLs without
                     credentials, short words) in clear, everything else masked as
                     <first 4>…(<length> chars); then the keys that differ from the template
  set <file> <KEY>   the value arrives on stdin; needs the user's env unlock

python3 3.8+, standard library only. The unlock rules match unlock_until in .claude/hooks/lib.sh.
"""
import datetime
import fcntl
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import time

ROOT = os.path.realpath(os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", ".."))
STATE = os.path.join(ROOT, ".claude", "state")
LONGEST = 240 * 60
KEEP_BACKUPS = 20

# A key whose value is masked whatever it looks like. Wide on purpose: over-masking is harmless,
# printing a secret is not.
SECRET_KEY = re.compile(
    r"SECRET|TOKEN|KEY|PASSWORD|PASS|PWD?(_|$)|PRIVATE|CREDENTIAL|DSN|AUTH|SALT|WEBHOOK|SIGN|SESSION"
    r"|ENCRYPT|CIPHER|HMAC|SEED|COOKIE|CERT|OTP|PIN", re.I)
# Keys whose value is always shown in clear: they never hold a secret.
PUBLIC_KEYS = {"NODE_ENV", "PORT", "HOST", "LOG_LEVEL", "TZ", "APP_ENV", "ENVIRONMENT"}
BOOLEAN = re.compile(r"(true|false|yes|no|on|off|none|null|nil)\Z", re.I)
NUMBER = re.compile(r"-?[0-9]{1,12}(\.[0-9]{1,12})?\Z")
# A duration (30s, 5m, 1h30m, 100ms, 7d) and a log level: plain settings, not secrets.
DURATION = re.compile(r"(\d+(\.\d+)?\s*(ns|us|µs|ms|s|m|h|d|w))+\Z", re.I)
LOG_LEVEL = re.compile(r"(trace|debug|info|warn|warning|error|fatal|silent|verbose|notice|critical|off)\Z", re.I)
HOST = re.compile(r"(localhost|[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+|\[[0-9A-Fa-f:.]+\])(:[0-9]{1,5})?\Z")
URL = re.compile(r"(?P<scheme>[A-Za-z][A-Za-z0-9+.-]*://)(?:(?P<userinfo>[^@/?#]*)@)?(?P<rest>[^?#]*)"
                 r"(?P<query>\?[^#]*)?(?P<fragment>#.*)?\Z", re.S)
LINE = re.compile(r"(?P<lead>[ \t]*)(?P<export>export[ \t]+)?(?P<key>[A-Za-z_][A-Za-z0-9_.-]*)(?P<eq>[ \t]*=[ \t]*)"
                  r"(?P<rest>.*)\Z", re.S)
KEY_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")
# A value written without quotes: nothing a parser could read as a quote, comment, escape or variable.
BARE = re.compile(r"[A-Za-z0-9_./:@%+,=~^-]*\Z")


class Refusal(Exception):
    """A request this tool turns down: exit 2 and the message, the file untouched."""


# ---- Masking ----

def mask(text):
    """<first 4>…(<length> chars); below 12 characters the start is left out too."""
    n = len(text)
    unit = "char" if n == 1 else "chars"
    return f"{text[:4]}…({n} {unit})" if n >= 12 else f"…({n} {unit})"


def looks_random(text):
    letters = sum(c.isalpha() for c in text)
    digits = sum(c.isdigit() for c in text)
    cases = any(c.islower() for c in text) and any(c.isupper() for c in text)
    return ((len(text) >= 16 and letters and digits >= 2) or (len(text) >= 12 and cases and digits)
            or bool(re.fullmatch(r"[A-Fa-f0-9]{16,}|[A-Za-z0-9+/_=-]{24,}", text)))


def plain(text):
    """Whether a value is clearly non-secret by shape: a boolean, a number, a duration, a log
    level, or a host name (no userinfo). Everything else is masked by default."""
    if BOOLEAN.match(text) or NUMBER.match(text) or DURATION.match(text) or LOG_LEVEL.match(text):
        return True
    if HOST.match(text):
        # A dotted token (a JWT, say) has the shape of a host name: every label must read as a word,
        # and the last one as a top-level domain or part of an IP address.
        labels = re.sub(r":[0-9]+\Z", "", text).strip("[]").split(".")
        if text.startswith("[") or text.startswith("localhost") or all(x.isdigit() for x in labels):
            return True
        return labels[-1].isalpha() and all(len(x) <= 63 and not looks_random(x) for x in labels)
    return False


def shown_url(m):
    """A URL with its credentials, secret-looking path parts and secret query values masked."""
    parts = [m.group("scheme")]
    if m.group("userinfo") is not None:
        parts.append(mask(m.group("userinfo")) + "@")
    host, slash, path = m.group("rest").partition("/")
    parts.append(host + slash + "/".join(mask(p) if p and looks_random(p) else p for p in path.split("/")))
    if m.group("query"):
        pairs = []
        for pair in m.group("query")[1:].split("&"):
            name, eq, value = pair.partition("=")
            secret = value and (SECRET_KEY.search(name) or looks_random(value))
            pairs.append(name + eq + (mask(value) if secret else value))
        parts.append("?" + "&".join(pairs))
    if m.group("fragment"):
        parts.append("#" + mask(m.group("fragment")[1:]))
    return "".join(parts)


def shown(key, value):
    """What show and set print for a value: masked by default, cleared only when it is clearly not
    a secret (a public-allowlist key, or a value whose shape holds no secret)."""
    if value == "":
        return "(empty)"
    if "\n" in value or "\r" in value or SECRET_KEY.search(key):
        return mask(value)
    if key.upper() in PUBLIC_KEYS:
        return value
    m = URL.match(value)
    if m:
        return shown_url(m)
    return value if plain(value) else mask(value)


# ---- Parsing ----

def closing(text, quote):
    """Index of the quote that closes a value opened by quote, or -1. Inside double quotes a
    backslash escapes the next character."""
    i = 0
    while i < len(text):
        if quote == '"' and text[i] == "\\":
            i += 2
            continue
        if text[i] == quote:
            return i
        i += 1
    return -1


def unescape(text):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "r": "\r", "t": "\t"}.get(m.group(1), m.group(1)), text, flags=re.S)


def parse(lines):
    """The entries of a .env file split into lines (line endings kept): for each KEY=VALUE a dict
    with its first and last line, key, value, quote and the text around the value; for a line that
    is not one, {"bad": line}. Blank lines and # comments are skipped."""
    entries, i = [], 0
    while i < len(lines):
        line = lines[i].rstrip("\r\n")
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        m = LINE.match(line)
        if m is None:
            entries.append({"bad": i})
            i += 1
            continue
        rest, j = m.group("rest"), i
        quote = rest[:1] if rest[:1] in ("'", '"', "`") else ""
        if quote:
            body = rest[1:]
            end = closing(body, quote)
            while end < 0 and j + 1 < len(lines):
                j += 1
                body += "\n" + lines[j].rstrip("\r\n")
                end = closing(body, quote)
            tail = body[end + 1:] if end >= 0 else ""
            if end < 0 or (tail.strip() and not tail.lstrip().startswith("#")):
                entries.append({"bad": i})
                i += 1
                continue
            value = unescape(body[:end]) if quote == '"' else body[:end]
        else:
            hash_at = re.search(r"[ \t]#", rest)
            value, tail = (rest[:hash_at.start()], rest[hash_at.start():]) if hash_at else (rest, "")
            value = value.rstrip(" \t")
        entries.append({"first": i, "last": j, "key": m.group("key"), "value": value, "quote": quote, "tail": tail,
                        "prefix": m.group("lead") + (m.group("export") or "") + m.group("key") + m.group("eq")})
        i = j + 1
    return entries


def read_lines(path):
    with open(path, "rb") as fh:
        data = fh.read()
    return data.decode("utf-8", "surrogateescape").splitlines(keepends=True)


# ---- The unlock ----

def unlocked(target):
    """The epoch the user's unlock of target ends at, or 0 while it is locked."""
    uid = os.geteuid()
    folder = os.path.join(STATE, "unlock")
    try:
        for d in (STATE, folder):
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
        end, now = int(text), time.time()
        if end <= now or end > now + LONGEST + 60 or end > info.st_mtime + LONGEST + 60:
            return 0
    except (OSError, ValueError):
        return 0
    tracked = subprocess.run(["git", "-C", ROOT, "ls-files", "--", os.path.join(folder, target)],
                             capture_output=True, text=True)
    return 0 if tracked.returncode == 0 and tracked.stdout.strip() else end


def unlock_hint(target):
    """What the user types to unlock target in this repo (unlock_hint in .claude/hooks/lib.sh)."""
    try:
        with open(os.path.join(ROOT, "package.json"), encoding="utf-8") as fh:
            scripts = json.load(fh).get("scripts") or {}
    except (OSError, ValueError, AttributeError):
        scripts = {}
    if isinstance(scripts, dict) and "unlock" in scripts:
        for lock, run in (("bun.lock", "bun unlock"), ("bun.lockb", "bun unlock"), ("pnpm-lock.yaml", "pnpm unlock"),
                          ("yarn.lock", "yarn unlock")):
            if os.path.exists(os.path.join(ROOT, lock)):
                return f"! {run} {target}"
        return f"! npm run unlock {target}"
    return f"! ./scripts/ops/unlock.sh {target}"


# ---- show ----

def env_file(path, template_ok):
    name = os.path.basename(path)
    if not re.match(r"\.env(rc)?([._-]|\Z)", name, re.I):
        raise Refusal(f"{path} is not a .env* file.")
    if ".example" in name.lower() and not template_ok:
        raise Refusal(f"{path} is a template: edit it directly, it holds no secrets.")


def template_for(path):
    """The template a .env file is checked against: <file>.example, else the same without .local."""
    d, name = os.path.split(path)
    names = [name + ".example"]
    if name.endswith(".local"):
        names.append(name[:-len(".local")] + ".example")
    for n in names:
        if os.path.isfile(os.path.join(d, n)):
            return os.path.join(d, n)
    return ""


def show(path):
    env_file(path, template_ok=True)
    if not os.path.isfile(path):
        raise Refusal(f"{path} does not exist.")
    lines = read_lines(path)
    entries = parse(lines)
    pairs = [e for e in entries if "key" in e]
    keys = []
    for e in pairs:
        if e["key"] not in keys:
            keys.append(e["key"])
    last = {e["key"]: e for e in pairs}
    width = min(max((len(k) for k in keys), default=0), 32)
    print(f"{path}: {len(keys)} {'key' if len(keys) == 1 else 'keys'}")
    for k in keys:
        print(f"  {k:<{width}}  {shown(k, last[k]['value'])}")
    for k in keys:
        at = [str(e["first"] + 1) for e in pairs if e["key"] == k]
        if len(at) > 1:
            print(f"  note: {k} is set {len(at)} times (lines {', '.join(at)}); the last one counts.")
    for e in entries:
        if "bad" in e:
            print(f"  note: line {e['bad'] + 1} is not KEY=VALUE, so it is not shown.")
    missing = []
    template = "" if ".example" in os.path.basename(path).lower() else template_for(path)
    if template:
        wanted = [e["key"] for e in parse(read_lines(template)) if "key" in e]
        missing = [k for k in wanted if k not in last]
        extra = [k for k in keys if k not in wanted]
        print(f"checked against {template}: "
              + ("every key present" if not missing else "missing " + ", ".join(missing))
              + ("; not in the template: " + ", ".join(extra) if extra else ""))
    end = unlocked("env")
    if end:
        print(f"env is unlocked until {time.strftime('%H:%M', time.localtime(end))}: scripts/env/set.sh may change it.")
    else:
        print(f"env is locked: to change a value, the user first runs `{unlock_hint('env')}`.")
    return 1 if missing else 0


# ---- set ----

def render(value, quote):
    """The value as written in the file: in its old quoting when that holds it unchanged, else in
    the plainest quoting every common parser reads back literally. Single quotes come first among
    the fallbacks, so a single-quoted (or backtick-quoted) value stays single-quoted."""
    if "\r" in value or "\0" in value:
        raise Refusal("the value holds a carriage return or a NUL byte; the user edits this one by hand.")
    single = "'" not in value and "\n" not in value
    double = not re.search(r'["\\$`]', value)
    if quote == '"' and double:
        return '"' + value.replace("\n", "\\n") + '"'
    if not quote and BARE.match(value):
        return value
    if single:
        return f"'{value}'"
    if double:
        return '"' + value.replace("\n", "\\n") + '"'
    raise Refusal("the value mixes quotes, backslashes or $ with line breaks, which no quoting keeps intact in "
                  "every .env reader; the user edits this one by hand.")


def git_ignores(path):
    r = subprocess.run(["git", "-C", ROOT, "check-ignore", "-q", "--no-index", path], capture_output=True)
    return r.returncode != 1  # 0: ignored; 128: not a git repo, where nothing is committed


def private_dir(path):
    os.makedirs(path, mode=0o700, exist_ok=True)
    if os.path.islink(path):
        raise Refusal(f"{os.path.relpath(path, ROOT)} is a symbolic link.")
    os.chmod(path, 0o700)


def backup(path, rel):
    """Copies the file to .claude/state/env-backups/<its folder>/<its name>.<time> (0600, in 0700
    folders), so every backup keeps a .env* name, and keeps the newest KEEP_BACKUPS of each file."""
    folder = os.path.join(STATE, "env-backups")
    private_dir(STATE)
    private_dir(folder)
    for part in os.path.dirname(rel).split(os.sep) if os.path.dirname(rel) else []:
        folder = os.path.join(folder, part)
        private_dir(folder)
    stem = os.path.basename(rel)
    stamp = datetime.datetime.now().strftime("%Y%m%dT%H%M%S")
    for n in range(100):
        target = os.path.join(folder, f"{stem}.{stamp}" + (f"-{n}" if n else ""))
        try:
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            break
        except FileExistsError:
            continue
    else:
        raise Refusal("could not name a backup file.")
    with open(path, "rb") as src, os.fdopen(fd, "wb") as dst:
        dst.write(src.read())
    olds = sorted(f for f in os.listdir(folder) if f.startswith(stem + "."))
    for f in olds[:-KEEP_BACKUPS]:
        os.unlink(os.path.join(folder, f))
    return target


def write_atomic(path, data, mode):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix="." + os.path.basename(path) + ".")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def set_value(path, key):
    env_file(path, template_ok=False)
    if not KEY_NAME.match(key):
        raise Refusal(f'"{key}" is not a key name (letters, digits and _, not starting with a digit).')
    full = os.path.abspath(path)
    if not (os.path.realpath(os.path.dirname(full)) + os.sep).startswith(ROOT + os.sep):
        raise Refusal(f"{path} is outside this repo.")
    if os.path.islink(full):
        raise Refusal(f"{path} is a symbolic link; the user edits its target.")
    if os.path.exists(full) and not os.path.isfile(full):
        raise Refusal(f"{path} is not a regular file.")
    if not unlocked("env"):
        raise Refusal(f"🔒 .env files are locked. Ask the user to run `{unlock_hint('env')}` themselves, then run "
                      "this again.")
    if not git_ignores(os.path.join(STATE, "env-backups", "probe")):
        raise Refusal(".claude/state/ is not in .gitignore, and the backup of this file would hold its secrets. "
                      "Add .claude/state/ to .gitignore first.")
    if sys.stdin.isatty():
        raise Refusal("pipe the value in on stdin, for example: printf '%s' \"$VALUE\" | bash scripts/env/set.sh "
                      f"{path} {key}")
    raw = sys.stdin.buffer.read().decode("utf-8", "surrogateescape")
    value = raw[:-1] if raw.endswith("\n") else raw
    rel = os.path.relpath(os.path.realpath(full), ROOT)
    private_dir(STATE)
    with open(os.path.join(STATE, "env-set.lock"), "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        exists = os.path.exists(full)
        lines = read_lines(full) if exists else []
        newline = "\r\n" if any(line.endswith("\r\n") for line in lines) else "\n"
        entries = [e for e in parse(lines) if e.get("key") == key]
        for e in reversed(entries):
            text = e["prefix"] + render(value, e["quote"]) + e["tail"] + newline
            lines[e["first"]:e["last"] + 1] = [text]
        if not entries:
            if lines and not lines[-1].endswith("\n"):
                lines[-1] += newline
            lines.append(f"{key}={render(value, '')}{newline}")
        data = "".join(lines).encode("utf-8", "surrogateescape")
        check = {e["key"]: e["value"] for e in parse(data.decode("utf-8", "surrogateescape").splitlines(keepends=True))
                 if "key" in e}
        if check.get(key) != value:
            raise Refusal("the new line would not read back as the value given; nothing was changed.")
        saved = backup(full, rel) if exists else ""
        write_atomic(full, data, stat.S_IMODE(os.stat(full).st_mode) if exists else 0o600)
        log = os.path.join(STATE, "env-audit.log")
        fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "a") as fh:
            when = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
            fh.write(f"{when}\tset\t{rel}\t{key}\t{'updated' if entries else 'added'}\n")
    action = f"updated ({len(entries)} lines)" if len(entries) > 1 else "updated" if entries else "added"
    note = f" · backup {os.path.relpath(saved, os.getcwd())}" if saved else ""
    print(f"✓ {key} {action} in {path}: {shown(key, value)}{note}")
    return 0


def main(argv):
    usage = {"show": "usage: bash scripts/env/show.sh <.env file>",
             "set": "usage: printf '%s' \"$VALUE\" | bash scripts/env/set.sh <.env file> <KEY>"}
    cmd = argv[1] if len(argv) > 1 else ""
    try:
        if cmd == "show" and len(argv) == 3:
            return show(argv[2])
        if cmd == "set" and len(argv) == 4:
            return set_value(argv[2], argv[3])
        raise Refusal(usage.get(cmd, "usage: envfile.py show <file> | set <file> <KEY>"))
    except Refusal as why:
        print(f"{'show.sh' if cmd == 'show' else 'set.sh' if cmd == 'set' else 'envfile.py'}: {why}", file=sys.stderr)
        return 2
    except OSError as why:
        print(f"envfile.py: {why.strerror}: {why.filename}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
