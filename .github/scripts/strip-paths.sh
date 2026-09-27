#!/usr/bin/env bash
# Single source of truth for what the prod strip removes. Sourced by strip-ai.sh, verify-strip.sh
# and back-merge-prod.sh: all three must agree, or the strip half-lands and prod keeps AI config.

# shellcheck disable=SC2034 # every variable here is read by the scripts that source this file

# Word splitting is intended: one pathspec per word. Globbing is off so patterns
# reach git as pathspecs instead of being expanded against the working tree.
set -f

STRIP_PATHS=".agent .agents .claude .gemini .serena .impeccable _workflow-source AGENTS.md CLAUDE.md GEMINI.md SSOT.md PRODUCT.md PRODUCT.example.md DESIGN.md DESIGN.example.md skills-lock.json .mcp.json .skillspector-baseline.yaml .github/gemini.yaml .github/skills promote-deploy-logs"
# Dev-only files matched by pattern, one pathspec per word, for example "debug*.config.ts".
STRIP_GLOBS=""

LIST="${STRIP_AI_LIST:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/stripped-paths.txt}"

# Bot identity, passed per-invocation via -c so it never touches .git/config. Every script that
# commits must apply it explicitly: a CI runner has no identity of its own and git refuses to merge.
GIT_BOT_IDENTITY=(-c user.name="github-actions[bot]" -c user.email="github-actions[bot]@users.noreply.github.com")
