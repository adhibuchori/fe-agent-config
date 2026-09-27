#!/usr/bin/env bash
# Proves the MCP pin rule of scripts/check/ai-config.sh (check 4) both ways: every spec marked
# "pinned" below names one release and must pass, and every spec marked "unpinned" can move under
# the repo (a bare name, a tag, a range, a major-only or major.minor version, a short commit SHA)
# and must be named. The cases run through the real ai-config.sh in a temp repo that holds only
# .claude/ and the MCP files, so this repo is never read or touched.
#
#   bash scripts/check/ai-config-probes.sh
#
# Exit 0 when every case holds, 1 when one does not, 2 when it cannot run. Needs bash 3.2+ and
# python3, which check 4 itself needs. Run it with /bin/bash on macOS to prove 3.2.
set -uo pipefail
# A pathspec commit hands pre-commit its own git environment; the temp repos below must not see it.
unset GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
cd "$(dirname "$0")/../.." || exit 2
[ -f scripts/check/ai-config.sh ] || { echo "scripts/check/ai-config.sh not found" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "::error::python3 is required" >&2; exit 2; }

TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# git stops at $TMP, so a temp folder inside some other checkout is never read as a work tree.
export GIT_CEILING_DIRECTORIES="$TMP"
SHA1="0123456789abcdef0123456789abcdef01234567"
SHA256="$SHA1${SHA1:0:24}"

# <expected verdict> <command> <args...>, one server per line.
CASES="pinned npx -y pkg@1.2.3
pinned npx -y @scope/pkg@1.2.3
pinned npx -y pkg@v1.2.3
pinned npx -y pkg@1.2.3-beta.1
pinned npx -y pkg@1.2.3+build.5
pinned bunx pkg@10.20.30
pinned npx -y --package=pkg@1.2.3 pkg-bin
pinned npx -y -p pkg@1.2.3 pkg-bin
pinned npx -y github:owner/repo#$SHA1
pinned npx -y pkg@sha256:$SHA256
pinned uvx pkg==1.2.3
pinned uvx pkg==1.2.3rc1
pinned uvx pkg==1.2.3.post1
pinned uvx --from pkg==1.2.3 pkg-cli
pinned uvx --from git+https://github.com/owner/repo@v1.7.0 tool start
pinned uvx --from git+https://github.com/owner/repo@$SHA1 tool
pinned uvx --with mcp==1.9.4 postgres-mcp==0.3.0 --access-mode=restricted
unpinned npx -y pkg
unpinned npx -y @scope/pkg
unpinned npx -y pkg@latest
unpinned npx -y pkg@1
unpinned npx -y pkg@v1
unpinned npx -y pkg@1.2
unpinned npx -y pkg@^1.2.3
unpinned npx -y pkg@~1.2.3
unpinned npx -y pkg@1.x
unpinned npx -y pkg@1.2.x
unpinned npx -y pkg@>=1.2.3
unpinned npx -y --package=pkg@1 pkg-bin
unpinned bunx pkg@2
unpinned npx -y github:owner/repo#${SHA1:0:7}
unpinned uvx --from git+https://github.com/owner/repo@${SHA1:0:7} tool
unpinned uvx --from git+https://github.com/owner/repo tool
unpinned uvx pkg
unpinned uvx pkg==1
unpinned uvx pkg==1.2
unpinned uvx pkg>=1.2.3
unpinned uvx pkg~=1.2.3
unpinned uvx --with mcp postgres-mcp==0.3.0"

# $1 fixture dir, $2 "all" or "pinned": writes .mcp.json with one server per case (p01, u01, ...),
# plus an unpinned on-demand server that must be checked and an example file that must be skipped.
fixture() {
  mkdir -p "$1/.claude/mcp" "$1/scripts/check"
  cp -p scripts/check/ai-config.sh "$1/scripts/check/"
  python3 - "$1" "$2" "$CASES" <<'PY'
import json, os, sys

root, which, cases = sys.argv[1], sys.argv[2], sys.argv[3]
servers, n = {}, {"pinned": 0, "unpinned": 0}
for line in cases.splitlines():
    verdict, command, *args = line.split()
    n[verdict] += 1
    if which == "pinned" and verdict != "pinned":
        continue
    servers[f"{verdict[0]}{n[verdict]:02d}"] = {"type": "stdio", "command": command, "args": args}
json.dump({"mcpServers": servers}, open(os.path.join(root, ".mcp.json"), "w"), indent=2)
on_demand = {"mcpServers": {"uod": {"command": "npx", "args": ["-y", "pkg@latest"]}}}
example = {"mcpServers": {"pex": {"command": "npx", "args": ["-y", "<pkg>@<pinned-version>"]}}}
if which != "pinned":
    json.dump(on_demand, open(os.path.join(root, ".claude/mcp/od.json"), "w"))
json.dump(example, open(os.path.join(root, ".claude/mcp/od.example.json"), "w"))
PY
}

pass=0 fail=0
holds() {
  local what="$1"
  shift
  if "$@"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $what"
  fi
}
# $1 file, $2 server, $3 output: ai-config.sh named that server as unpinned.
named() { grep -qF -- "$1: $2 runs " "$3"; }
not_named() { ! named "$@"; }
not_in() { ! grep -qF -- "$1" "$2"; }

# Every case in one repo: exit 1, each unpinned server named, no pinned one.
fixture "$TMP/all" all
(cd "$TMP/all" && bash scripts/check/ai-config.sh) >"$TMP/all.out" 2>&1
code=$?
holds "a repo with unpinned servers exits 1 (got $code)" [ "$code" -eq 1 ]
p=0 u=0
while read -r verdict _ rest; do
  if [ "$verdict" = pinned ]; then
    p=$((p + 1))
    name="$(printf 'p%02d' "$p")"
    holds "pinned $name ($rest) is not named" not_named .mcp.json "$name" "$TMP/all.out"
  else
    u=$((u + 1))
    name="$(printf 'u%02d' "$u")"
    holds "unpinned $name ($rest) is named" named .mcp.json "$name" "$TMP/all.out"
  fi
done <<EOF
$CASES
EOF
holds "an unpinned server in .claude/mcp/*.json is named" named .claude/mcp/od.json uod "$TMP/all.out"
holds "a placeholder in .claude/mcp/*.example.json is skipped" not_in od.example.json "$TMP/all.out"

# Only the pinned cases: exit 0.
fixture "$TMP/pinned" pinned
(cd "$TMP/pinned" && bash scripts/check/ai-config.sh) >"$TMP/pinned.out" 2>&1
code=$?
holds "a repo whose servers are all pinned exits 0 (got $code)" [ "$code" -eq 0 ]

if [ "$fail" -gt 0 ]; then
  echo "--- ai-config.sh output, every case:"
  cat "$TMP/all.out"
fi
echo "ai-config probes: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
