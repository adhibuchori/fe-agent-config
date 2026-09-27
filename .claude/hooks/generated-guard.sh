#!/usr/bin/env bash
# PreToolUse(Write|Edit|MultiEdit and Serena's writes): generated output changes only through its
# generator. The guarded paths are generatedPaths in .claude/agent-config.json (repo-relative files
# or folders); the default covers a generated API client and a copied OpenAPI contract. Optional:
# wire it where the repo has generated files (frontends, docs sites).
#
# A symlink is judged as named and as the file it points to, since a write lands there.
#
# Fails closed: a payload it cannot read, a path list it cannot load, a symlink it cannot
# follow, or a replace_in_files whose reach it cannot work out (no python3, or over 5 s) refuses
# the call.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_start guard "[generated-guard]"

# generatedPaths of the repo ROOT names. A key that neither python3 nor jq can read refuses the
# call rather than guarding nothing.
guarded() {
  local list p
  list="$(hook_config generatedPaths)" || hook_fail "generatedPaths could not be read."
  GUARDED=()
  GUARDED_ROOT="$ROOT"
  while IFS= read -r p; do
    p="${p%/}"
    [[ -n "$p" ]] && GUARDED+=("$p")
  done <<<"$list"
}
guarded

# replace_in_files names a folder, or the whole project, rather than the file it rewrites.
if [[ ${#GUARDED[@]} -gt 0 ]] && hook_scope_hits "${GUARDED[@]}"; then
  block "[generated-guard] BLOCKED: this replace_in_files reaches generated output (generatedPaths in .claude/agent-config.json)." \
    "Narrow relative_path, or add paths_exclude_glob, so it is not touched."
fi

# $1, an absolute path: refused when it is generated output of its repo. Workspace mode: a file in
# another repo follows that repo's configuration.
judge() {
  local rel p
  hook_adopt_repo "$1"
  in_project "$1" || return 0
  rel="${1#"$ROOT"/}"
  [[ "$ROOT" == "$GUARDED_ROOT" ]] || guarded
  for p in ${GUARDED[@]+"${GUARDED[@]}"}; do
    [[ "$rel" == "$p" || "$rel" == "$p"/* ]] || continue
    case "$p" in
    openapi.* | */openapi.*)
      block "[generated-guard] BLOCKED: $rel is the API contract, copied from the service that owns it." \
        "Change it there and copy it again; never edit the copy."
      ;;
    *)
      block "[generated-guard] BLOCKED: $rel is generated output ($p in generatedPaths)." \
        "Change its source and run the project's generator instead of editing it."
      ;;
    esac
  done
}

FILE="$(hook_file)"
[[ -n "$FILE" ]] || exit 0
SESSION_ROOT="$ROOT"
judge "$FILE"
# A write to a symlink lands in the file it points to, a dangling one included: that is judged too.
TARGET="$(hook_target "$FILE")"
[[ -n "$TARGET" ]] || hook_fail "$FILE is a symbolic link that could not be followed (no realpath, readlink or python3)."
if [[ "$TARGET" != "$FILE" ]]; then
  ROOT="$SESSION_ROOT"
  cd "$ROOT" || hook_fail "the project folder $ROOT cannot be entered."
  judge "$TARGET"
fi

exit 0
