#!/usr/bin/env bash
# Shared helpers for the hooks in this directory. Source it, don't execute it.

# Resolves a tool from the project's own node_modules first. oxfmt/oxlint are
# devDependencies installed into node_modules/.bin and are NOT on PATH, so a bare
# `command -v oxfmt` guard always misses and turns the hook into a silent no-op.
# Falls back to PATH (a global install is fine), then to `bunx` as a last resort.
resolve_tool() {
  local tool="$1" root
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

  if [[ -x "$root/node_modules/.bin/$tool" ]]; then
    printf '%s' "$root/node_modules/.bin/$tool"
    return 0
  fi
  if command -v "$tool" &>/dev/null; then
    printf '%s' "$tool"
    return 0
  fi
  if command -v bunx &>/dev/null; then
    printf 'bunx %s' "$tool"
    return 0
  fi
  return 1
}

# Runs a command under a timeout when one is available. macOS ships no `timeout`
# and no `gtimeout` unless coreutils is installed, and `timeout 5 x || true`
# swallows the resulting 127 — which is how these hooks came to exit 0 without
# doing any work. Degrade to running bare rather than silently skipping.
# run-tests.sh already solved this inline; this is the same fix, shared.
run_capped() {
  local secs="$1"; shift
  local to
  to="$(command -v timeout || command -v gtimeout || true)"

  if [[ -n "$to" ]]; then
    "$to" "$secs" "$@"
  else
    "$@"
  fi
}
