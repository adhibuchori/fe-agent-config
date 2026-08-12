#!/usr/bin/env bash
# Runs the checks quality-gate.yaml runs, for promotions that cannot use CI.
# Usage: quality-gate.sh [base-ref]   default origin/dev. See README § CI/CD.
set -uo pipefail

cd "$(dirname "$0")/../.."

BASE="${1:-origin/dev}"
failed=0
skipped=""

# On a runner a skipped check is a hole in the gate, so it fails instead.
STRICT=0
[ "${CI:-}" = "true" ] && STRICT=1
case " $* " in *" --strict "*) STRICT=1 ;; esac

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

git rev-parse --verify "$BASE" >/dev/null 2>&1 || {
  echo "::error::base ref '$BASE' not found; run: git fetch origin"
  exit 1
}

run "Install Dependencies" bun install --frozen-lockfile
run "Format & Lint" bun run fl:ci
run "Type Check" bun run type-check
run "Comment Style Check" bun run .github/scripts/check-comment-style.ts
run "Comment Block Length Check" bash .github/scripts/check-comment-blocks.sh

# A stale copy under .claude/commands/ still reads as valid, and INDEX.md is what an agent
# consults to discover the commands at all. Skipped on prod, where the strip removed the source.
step "Workflow Mirror Drift Check"
if [ ! -d _workflow-source ] || [ ! -f scripts/sync-workflows.sh ]; then
  echo "_workflow-source/ not present on this branch - skipping"
elif ! bash scripts/sync-workflows.sh --check; then
  echo "::error::workflow mirror or INDEX.md has drifted"
  failed=$((failed + 1))
fi
run "Security Audit" bun run scripts/audit-check.ts

# ── Security scans over the diff against BASE ──
scan() {
  step "$1"
  if git diff "$BASE"...HEAD -- $3 | grep -Eq "$2"; then
    echo "::error::$1 found a match"
    git diff "$BASE"...HEAD -- $3 | grep -En "$2" | head -20
    failed=$((failed + 1))
  else
    echo "Clean"
  fi
}

step "Check .env Not Committed"
if git diff "$BASE"...HEAD --name-only | grep -E "^\.env(\.|$)" | grep -qvE "^\.env(\.[a-z]+)?\.example$"; then
  echo "::error::.env file committed"
  failed=$((failed + 1))
else
  echo "Clean"
fi

scan "Dangerous JS APIs Check" '\beval\s*\(|new\s+Function\s*\(' "src scripts"
scan "Unsafe React Patterns Check" 'dangerouslySetInnerHTML|__html' "src scripts"
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
  if curl -sSfL -o gitleaks.tar.gz "$GL_URL"     && echo "${GITLEAKS_SHA256}  gitleaks.tar.gz" | sha256sum -c -     && tar xzf gitleaks.tar.gz gitleaks; then
    GL=./gitleaks
  else
    echo "::error::could not fetch or verify the pinned gitleaks build"
    failed=$((failed + 1))
  fi
elif command -v gitleaks >/dev/null 2>&1; then
  GL=gitleaks
fi

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
for f in $(find src/hooks src/lib -name "*.ts" -o -name "*.tsx" 2>/dev/null); do
  while IFS= read -r line; do
    fn=$(echo "$line" | grep -oE "export (async )?function [a-zA-Z]+" | awk '{print $NF}')
    if [ -n "$fn" ]; then
      lineno=$(grep -n "export.*function $fn\|export const $fn" "$f" | head -1 | cut -d: -f1)
      if [ -n "$lineno" ] && [ "$lineno" -gt 3 ]; then
        before=$(sed -n "$((lineno-3)),$((lineno-1))p" "$f")
        if ! echo "$before" | grep -q "/\*\*"; then
          missing="$missing\n  $f: $fn"
        fi
      fi
    fi
  done < <(grep -n "^export.*function\|^export const" "$f" 2>/dev/null)
done
if [ -n "$missing" ]; then
  echo "::warning::Missing JSDoc on exported symbols:$missing"
fi

# Inserting a rule renumbers AGENTS.md and silently breaks every citation.
step "AI Config Rule Drift Check"
if [ ! -f AGENTS.md ] || [ ! -d .claude ]; then
  echo "AGENTS.md or .claude/ not present on this branch - skipping"
else
  stale=0
  for f in .claude/agents/*.md .claude/hooks/*.sh; do
    [ -f "$f" ] || continue
    for n in $(grep -oE "Rule [0-9]+" "$f" | grep -oE "[0-9]+" | sort -u); do
      if ! grep -qE "Rule $n[^0-9]" AGENTS.md; then
        echo "::error file=$f::cites Rule $n, which does not exist in AGENTS.md"
        stale=1
      fi
    done
  done
  if [ "$stale" -ne 0 ]; then
    failed=$((failed + 1))
  else
    echo "All cited rule numbers exist in AGENTS.md"
  fi
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
