---
trigger: always_on
---

# Read First

This repo's guardrails live in several files. `AGENTS.md`, this file and
`common-working-agreements.md` load automatically; every other rule in this folder loads while a
file matching its globs is in play. Read the rest yourself, in this order, before touching any code.

## Required reading

1. **`AGENTS.md`** — the numbered rules (1-34): separation of concerns, styling, data fetching,
   i18n, React Compiler, code quality, folder organization. This is the primary rulebook.
2. **`SSOT.md` §4** — folder structure and layer ownership. §5 for the API contract.
3. **`CLAUDE.md`** — project snapshot, quality gates, branching, commit format, protected files,
   and the on-demand reference table. **Skip § Agent Tooling** — see "Does not apply here" below.
4. **`common-working-agreements.md`** in this folder — how work is scoped, evidenced, reviewed and
   reported here.
5. **`.claude/anti-patterns/INDEX.md`** — scan the trigger keywords, then load only the entries
   matching your task.

## Does not apply here

`AGENTS.md` and `CLAUDE.md` are shared with Claude Code, which has tooling this IDE does not.
These parts are written for that tooling. Substitute as follows:

| Rule as written                                                               | What to do here                                                                                                                               |
| ----------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `AGENTS.md` Rule 0 / 0b — "Use Serena MCP for .ts/.tsx, never Read/Grep/Glob" | No Serena MCP here. Use this IDE's native file reading and symbol search. Read the code normally — Rule 0 is not a ban on reading TypeScript. |
| `CLAUDE.md` § Agent Tooling — Serena and Context7                             | Use this IDE's own symbol search and documentation lookup.                                                                                    |
| `AGENTS.md` §J Self-Review Gate — the three `MCP:` checklist lines            | Skip those three. Every other line in that checklist still applies.                                                                           |

Everything else in both files applies unchanged.

## The guard hooks do not run here

Claude Code runs the hooks in `.claude/settings.json`: they refuse destructive commands, pushes to
`dev` or `prod`, skipped pre-commit gates, direct reads or writes of `.env*` files, and hand edits
to generated output. **None of that runs in this IDE, so hold yourself to it.** List a `.env*` file
only through `bash scripts/env/show.sh <file>`, which masks the secrets, and leave pushes to
protected branches to the user.

## Quality gates are manual here

Claude Code formats and lints every edited file through hooks. **Those hooks do not run in this
IDE.** Before marking any task done, run `bash scripts/check/gates.sh` — the list
`.husky/pre-commit` runs — and fix what it reports.

If you changed any translation key, verify every locale file under `src/messages/` was updated —
nothing will check that for you here until the gates run.
