---
trigger: always_on
---

# Read First

This repo's guardrails live in several files. Only `AGENTS.md` and this file load automatically.
Read the rest yourself, in this order, before touching any code.

## Required reading

1. **`AGENTS.md`** — Rules 1-30. Separation of concerns, styling, data fetching, i18n, React
   Compiler, code quality. This is the primary rulebook.
2. **`SSOT.md` §4** — folder structure and layer ownership. §5 for design tokens.
3. **`CLAUDE.md`** — project snapshot, JSDoc convention, naming conventions, quality gates,
   branching, commit format, protected files. **Skip §Tool Priority** — see
   "Does not apply here" below.
4. **`.claude/anti-patterns/INDEX.md`** — scan the trigger keywords, then load only the entries
   matching your task.

## Does not apply here

`AGENTS.md` and `CLAUDE.md` are shared with Claude Code, which has tooling this IDE does not.
Three rules there are written for that tooling. Substitute as follows:

| Rule as written                                                                         | What to do here                                                                                                                               |
| --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `AGENTS.md` Rule 0 / 0b — "Use Serena MCP for .ts/.tsx, never Read/Grep/Glob"           | No Serena MCP here. Use this IDE's native file reading and symbol search. Read the code normally — Rule 0 is not a ban on reading TypeScript. |
| `AGENTS.md` §J Self-Review Gate — the three `MCP:` checklist lines                      | Skip those three. Every other line in that checklist still applies.                                                                           |

Everything else in both files applies unchanged.

## Quality gates are manual here

Claude Code runs format, lint, and i18n-parity checks automatically via hooks in
`.claude/settings.json`. **Those hooks do not run in this IDE.** Before marking any task done, run
both of these yourself and fix what they report:

```bash
bun fl          # oxfmt + oxlint
bun type-check  # tsc --noEmit, strict
```

If you changed any translation key, verify `en.json` and `id.json` were both updated — nothing
will check that for you here.
