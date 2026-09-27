# <Project Name> FE — Claude Code Config

> Load the relevant SSOT.md sections for your task. Then execute.
> Behavioral protocol → AGENTS.md §A. Self-review gate → AGENTS.md §J.

---

## Project Snapshot

Next.js 16 + React 19. TanStack Query v5. next-intl (en/id). Orval-generated API client.
Dev: `bun dev` · Default port: 3000

---

## Agent Tooling

- Call `mcp__serena__initial_instructions` before the first `.ts`/`.tsx` task, then use Serena's symbol tools for `.ts`/`.tsx` reads and edits; built-in tools for every other file.
- Scope Serena searches with `relative_path`. `find_symbol` takes `name_path_pattern`; `list_dir` needs `relative_path` and `recursive`. A shared multi-repo workspace changes the prefix: `.claude/SERENA-WORKSPACE.md`.
- On a Serena failure retry once, check `.claude/serena-errors.md` for a logged workaround, log a new one there, and fall back to built-in tools only for a persistent outage, saying so.
- Library APIs: check current docs through Context7 before relying on training data.
- `.env*` files are never read or written directly. List one with `bash scripts/env/show.sh <file>` (secrets masked); change a value with `scripts/env/set.sh` only while the user has run `unlock env`. Production SQL writes wait for `unlock db`. Only the user unlocks: hand them the command to run with `!` (`docs/unlock.md`).

---

## Command Wrapper

None ships. If you route shell commands through a wrapper — an output filter, a sandbox, a
recorder — declare it here as a hard rule, prefix every command in this file with it, and name it
under `commandWrappers` in `.claude/agent-config.json` so the safety hook judges the command it
wraps. A wrapper mentioned only in passing gets dropped the moment a task gets busy.

---

## Context Loading Strategy

Read the relevant section before starting a task. The rules under `.claude/rules/` load by
themselves while a matching file is in play.

| Task                           | Read                                                             |
| ------------------------------ | ---------------------------------------------------------------- |
| Component / UI changes         | SSOT.md §4 + AGENTS.md §B, §C                                    |
| Data fetching / API hooks      | SSOT.md §4 + AGENTS.md §D + `.claude/rules/web/data-fetching.md` |
| i18n / translation keys        | SSOT.md §4 + AGENTS.md §E                                        |
| Store / global state           | SSOT.md §4 + AGENTS.md §B                                        |
| Validation schemas             | SSOT.md §4 + AGENTS.md §B                                        |
| Environment / deployment       | SSOT.md §6, §7                                                   |
| Architecture / layer ownership | SSOT.md §4 + AGENTS.md §I                                        |
| Where a new file belongs       | `.claude/rules/web/file-organization.md`                         |
| Anti-pattern triggers          | `.claude/anti-patterns/INDEX.md`                                 |

---

## Quality Gates

Before calling a task done, run `bash scripts/check/gates.sh`. It runs `scripts/check/gates.list`,
the list `.husky/pre-commit` runs, and prints each gate's exit code and log. In a shared checkout,
`--paths <your files>` limits format and lint to your own files.

`bun run build` is not a gate; run it after a structural change and before a PR. Tests run with
`bun run test` (Vitest); bare `bun test` is Bun's own runner and fails for the wrong reasons.

---

## Language Convention

All code artifacts must be written in **English**:

- Variable and function names
- Comments and JSDoc
- Commit messages and PR descriptions

User-facing strings must go through next-intl (`en.json` / `id.json`). No hardcoded UI text.

---

## Commit Format

```
type(scope): subject — max 50 characters
```

Types: `feat` · `fix` · `refactor` · `chore` · `docs` · `style` · `perf` · `test` — these
label commit messages, not branch names; branch prefixes are `internal/…` (see § Branching).

Stage and commit by pathspec (`git commit -- <paths>`). `git add -A` is used only inside `/ship`,
which states its own guards.

---

## Branching

Three branch levels, each a promotion stage:

| Branch             | Purpose                                              |
| ------------------ | ---------------------------------------------------- |
| `internal/{scope}` | Experiments, proof of concept, early work on a scope |
| `dev`              | Active development — all scopes merge here first     |
| `prod`             | Stable, deployed code                                |

Naming: `internal/{scope}` for a single task; `internal/{scope}/{context}` when parallel
tasks share a scope — e.g. `internal/auth`, `internal/auth/login`, `internal/auth/register`.
Work directly on `internal/{scope}` unless the scope splits into parallel tasks, in which
case `internal/{scope}` becomes the integration point for the `internal/{scope}/{context}`
branches and is not committed to directly.

Merge order: `internal/{scope}/{context}` → `internal/{scope}` → `dev` → `prod`. Never push
directly to `dev` or `prod`: the safety hook refuses it, and a promotion push is the user's, run
with `!`.

---

## Protected Files

Never edit:

```
.env*                     ← list with scripts/env/show.sh; change only while unlocked (docs/unlock.md)
src/lib/api/generated/    ← auto-generated by Orval, regenerate with bun generate:api
AGENTS.md · SSOT.md       ← propose the change; the user makes it
.claude/settings.json     ← hook wiring and permissions
```

The committed `.env.*.example` templates hold no real values and may be edited.

---

## Notes

- `src/lib/api/generated/` is read-only — regenerate with `bun generate:api` after any `openapi.json` change.
- React Compiler is active (`babel-plugin-react-compiler`) — do not add `useMemo`/`useCallback`/`memo()` speculatively.
- Both `en.json` and `id.json` must be updated together whenever a translation key is added or changed.

---

## On-demand References

Nothing below loads automatically. Read the file when its row matches the task. A file that ships
as `<name>.example.md` is a template: fill it in and save it without `.example`, or delete the
template and its row.

| Read when                                                                           | File                                          |
| ----------------------------------------------------------------------------------- | --------------------------------------------- |
| Operations: hooks contract, GitHub and CI, reviews, MCP pins, deploys, skill scans  | `.claude/OPERATIONS.md`                       |
| Known traps — scan trigger keywords before debugging                                | `.claude/anti-patterns/INDEX.md`              |
| Sealed bodies, the route registry and keys (where adopted)                          | `.claude/PAYLOAD-CONTRACT.md`                 |
| Reviewing a change (`/review` reads it)                                             | `.claude/docs/code-review-checklist.md`       |
| Before `/promote`, when the user asks for the audit                                 | `.claude/docs/pre-promote-audit.md`           |
| File organization examples                                                          | `.claude/docs/standards/file-organization.md` |
| Responsive failures and examples                                                    | `.claude/docs/standards/responsive.md`        |
| Skeleton derivations and examples                                                   | `.claude/docs/standards/skeletons.md`         |
| Dialog description examples and sources                                             | `.claude/docs/standards/dialog-content.md`    |
| Postgres through `db-dev`/`db-prod`: topology, tunnel, production rules             | `.claude/DATABASE.md`                         |
| CI runner pools and billing                                                         | `.claude/CI-RUNNERS.md`                       |
| Analytics read API                                                                  | `.claude/ANALYTICS.md`                        |
| Serena across several repos                                                         | `.claude/SERENA-WORKSPACE.md`                 |
| Rarely used MCP servers, loaded per session with `claude --mcp-config <file>`       | `.claude/mcp/*.json`                          |
| What the `.env*` and database locks stop, and how the user opens them               | `docs/unlock.md`                              |
