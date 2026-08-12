# <Project Name> FE — Claude Code Config

> Load the relevant SSOT.md sections for your task. Then execute.
> Behavioral protocol → AGENTS.md §A. Self-review gate → AGENTS.md §J.
> Accumulated working-style feedback → `.claude/session-feedback/INDEX.md`.

---

## Project Snapshot

Next.js 16 + React 19. TanStack Query v5. next-intl (en/id). Orval-generated API client.
Dev: `bun dev` · Default port: 3000

---

## Commands

```
bun dev
bun fl
bun type-check
bun generate:api
bun test
bun test:coverage
bun run build
```

> If you route terminal commands through a wrapper — a token-reducing proxy, a sandbox, a
> recorder — declare it here as a hard rule and prefix every command in this file with it.
> A wrapper mentioned only in passing gets dropped the moment a task gets busy.

---

## Context Loading Strategy

Read the relevant SSOT.md section before starting a task:

| Task                           | Read                             |
| ------------------------------ | -------------------------------- |
| Component / UI changes         | SSOT.md §4 + AGENTS.md §B, §C    |
| Data fetching / API hooks      | SSOT.md §4 + AGENTS.md §D        |
| i18n / translation keys        | SSOT.md §4 + AGENTS.md §E        |
| Store / global state           | SSOT.md §4 + AGENTS.md §B        |
| Validation schemas             | SSOT.md §4 + AGENTS.md §B        |
| Environment / deployment       | SSOT.md §6, §7                   |
| Architecture / layer ownership | SSOT.md §4                       |
| Anti-pattern triggers          | `.claude/anti-patterns/INDEX.md` |

---

## Tool Priority — Serena MCP (STRICT ENFORCEMENT) (Claude Code Only)

Serena MCP is active in this project:

| Instance | Tool Prefix      | Project Root            | Use For                  |
| -------- | ---------------- | ----------------------- | ------------------------ |
| `serena` | `mcp__serena__*` | `.` (this repo)  | All `.ts` / `.tsx` files |

### Session Start — REQUIRED

Before any task involving `.ts`/`.tsx`:

1. Call `mcp__serena__initial_instructions` — read the Serena Instructions Manual
2. Verify tools are available before proceeding

### MANDATORY Rules

1. **ALWAYS** use Serena for `.ts` / `.tsx` file operations in this project.
2. **NEVER** use built-in `Read`, `Grep`, or `Glob` for `.ts` / `.tsx` files.
3. **EXCEPTION:** Non-code files (`.json`, `.md`, `.env`, `.yaml`, `.svg`) may use `Read` / `Glob` / `Grep`.
4. **EXCEPTION:** If a persistent infrastructure error occurs with Serena (see Error Protocol below), report to user and only then fall back to built-in tools.

### Tool Reference

| Task                         | Tool                                                                     |
| ---------------------------- | ------------------------------------------------------------------------ |
| Session Start (Required)     | `mcp__serena__initial_instructions`                                      |
| File Exploration             | `mcp__serena__get_symbols_overview`                                      |
| Locate Symbol/Logic          | `mcp__serena__find_symbol`                                               |
| Find Declaration             | `mcp__serena__find_declaration`                                          |
| Find Implementations         | `mcp__serena__find_implementations`                                      |
| Trace Usages/Dependencies    | `mcp__serena__find_referencing_symbols`                                  |
| File Diagnostics             | `mcp__serena__get_diagnostics_for_file`                                  |
| Replace Full Function/Body   | `mcp__serena__replace_symbol_body`                                       |
| Replace Content (partial)    | `mcp__serena__replace_content`                                           |
| Add code before/after symbol | `mcp__serena__insert_before_symbol` / `mcp__serena__insert_after_symbol` |
| Safe Delete Symbol           | `mcp__serena__safe_delete_symbol`                                        |
| Rename Symbol                | `mcp__serena__rename_symbol`                                             |

### Known Parameter Rules (Breaking Changes — Do Not Revert)

- `find_symbol`: use `name_path_pattern` — NOT `name_path`
  - Example: `{ "name_path_pattern": "useContactForm", "substring_matching": true }`
- `list_dir`: both `relative_path` and `recursive` are mandatory (no defaults)
  - Example: `{ "relative_path": "src/hooks", "recursive": false }`
- `find_symbol` / `find_referencing_symbols`: pass `relative_path` to scope the search —
  omitting it searches every repo in the umbrella workspace when one is active
  - Path prefixing depends on the active Serena project — see `.claude/SERENA-WORKSPACE.example.md`
    if you run a multi-repo umbrella; ignore this line if you do not

### Serena Availability Tiers

| Condition                                                        | Action                                                   |
| ---------------------------------------------------------------- | -------------------------------------------------------- |
| Serena available                                                 | Use normally                                             |
| Serena timeout / transient error                                 | Retry once, then report to user                          |
| Serena unavailable for a `.ts`/`.tsx` task                       | STOP — report to user, wait for approval before fallback |
| Task does not involve `.ts`/`.tsx` (e.g. editing `.md`, `.json`) | Continue without Serena                                  |

### Serena Error Protocol

When a Serena tool call fails:

**Step 1 — Log:** Write a record to `.claude/serena-errors.md`:

```markdown
## YYYY-MM-DD — [tool name]

**Error:** [exact error message]
**Parameters:** [exact params]
**Workaround:** [what was done]
```

**Step 2 — Do Not Repeat:** Before using the same tool again, check `.claude/serena-errors.md` for a matching entry. If found, apply the recorded workaround.

**Step 3 — Fallback (Last Resort):** Only if the error is a persistent infrastructure failure, fall back to built-in tools AND report to user:

> "Serena is unavailable. Falling back to built-in tools. Error logged to `.claude/serena-errors.md`."

---

## Context7 MCP — Documentation Lookup

Context7 provides up-to-date library documentation. Use it when:

- Generating code that depends on a specific library version (Next.js, TanStack Query, next-intl, Zod, etc.)
- Looking up API references, configuration options, or code examples
- Setup or installation steps for a new dependency

**Auto-invoke rule:** Always use Context7 when you need current documentation for any library. Do not rely on training data alone for library-specific APIs.

---

## JSDoc Convention

Every exported function or component must have exactly one JSDoc block, placed immediately above the symbol it describes:

```ts
/** {Type}: {Name}
 * {One sentence description.}
 */
```

Placement is anchored to the symbol, not to the imports: the block goes directly above the `export function` it describes, even when other declarations sit between that function and the import list. What changes versus the old per-file rule is multi-export files, which can now give each symbol its own description. That matters because the docs site reads per symbol — without it, every component in a shared file publishes the same invented prose.

Out of scope, and needing no block of their own:

- Data constants, matching the JSDoc Presence Check in `quality-gate.yaml`.
- Types and interfaces, including `{Name}Props`. Prop descriptions go on the interface **members**, not on the interface, and not in the component's block.

Type prefix — pick the one matching the file's role:

| Prefix      | Used for                |
| ----------- | ----------------------- |
| `Component` | `src/components/**`     |
| `Hook`      | `src/hooks/**`          |
| `Lib`       | `src/lib/**`            |
| `Layout`    | `src/app/**/layout.tsx` |
| `UI`        | `src/components/ui/**`  |
| `Store`     | `src/store/**`          |
| `Page`      | `src/app/**/page.tsx`   |

---

## Quality Gates

Must pass before marking any task done:

```bash
bun fl          # oxfmt (format) + oxlint (lint)
bun type-check  # TypeScript strict — tsc --noEmit
```

---

## Naming Conventions

| Type        | Convention | Example                                              |
| ----------- | ---------- | ---------------------------------------------------- |
| Components  | PascalCase | `HeroSection.tsx` → exports `HeroSection`            |
| Hooks       | camelCase  | `useScrollPosition.ts` → exports `useScrollPosition` |
| Directories | kebab-case | `src/components/`                                    |
| Constants   | kebab-case | `src/lib/constants/routes.ts`                        |
| Types       | kebab-case | `src/types/course.ts`                                |

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
directly to `dev` or `prod`; nothing enforces this in CI yet, so it is a convention to keep.

---

## Protected Files

Never edit:

```
.env.development / .env.production   (the .example templates are committed and hold no real values)
src/lib/api/generated/    ← auto-generated by Orval, regenerate with bun generate:api
.claude/settings.json
```

---

## Notes

- `src/lib/api/generated/` is read-only — regenerate with `bun generate:api` after any `openapi.json` change.
- React Compiler is active (`babel-plugin-react-compiler`) — do not add `useMemo`/`useCallback`/`memo()` speculatively.
- Both `en.json` and `id.json` must be updated together whenever a translation key is added or changed.

---

## Optional Shared Docs

Three templates ship in `.claude/` as `*.example.md`. Each covers a capability this config can use
but does not require. **Fill one in, rename it to drop `.example`, then uncomment its import line
below.** Delete the ones you do not need — an unfilled template is worse than an absent one,
because an agent will try to use it.

| Template                        | Covers                                                        | Delete it if                       |
| ------------------------------- | ------------------------------------------------------------- | ---------------------------------- |
| `DATABASE.example.md`           | Database access over MCP — topology, tunnel, production rules | You give agents no database access |
| `OPENPANEL.example.md`          | Analytics read API — base URL, auth headers, worked example   | You have no analytics backend      |
| `SERENA-WORKSPACE.example.md`   | Multi-repo symbol-search scoping                              | You work in a single repo          |

```
<!-- @.claude/DATABASE.md -->
<!-- @.claude/ANALYTICS.md -->
<!-- @.claude/SERENA-WORKSPACE.md -->
```

> Note what these three are. They are **not** neutral reference material — `DATABASE.md` in
> particular is the only place recording which production operations are permitted. Treat them as
> operational rules, and review changes to them accordingly.
