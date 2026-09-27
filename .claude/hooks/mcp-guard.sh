#!/usr/bin/env bash
# PreToolUse(GitHub MCP writes): the GitHub tools that commit, push or branch without a Bash call
# never write straight onto a protected branch (protectedBranches in .claude/agent-config.json).
# Wire it only on tools that carry a `branch` field: push_files, create_or_update_file, delete_file,
# create_branch. A merge goes through a PR, which is the point.
#
# Fails closed: a payload it cannot read, or a branch list it cannot load, refuses the call.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_start guard "[mcp-guard]"
TOOL="$(hook_field .tool_name)"
BRANCH="$(hook_field .tool_input.branch)"
BRANCH="${BRANCH#refs/heads/}"
[[ -n "$BRANCH" ]] || exit 0

PROTECTED="$(hook_config protectedBranches)" || hook_fail "protectedBranches could not be read."
while IFS= read -r protected; do
  if [[ -n "$protected" && "$BRANCH" == "$protected" ]]; then
    block "[mcp-guard] BLOCKED: ${TOOL##*__} writes straight to the protected branch $BRANCH. Push your work branch and open a PR."
  fi
done <<<"$PROTECTED"

exit 0
