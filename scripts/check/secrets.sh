#!/usr/bin/env bash
# Scans the staged changes for secrets before they become a commit: `gitleaks git --staged` (what
# `gitleaks protect --staged` was) with this repo's .gitleaks.toml. CI scans the pull request's
# commits again, but by then the secret is in the remote's history. scripts/check/gates.list runs
# it on every commit; in a Python repo, .pre-commit-config.yaml does.
#
#   bash scripts/check/secrets.sh
#
# Fails, never skips, when gitleaks or .gitleaks.toml is missing: a gate that cannot run must not
# read as a pass. A gitleaks release other than CI's pin still scans, with a warning on stderr: a
# routine upgrade must not stop every commit, and CI scans again with the pinned release. CI's pin
# is GITLEAKS_VERSION in .github/scripts/quality-gate.sh when the repo runs its own gate there, else
# PIN below, the release agent-config-kit's reusable quality gate installs. Exit 1 on a finding.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

# The gitleaks release the reusable quality gate installs (its scripts/install-gitleaks.sh).
PIN=8.30.1
want="$(sed -n 's/^GITLEAKS_VERSION=//p' .github/scripts/quality-gate.sh 2>/dev/null | head -1)"
want="${want:-$PIN}"
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "::error::gitleaks is not installed; install release $want (brew install gitleaks, or the binary from https://github.com/gitleaks/gitleaks/releases)" >&2
  exit 1
fi
if [ ! -f .gitleaks.toml ]; then
  echo "::error::.gitleaks.toml is missing: the scan reads this repo's rules and allowlist from it" >&2
  exit 1
fi
have="$(gitleaks version 2>/dev/null)"
if [ "${have#v}" != "$want" ]; then
  echo "::warning::gitleaks ${have:-of unknown version} found; CI pins $want. Scanning with it anyway; install $want to match CI" >&2
fi
exec gitleaks git --staged --no-banner --redact --config .gitleaks.toml
