#!/usr/bin/env bash
# Runs the checks quality-gate.yaml runs, for promotions that cannot use CI.
# Usage: quality-gate.sh [base-ref] [--strict]   base default origin/dev. Why: https://github.com/adhibuchori/fe-agent-config#cicd
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 2

BASE=origin/dev
STRICT=0
for arg in "$@"; do
  case "$arg" in
  --strict) STRICT=1 ;;
  -*) echo "::error::unknown option $arg" && exit 2 ;;
  *) BASE="$arg" ;;
  esac
done
# On a runner a skipped check is a hole in the gate, so it fails instead.
[ "${CI:-}" = "true" ] && STRICT=1

failed=0
skipped=""

step() {
  printf '\n\033[1m── %s\033[0m\n' "$1"
}

run() {
  step "$1"
  shift
  if ! "$@"; then
    echo "::error::$* failed"
    failed=$((failed + 1))
  fi
}

# A check that cannot run here is recorded, never silently passed — the summary
# at the end is what tells you the gate was partial.
skip() {
  skipped="${skipped}"$'\n'"  $1 — $2"
}

# An optional module (dialog descriptions, responsive layout, skeleton switches) runs here exactly
# when scripts/check/gates.list lists it, so deleting its line there switches it off in both places.
optional() {
  local name="$1" script="$2"
  if grep -qE "^[^#].*run ${script}\$" scripts/check/gates.list 2>/dev/null; then
    run "$name" bun run "$script"
  else
    step "$name"
    echo "$script is not in scripts/check/gates.list - optional module not adopted"
  fi
}

git rev-parse --verify "$BASE" >/dev/null 2>&1 || {
  echo "::error::base ref '$BASE' not found; run: git fetch origin"
  exit 1
}

run "Install Dependencies" bun install --frozen-lockfile --ignore-scripts
run "Format & Lint" bun run fl:ci
run "Folder Shape Check" node scripts/check/folder-shape.mjs
run "Coverage Policy Check" node scripts/check/coverage-policy.mjs

# The generated client is gitignored, so a fresh checkout has no src/lib/api/generated/ until it is
# built. The type check and the dead-code check both import from it.
if [ -f orval.config.ts ] || [ -f orval.config.js ]; then
  run "Generate API Client" bun run generate:api
fi
run "Type Check" bun run type-check
run "Dead Code Check" bun run check:dead-code
run "Comment Style Check" bun run .github/scripts/check-comment-style.ts
run "Comment Block Length Check" bash .github/scripts/check-comment-blocks.sh
run "i18n Parity and Casing Check" bun run check:i18n
run "Hook Placement Check" bun run check:hooks
run "No Re-exports" bun run check:reexport
run "Separation of Concerns" bun run check:soc
# Calls Tailwind's own canonicalizer against this repo's stylesheet, so it cannot drift from the
# editor's warning.
run "Tailwind Class Check" bun run check:tailwind
run "Error Code Mapping Check" bun run check:error-codes
run "Error Catch Check" bun run check:error-catch
# The image builds what this gate validated: generated clients, a readable digest pin, and a Bun no
# older than the one this gate ran.
run "Dockerfile Check" bun run check:dockerfile
optional "Dialog Description Check" check:dialog-desc
optional "Responsive Check" check:responsive
optional "Skeleton Switch Check" check:skeleton-switch
optional "Skeleton Pairs Check" check:skeleton-pairs
optional "Payload Endpoint Registry Check" check:endpoints
optional "Payload Crypto Interop Check" check:crypto-interop

# The mirrors a second tool reads: stale copies still read as valid, so drift fails here. Both
# scripts exit 0 on a branch the prod strip has cleaned.
run "Rules Mirror Check" bash scripts/sync/rules.sh --check
run "Workflow Mirror Drift Check" bash scripts/sync/workflows.sh --check
run "Security Audit" bun run scripts/check/audit.ts

# ── Security scans over the diff against BASE ──
# $3 is a space-separated pathspec list, split on purpose; tests may name what these refuse.
scan() {
  step "$1"
  # shellcheck disable=SC2086 # one pathspec per word
  if git diff "$BASE"...HEAD -- $3 ':(exclude)src/testing' | grep -Eq "$2"; then
    echo "::error::$1 found a match"
    # shellcheck disable=SC2086 # one pathspec per word
    git diff "$BASE"...HEAD -- $3 ':(exclude)src/testing' | grep -En "$2" | head -20
    failed=$((failed + 1))
  else
    echo "Clean"
  fi
}

step "Check .env Not Committed"
if git diff "$BASE"...HEAD --name-only | grep -E "(^|/)\.env(\.|$)" | grep -qvE "(^|/)\.env(\.[a-z]+)?\.example$"; then
  echo "::error::.env file committed"
  failed=$((failed + 1))
else
  echo "Clean"
fi

scan "Dangerous JS APIs Check" '\beval\s*\(|new\s+Function\s*\(' "src scripts"
scan "Unsafe React Patterns Check" 'dangerouslySetInnerHTML|__html' "src scripts"
# For a repo whose sign-in lives in another app; delete this scan if this app owns sign-in.
scan "Auth Code Detection" '\b(useSession|NextAuth|ClerkProvider|useAuth|getAuth|withAuth|jwt\.sign|jwt\.verify|openid-connect)\b' "src scripts"
scan "URL Scheme Injection Check" '(javascript:|data:text/html|data:application/)' "src scripts"

step "Secret Scan (gitleaks)"
GITLEAKS_VERSION=8.30.1
GITLEAKS_SHA256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
GL=""

# The pinned build and checksum, exactly as CI fetches them. Any other binary is
# a different scan, so elsewhere it falls back to whatever is installed.
if [ "$(uname -s)" = "Linux" ] && [ "$(uname -m)" = "x86_64" ]; then
  GL_URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
  if curl -sSfL -o gitleaks.tar.gz "$GL_URL" && echo "${GITLEAKS_SHA256}  gitleaks.tar.gz" | sha256sum -c - && tar xzf gitleaks.tar.gz gitleaks; then
    GL=./gitleaks
  else
    echo "::error::could not fetch or verify the pinned gitleaks build"
    failed=$((failed + 1))
  fi
elif command -v gitleaks >/dev/null 2>&1; then
  GL=gitleaks
fi

# --config explicitly: the allowlist in .gitleaks.toml is only read when named.
if [ -n "$GL" ]; then
  if ! "$GL" git . --no-banner --redact --config .gitleaks.toml; then
    echo "::error::gitleaks found findings"
    failed=$((failed + 1))
  fi
elif [ "$failed" -eq 0 ]; then
  echo "gitleaks not installed — brew install gitleaks"
  skip "Secret Scan (gitleaks)" "no pinned build for $(uname -sm), none on PATH"
fi
rm -f gitleaks gitleaks.tar.gz

run "Tests with Coverage" bun run test:coverage

# ── Documentation — JSDoc presence check (warning-only, never fails the gate) ──
step "JSDoc Presence Check"
missing=""
while IFS= read -r f; do
  while IFS= read -r line; do
    fn=$(printf '%s\n' "$line" | grep -oE "export (async )?function [a-zA-Z]+" | awk '{print $NF}')
    [ -n "$fn" ] || continue
    lineno=$(grep -n "export.*function $fn\|export const $fn" "$f" | head -1 | cut -d: -f1)
    if [ -n "$lineno" ] && [ "$lineno" -gt 3 ]; then
      if ! sed -n "$((lineno - 3)),$((lineno - 1))p" "$f" | grep -q "/\*\*"; then
        missing="$missing\n  $f: $fn"
      fi
    fi
  done < <(grep -n "^export.*function\|^export const" "$f" 2>/dev/null)
done < <(find src/hooks src/lib \( -name "*.ts" -o -name "*.tsx" \) 2>/dev/null)
if [ -n "$missing" ]; then
  printf '::warning::Missing JSDoc on exported symbols:%b\n' "$missing"
fi

# Rule citations (a new rule renumbers AGENTS.md), the always-loaded budget, hook wiring, MCP pins.
run "AI Config Check" bash scripts/check/ai-config.sh
# The MCP pin rule above, proved both ways on its own temp repos; it never reads this one.
run "AI Config Pin Probes" bash scripts/check/ai-config-probes.sh
# What each Claude Code hook must block and let through; skips on a branch without .claude/.
run "Hook Probes" bash scripts/check/hook-probes.sh
run "No Double Assertion" bash scripts/check/double-assertion.sh

# SkillSpector scans skills, commands, subagents and hooks; it installs and runs only when one changed.
step "Skill Security Scan"
SKILL_PATHS=(.agents/skills .claude/skills .claude/commands .claude/agents .claude/hooks _workflow-source .skillspector-baseline.yaml scripts/check/skills.sh)
if [ ! -d .claude ]; then
  echo ".claude/ not present on this branch - skipping"
elif git diff --quiet "$BASE"...HEAD -- "${SKILL_PATHS[@]}"; then
  echo "No skill, command, subagent or hook changed - skipping"
elif ! command -v uv >/dev/null 2>&1; then
  echo "::error::uv is required to install the pinned SkillSpector"
  failed=$((failed + 1))
else
  if ! command -v skillspector >/dev/null 2>&1; then
    # The same commit scripts/check/skills.sh pins; it refuses any other build.
    uv tool install --quiet --python 3.12 "git+https://github.com/NVIDIA/skillspector.git@69dcdfb74487d361ba4c811d088cfdea2ff3a9dc"
    PATH="$(uv tool dir --bin):$PATH"
  fi
  bash scripts/check/skills.sh --changed "$BASE" || failed=$((failed + 1))
fi

run "Production Build" bun run build

# ── Security — source map leak check (.next/static only) ──
step "Check Source Maps Leak"
MAPS=$(find .next/static -name "*.map" 2>/dev/null | head -5)
if [ -n "$MAPS" ]; then
  echo "::error::Source maps leaked in client bundle (.next/static)"
  echo "$MAPS"
  failed=$((failed + 1))
else
  echo "Clean"
fi

# ── Summary ──
printf '\n\033[1m── Summary\033[0m\n'
if [ -n "$skipped" ]; then
  printf 'Checks that did NOT run:%s\n\n' "$skipped"
fi

if [ "$failed" -gt 0 ]; then
  printf '::error::%d check(s) failed.\n' "$failed"
  exit 1
fi

if [ -n "$skipped" ]; then
  if [ "$STRICT" -eq 1 ]; then
    echo "::error::gate was partial and strict mode is on."
    exit 1
  fi
  echo "All checks that ran passed, but the gate was PARTIAL — see the list above."
  exit 0
fi

echo "Full gate passed."
