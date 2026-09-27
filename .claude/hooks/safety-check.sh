#!/usr/bin/env bash
# PreToolUse(Bash): refuses the commands an agent never runs on its own: destructive rm/find, work-
# wiping git commands, skipping the pre-commit gate, pushing to or deleting a protected branch,
# gh pr merge --delete-branch, alembic downgrade, any shell read or write of a real .env* file
# (scripts/env/show.sh and, while env is unlocked, scripts/env/set.sh aside), and the agent running
# the unlock script, touching .claude/state/unlock/ or changing scripts/env/ (docs/unlock.md), and
# any change to the files that turn the guards on (.claude/settings.json, settings.local.json,
# agent-config.json, agent-config-kit.lock), which the shell may only read. The rules live in
# analyze_command (lib.sh); scripts/check/hook-probes.tsv lists what each one must block and what it
# must let through. The user runs a refused command themselves with `!` when it is really meant.
#
# Fails closed: a payload that is not a JSON object is refused, and so is every command when
# python3 is present but the analyzer does not finish (a crash, over 8 s, or past the hook's 9 s
# deadline). Only when python3 is not installed do a few plain-text rules stand in for the
# analyzer, and Claude is told so.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_start guard "[safety]" plaintext
if [[ -n "$HOOK_NO_READER" ]]; then
  # Neither python3 nor jq: the plain-text rules judge the raw payload. JSON quotes and escapes
  # become spaces, so the command's words stand apart as in a shell.
  CMD="$(printf '%s' "$HOOK_INPUT" | sed -e 's/\\[nt]/ /g' -e 's/\\"/ /g' -e 's/"/ /g')"
else
  CMD="$(hook_field .tool_input.command)"
  [[ -n "$CMD" ]] || exit 0
fi

VERDICT=""
if [[ -z "$HOOK_NO_READER" ]] && command -v python3 &>/dev/null; then
  VERDICT="$(analyze_command "$CMD" "$(hook_field .cwd)")"
  if [[ "$VERDICT" != *END* ]]; then
    hook_fail "safety-check's command parser did not finish (python3 failed or took over 8 s), so the command was not checked. Splitting the command may help."
  fi
else
  # python3 is missing. Keep the plain-text rules rather than let every command through unread.
  # shellcheck disable=SC2016 # sed expressions: $ is a regex anchor or a character to escape
  names="$(hook_config protectedPaths 2>/dev/null | sed -e 's#/*$##' -e 's/[][\.*^$(){}+?|]/\\&/g' | paste -sd'|' -)"
  # shellcheck disable=SC2016 # sed expression: $ is a character to escape
  branches="$(hook_config protectedBranches 2>/dev/null | sed -e 's/[][\.*^$(){}+?|]/\\&/g' | paste -sd'|' -)"
  names="${names:-src|scripts|\\.claude|\\.git|\\.github|_workflow-source}"
  branches="${branches:-dev|prod|main|master}"
  RM='(^|[;&|[:space:]])rm[[:space:]]+-[[:alpha:]]*[rR]'
  if grep -qE "$RM" <<<"$CMD" && grep -qE "(^|[[:space:]/\"'])($names)(/|[[:space:]\"']|$)" <<<"$CMD"; then
    block "[safety] BLOCKED: rm -r on a protected path (the command parser is unavailable)."
  fi
  if grep -qE "${RM}[[:alpha:]]*[[:space:]]+(\\.|\\./|/|~|~/|\\*|\\./\\*|\\.\\.)([[:space:]\"';&|]|$)" <<<"$CMD"; then
    block "[safety] BLOCKED: rm -r on the repo, a parent folder or the home folder (the command parser is unavailable)."
  fi
  if grep -qE "git[[:space:]].*push[^;&|]*[[:space:]:+]($branches)([[:space:]\"';&|]|$)" <<<"$CMD"; then
    block "[safety] BLOCKED: pushing to a protected branch (the command parser is unavailable)."
  fi
  if grep -qE 'git[[:space:]]+([^;&|]*[[:space:]])?(reset[[:space:]][^;&|]*--hard|clean([[:space:]][^;&|]*)?[[:space:]](-[[:alpha:]]*f[[:alpha:]]*|--force)([^[:alnum:]_-]|$))|--no-verify|HUSKY=0' <<<"$CMD"; then
    block "[safety] BLOCKED: a hard reset, a forced clean or a skipped pre-commit gate (the command parser is unavailable)."
  fi
  # Any real .env* name, since the helper scripts need python3 too; templates (.example) stay open.
  if grep -oiE '(^|[^[:alnum:]_$.])[.]env(rc)?([._-][^[:space:]"'"'"';&|)<>]*)?' <<<"$CMD" | grep -viq '[.]example'; then
    block "[safety] BLOCKED: this command names a .env* file, and without python3 it cannot be checked. Install python3; the user reads the file themselves."
  fi
  if grep -qiE 'state/+(\./+)*unlock|unlock[.]sh|(bun|npm|pnpm|yarn)[[:space:]]+(run[[:space:]]+|run-script[[:space:]]+)?unlock([^[:alnum:]_-]|$)' <<<"$CMD"; then
    block "[safety] BLOCKED: only the user unlocks .env* files and database writes (docs/unlock.md)."
  fi
  # scripts/env/ is the code trusted with .env* files; unparsed, any command naming it may change it.
  if grep -qiE 'scripts/+(\./+)*env(/|[[:space:]]|$)|envfile[.]py' <<<"$CMD"; then
    block "[safety] BLOCKED: this command names scripts/env/, and without python3 it cannot tell a read from a change. Install python3."
  fi
  # The files that turn the guards on: unparsed, any command naming one may change it.
  if grep -qiE 'agent-config(-kit[.]lock|[.]json)|[.]claude[^[:alnum:]]{0,8}settings([.]local)?[.]json|opted-in-projects' <<<"$CMD"; then
    block "[safety] BLOCKED: this command names a file that turns the guards on (.claude/settings.json, settings.local.json, agent-config.json or agent-config-kit.lock), and without python3 it cannot tell a read from a change. Install python3, or read it with the Read tool."
  fi
  report "safety-check could not parse this command (python3 is missing), so only its plain-text rules ran." PreToolUse
  exit 0
fi

REASONS="$(awk -F'\t' '$1 == "BLOCK" { print $2 }' <<<"$VERDICT")"
[[ -z "$REASONS" ]] || block "$REASONS"
report "$(awk -F'\t' '$1 == "WARN" { print $2 }' <<<"$VERDICT")" PreToolUse
exit 0
