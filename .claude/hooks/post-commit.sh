#!/usr/bin/env bash
# PostToolUse(Bash): after a git commit succeeds, shows Claude what actually landed and says so
# when the commit carries paths its pathspec did not name. Sessions that share one checkout share
# one git index, so another session's staged work can ride along in a pathspec commit; reading the
# committed file list is the one check that binds.
#
# A piped commit (`git commit ... | tail`) reaches PostToolUse even when it failed, and a background
# one before it ran, so what landed is read from the HEAD reflog past the point safety-check.sh
# recorded for this tool call: no record or no new commit, no report, and each commit of a
# multi-commit command is held to its own pathspec.
#
# Fails open: a report after the fact. Without python3, or with a payload it cannot read, it says
# nothing and exits 0.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_start feedback "[post-commit]"
CMD="$(hook_field .tool_input.command)"
[[ "$CMD" == *commit* ]] || exit 0
command -v python3 &>/dev/null || exit 0

NOTES=""
while IFS=$'\t' read -r kind dir sha base paths; do
  [[ "$kind" == COMMIT && -n "$sha" ]] || continue
  stat="$(git -C "$dir" -c core.quotePath=false show --stat --format='%h %s' "$sha" 2>/dev/null | head -40)"
  [[ -n "$stat" ]] || continue
  NOTES="${NOTES}${NOTES:+$'\n\n'}Committed in $dir:"$'\n'"$stat"
  [[ -n "$paths" ]] || continue
  specs=()
  while IFS= read -r p; do
    [[ -n "$p" ]] && specs+=("$p")
  done < <(tr '\037' '\n' <<<"$paths")
  # What this commit changed: against the commit before it, which for --amend is the one it replaced.
  if [[ "$base" == - ]]; then
    list=(show --name-only --format= "$sha")
  else
    list=(diff-tree -r --no-commit-id --name-only "$base" "$sha")
  fi
  # Git resolves the pathspec itself, so ./a, ../b, absolute paths, globs and :/ match as they did
  # for the commit; comparing strings here would call every one of them stray.
  all="$(git -C "$dir" -c core.quotePath=false "${list[@]}" 2>/dev/null | sort)"
  named="$(git -C "$dir" -c core.quotePath=false "${list[@]}" -- "${specs[@]}" 2>/dev/null | sort)"
  stray="$(comm -23 <(printf '%s\n' "$all") <(printf '%s\n' "$named") | sed '/^$/d' | tr '\n' ' ')"
  [[ -z "$stray" ]] || NOTES="$NOTES"$'\n'"WARNING: this commit carries paths its pathspec did not name: ${stray% }. Another session's staged work may have ridden along; check before pushing."
done < <(HOOK_MODE=commits analyze_command "$CMD" "$(hook_field .cwd)")

report "$NOTES"
exit 0
