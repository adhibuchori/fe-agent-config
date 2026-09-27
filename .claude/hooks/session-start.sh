#!/usr/bin/env bash
# SessionStart: makes the zsh that runs Claude's Bash commands behave like bash on three common
# traps: an unmatched glob aborts the command (NOMATCH), `=word` expands to a path (EQUALS), and
# $var does not word-split. It reaches only Claude's shell, through $CLAUDE_ENV_FILE, which Claude
# Code sources before every Bash command, and does nothing under bash. Wired with `|| true`.
# Fails open: it never reads the payload, and a file it cannot write is left alone.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_start feedback "[session-start]"
[ -n "${CLAUDE_ENV_FILE:-}" ] || exit 0
# shellcheck disable=SC2016 # the line is written for zsh to expand later
LINE='[ -n "${ZSH_VERSION:-}" ] && setopt NO_NOMATCH NO_EQUALS SH_WORD_SPLIT 2>/dev/null'
grep -qxF "$LINE" "$CLAUDE_ENV_FILE" 2>/dev/null || printf '%s\n' "$LINE" >>"$CLAUDE_ENV_FILE" 2>/dev/null
exit 0
