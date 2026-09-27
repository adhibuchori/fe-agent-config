#!/usr/bin/env bash
# PreToolUse(the production database's SQL tool): read-only SQL passes; SQL that may write runs only
# while the user has unlocked db (scripts/ops/unlock.sh db; docs/unlock.md). The tool is
# dbWriteGuard.toolPattern in .claude/agent-config.json (a regex matched against the whole tool
# name; default mcp__db-prod__execute_sql). Wire this hook with a matcher that covers it.
#
# Read-only is one statement of SELECT, SHOW, VALUES, TABLE, DESCRIBE, WITH ... SELECT with no
# data-modifying part, or EXPLAIN (EXPLAIN ANALYZE runs its statement, so only of a read). A
# SELECT with INTO, FOR UPDATE or FOR SHARE, or a call to a built-in function that changes state
# or reaches outside the tables (setval, pg_terminate_backend, dblink, pg_read_file, ...) is a write. So is anything else: more than one
# statement, a comment holding a semicolon or another comment, quoting that databases read
# differently (dollar quotes, backticks, #, a backslash that splits a string differently where it
# escapes), and SQL that does not parse. A SELECT calling a
# function of your own that writes cannot be told from its text: keep the server in read-only mode
# (postgres-mcp --access-mode=restricted) as the layer below.
#
# A call to any other tool passes before python3 is needed: jq reads the tool name and the pattern,
# and bash matches them (db_tool_miss), so the plugin's wiring on every MCP tool never refuses an
# unrelated call on a machine without python3.
#
# Fails closed: a payload it cannot read, or, for the SQL tool (or a call it cannot rule out as
# another tool's), no python3 or a check that does not finish within 5 s refuses the call, reads
# included.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_start guard "[db-guard]"

# dbWriteGuard.toolPattern as load_config reads it: the one agent-config.json sets when usable, else
# the default. Status 1 when jq is missing or cannot read the file as python3 would (it is not
# JSON, or not UTF-8), so python3 decides.
db_pattern() {
  local file="$ROOT/.claude/agent-config.json"
  command -v jq &>/dev/null || return 1
  if [[ ! -e "$file" ]]; then
    jq -rn --argjson d "$HOOK_DEFAULTS" '$d.dbWriteGuard.toolPattern'
    return
  fi
  # shellcheck disable=SC2016 # $d and $default are jq variables
  jq -Rrs --argjson d "$HOOK_DEFAULTS" '$d.dbWriteGuard.toolPattern as $default
    | if test("\ufffd") then error("not UTF-8") else fromjson end
    | if type != "object" or (has("dbWriteGuard") | not) or (.dbWriteGuard | type) != "object" then $default
      else (.dbWriteGuard | with_entries(select(.key | startswith("//") | not))) as $f
        | if ($f | keys) == ["toolPattern"] and ($f.toolPattern | type) == "string" then $f.toolPattern
          else $default end
      end' <"$file" 2>/dev/null
}

# 0 when the call is certainly not to the SQL tool. Only a pattern of plain names, | and balanced
# ( ) is matched here, since bash (POSIX ERE) and python3 read that alike as a whole-name match;
# any other pattern, or a name jq cannot read, is left to python3.
db_tool_miss() {
  local tool pattern re rest depth=0 rc
  command -v jq &>/dev/null || return 1
  tool="$(jq -r 'if (.tool_name | type) == "string" then .tool_name else error("no tool name") end' <<<"$HOOK_INPUT" 2>/dev/null)" ||
    return 1
  pattern="$(db_pattern)" || return 1
  re='^[A-Za-z0-9_|()-]+$'
  [[ "$pattern" =~ $re ]] || return 1
  rest="$pattern"
  while [[ -n "$rest" ]]; do
    case "${rest:0:1}" in
    "(") depth=$((depth + 1)) ;;
    ")") depth=$((depth - 1)) ;;
    esac
    [[ "$depth" -ge 0 ]] || return 1
    rest="${rest:1}"
  done
  [[ "$depth" -eq 0 ]] || return 1
  re="^(${pattern})\$"
  # 1 is a clean miss; 2, a pattern this bash cannot compile, is no answer.
  [[ "$tool" =~ $re ]]
  rc=$?
  [[ "$rc" -eq 1 ]]
}

db_tool_miss && exit 0
command -v python3 &>/dev/null || hook_fail "db-guard reads SQL with python3, which is not installed."

read -r -d '' DB_PY <<'PY'
READ_FIRST = {"SELECT", "WITH", "EXPLAIN", "SHOW", "VALUES", "TABLE", "DESCRIBE", "DESC"}
# Words that make a read statement write wherever they stand outside quotes: a data-modifying CTE,
# SELECT ... INTO, FOR UPDATE.
WRITES_ANYWHERE = {"INSERT", "UPDATE", "DELETE", "MERGE", "UPSERT", "TRUNCATE", "DROP", "ALTER", "CREATE", "GRANT",
                   "REVOKE", "INTO", "COPY"}
SIDE_EFFECTS = re.compile(
    r"NEXTVAL|SETVAL|SET_CONFIG|TXID_CURRENT|PG_CURRENT_XACT_ID|PG_TERMINATE_BACKEND|PG_CANCEL_BACKEND"
    r"|PG_RELOAD_CONF|PG_ROTATE_LOGFILE|PG_SWITCH_WAL|PG_PROMOTE|PG_(TRY_)?ADVISORY\w*|LO_\w+|DBLINK\w*"
    r"|PG_FILE_\w+|PG_READ_\w*FILE|PG_LS_\w+|PG_STAT_RESET\w*|PG_CREATE_\w+|PG_DROP_\w+|PG_REPLICATION_\w+"
    r"|PG_LOGICAL_\w+|PG_NOTIFY|PG_SLEEP\w*|QUERY_TO_\w+|CURSOR_TO_\w+|PG_IMPORT_\w+|PG_BACKUP_\w+"
    r"|PG_LOG_\w+|PG_COPY_\w+|PG_WAL_REPLAY_\w+")
WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_$]*")


class Unsure(Exception):
    """SQL this check cannot read the way every database would: treated as a write."""


def statements(sql, backslash=False):
    """Each statement's tokens, (kind, text), with comments and quoted text reduced to one token.
    With backslash, a backslash escapes in every string, as MySQL and a PostgreSQL server with
    standard_conforming_strings off read it. Raises Unsure on what could hide a statement."""
    out, cur, i, n = [], [], 0, len(sql)
    while i < n:
        c = sql[i]
        if c.isspace():
            i += 1
        elif sql.startswith("--", i):
            j = sql.find("\n", i)
            j = n if j < 0 else j
            if ";" in sql[i:j]:
                raise Unsure("a comment holds a semicolon")
            i = j
        elif sql.startswith("/*", i):
            j = sql.find("*/", i + 2)
            if j < 0:
                raise Unsure("a comment is never closed")
            body = sql[i + 2:j]
            if "/*" in body or ";" in body or body.startswith("!"):
                raise Unsure("a comment holds a semicolon, another comment or MySQL code")
            i = j + 2
        elif c == "'":
            # E'...' takes backslash escapes; everywhere else '' is the only escape.
            prefixed = bool(cur) and cur[-1] == ("word", "E") and sql[i - 1] in "eE"
            if prefixed:
                cur.pop()
            escapes = prefixed or backslash
            j = i + 1
            while j < n:
                if escapes and sql[j] == "\\":
                    j += 2
                elif sql.startswith("''", j):
                    j += 2
                elif sql[j] == "'":
                    break
                else:
                    j += 1
            if j >= n:
                raise Unsure("a string is never closed")
            cur.append(("string", ""))
            i = j + 1
        elif c == '"':
            j = i + 1
            while j < n and not (sql[j] == '"' and not sql.startswith('""', j)):
                j += 2 if sql.startswith('""', j) or (backslash and sql[j] == "\\") else 1
            if j >= n:
                raise Unsure("a quoted name is never closed")
            cur.append(("name", sql[i + 1:j]))
            i = j + 1
        elif c == "$" and re.match(r"\$([A-Za-z_][A-Za-z0-9_]*)?\$", sql[i:]):
            raise Unsure("a dollar-quoted string")
        elif c == "`":
            raise Unsure("a backtick-quoted name")
        elif c == "#" and not sql.startswith(("#>", "#-"), i):
            raise Unsure("a # that some databases read as a comment")
        elif c == "\\":
            raise Unsure("a backslash outside a string")
        elif c == ";":
            if cur:
                out.append(cur)
            cur = []
            i += 1
        else:
            m = WORD.match(sql, i)
            if m:
                cur.append(("word", m.group(0).upper()))
                i = m.end()
            else:
                cur.append(("op", c))
                i += 1
    if cur:
        out.append(cur)
    return out


def writes(tokens):
    """Why one statement may write, or "" when it only reads."""
    k = 0
    while k < len(tokens) and tokens[k] == ("op", "("):
        k += 1
    words = [t for kind, t in tokens if kind == "word"]
    first = tokens[k][1] if k < len(tokens) and tokens[k][0] == "word" else ""
    if first not in READ_FIRST:
        return f"{'an' if first[:1] in 'AEIOU' else 'a'} {first} statement" if first else "something other than a statement"
    if first == "EXPLAIN":
        rest, analyze = tokens[k + 1:], False
        if rest and rest[0] == ("op", "("):
            depth, j = 0, 0
            for j, t in enumerate(rest):
                depth += {("op", "("): 1, ("op", ")"): -1}.get(t, 0)
                if t in (("word", "ANALYZE"), ("word", "ANALYSE")):
                    nxt = rest[j + 1] if j + 1 < len(rest) else ("op", ",")
                    analyze = analyze or nxt[1] not in ("FALSE", "OFF", "0")
                if depth == 0:
                    break
            rest = rest[j + 1:]
        while rest and rest[0][0] == "word" and rest[0][1] in ("ANALYZE", "ANALYSE", "VERBOSE"):
            analyze = analyze or rest[0][1] != "VERBOSE"
            rest = rest[1:]
        if not analyze:
            return ""
        why = writes(rest)
        return f"EXPLAIN ANALYZE runs {why}" if why else ""
    if first in ("SHOW", "DESCRIBE", "DESC", "TABLE"):
        return ""
    for word in words:
        if word in WRITES_ANYWHERE:
            return "INTO in a SELECT, which creates a table" if word == "INTO" else f"{word} inside a {first}"
    for j, (kind, text) in enumerate(tokens):
        if kind == "word" and text in ("UPDATE", "SHARE") and j and tokens[j - 1][1] in ("FOR", "KEY"):
            return f"FOR {text}, which locks rows"
        nxt = tokens[j + 1] if j + 1 < len(tokens) else None
        # A quoted or schema-qualified name ("setval"(...), pg_catalog."setval"(...)) is a call too:
        # name tokens keep their case, so compare upper-cased.
        if kind in ("word", "name") and nxt == ("op", "(") and SIDE_EFFECTS.fullmatch(text.upper()):
            return f"{text.lower()}(), which changes state or reaches outside the tables"
    return ""


def verdict(sql):
    if not isinstance(sql, str) or not sql.strip():
        return "no SQL text this check can read"
    try:
        found = statements(sql)
        # A string holding a backslash must split the same way whichever rule the server uses.
        if "\\" in sql and statements(sql, backslash=True) != found:
            return "a backslash in a string, which databases read differently"
    except Unsure as why:
        return str(why)
    if not found:
        return "no statement"
    if len(found) > 1:
        return f"{len(found)} statements in one call"
    return writes(found[0])


data = json.loads(sys.stdin.buffer.read())
root = sys.argv[1]
cfg, _ = load_config(root)
tool = data.get("tool_name") or ""
if not re.fullmatch(cfg["dbWriteGuard"]["toolPattern"], tool):
    print("SKIP")
    sys.exit(0)
given = data.get("tool_input") if isinstance(data.get("tool_input"), dict) else {}
sql = next((given[k] for k in ("sql", "query", "statement") if isinstance(given.get(k), str)), None)
why = verdict(sql)
if not why:
    print("READ")
    sys.exit(0)
end = unlock_until(root, "db")
if end:
    print(f"OPEN\tThe user has unlocked database writes until {time.strftime('%H:%M', time.localtime(end))}, so this "
          f"call, which may write ({why}), runs now. Tell the user what it changed.")
else:
    print(f"BLOCK\t[db-guard] BLOCKED: this SQL may change the production database ({why}). Reads (one SELECT, SHOW, "
          f"VALUES, EXPLAIN, or WITH ... SELECT) pass. For a write, the user runs `{unlock_hint(root, 'db')}` "
          "themselves and you try again, or you hand them the statement to run.")
PY

VERDICT="$(HOOK_DEFAULTS="$HOOK_DEFAULTS" run_capped "$(hook_cap 5)" python3 -c "$HOOK_PY_PRELUDE"$'\n'"$DB_PY" "$ROOT" <<<"$HOOK_INPUT" 2>/dev/null)"
case "$VERDICT" in
SKIP | READ) exit 0 ;;
OPEN*)
  report "${VERDICT#*$'\t'}" PreToolUse
  exit 0
  ;;
BLOCK*) block "${VERDICT#*$'\t'}" ;;
esac
hook_fail "the SQL check did not finish (python3 failed or took over 5 s)."
