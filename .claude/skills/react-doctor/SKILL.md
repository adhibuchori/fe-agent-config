---
name: react-doctor
description: Use when finishing a feature, fixing a bug, before committing React code, or when the user types `/react-doctor`, asks to scan, triage, or clean up React diagnostics. Covers lint, accessibility, bundle size, architecture. Includes a regression check and a local triage workflow.
---

# React Doctor

Scans React code for security, performance, correctness and architecture issues.

Adapted from React Doctor's own skill (version 1.2.0), Copyright (c) 2026 Million Software, Inc.,
under the Modified MIT License in [LICENSE](LICENSE), which also names the uses that need the
vendor's written permission. What changed here: the CLI is pinned instead of `@latest`; the triage
workflow in `references/triage.md` is written for this repo and read locally, never fetched from the
vendor's site at run time, so nothing outside the repo changes what an agent is told; and scans keep
their results local (below). An upgrade raises the pin here, in both references, and in
[the React Doctor workflow](../../../.github/workflows/react-doctor.yml) together, after reading the
release notes.

## Keep scans local

By default a scan sends data to two services. Its diagnostics (rule, message and a scrubbed file
path) and repository metadata (repo name, commit, framework, React version, file count) go to the
vendor's score API, along with crash reports and usage telemetry. On a full scan, or when a
manifest changed, each dependency's name and version also goes to Socket.dev for a supply-chain
score. `--no-score` (alias `--no-telemetry`) turns off the score API, the share link, crash
reporting and telemetry; `--no-supply-chain` turns off the dependency lookup. Pass both on every
run unless the user has agreed to share that data. The report then carries no health score, so
compare diagnostics instead. Known-vulnerable dependencies are the quality gate's job
([the audit gate](../../../scripts/check/audit.ts)), not this scan's.

## Command

Always the pinned CLI with both flags above. Never `@latest`, never an unversioned package.

```bash
bunx react-doctor@0.9.14 --no-score --no-supply-chain --verbose --scope changed   # after React changes
bunx react-doctor@0.9.14 --no-score --no-supply-chain --verbose                   # general cleanup
bunx react-doctor@0.9.14 --no-score --no-supply-chain design --verbose            # UI design audit
```

- After React code changes, a diagnostic the base branch did not have is a regression: fix it
  before committing.
- A general cleanup scans the full scope. Fix errors first, then warnings.
- The design audit runs only the design-tagged composition, typography, interaction,
  accessibility and motion rules, including those that stay opt-in in a general scan.
- Dead code is not reported here: [the repo's doctor.config.json](../../../doctor.config.json)
  sets `deadCode: false`, because Knip owns unused files, exports and dependencies
  ([the dead-code rule](../../rules/typescript/dead-code.md)).

| Flag                | Purpose                                                          |
| ------------------- | ---------------------------------------------------------------- |
| `.`                 | Scan current directory                                           |
| `--no-score`        | Skip the score API, share link, crash reports and telemetry      |
| `--no-supply-chain` | Skip the dependency lookup at Socket.dev                         |
| `--verbose`         | Show affected files and line numbers per rule                    |
| `--scope changed`   | Only report issues introduced vs the base branch (default: full) |
| `--scope lines`     | Only report issues on the changed lines                          |
| `--json`            | One structured JSON report, for comparing runs                   |
| `design`            | Run only the focused UI design diagnostics                       |

## /react-doctor — local triage

When the user types `/react-doctor` (this skill's name; `/doctor` is Claude Code's own health
check), says "run react doctor", or asks for a full triage or cleanup pass rather than a regression
check, follow [references/triage.md](references/triage.md). Guidance for a
single rule comes from `bunx react-doctor@0.9.14 --no-score rules explain <rule>`; do not fetch
rule prompts from the web.

## Configuring or explaining rules

When the user wants to understand a rule, disagrees with one, or wants to tune which rules run
rather than fix code, read [references/explain.md](references/explain.md) and follow it.
