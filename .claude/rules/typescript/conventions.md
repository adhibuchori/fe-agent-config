---
paths:
  - 'src/**/*.ts'
  - 'src/**/*.tsx'
---

# TypeScript Conventions

This repo's conventions for TypeScript source. The ban on `any` is `typescript/types.md` (`AGENTS.md`
Rule 31).

## React Compiler

React Compiler is active: never add `useMemo`, `useCallback` or `memo()` speculatively.

## JSDoc Convention

Every exported function or component must have exactly one JSDoc block, placed immediately above the symbol it describes:

```ts
/** {Type}: {Name}
 * {One sentence description.}
 */
```

Placement is anchored to the symbol, not to the imports: the block goes directly above the `export function` it describes, even when other declarations sit between that function and the import list. Multi-export files give each symbol its own description. That matters because the docs site reads per symbol — without it, every component in a shared file publishes the same invented prose.

Out of scope, and needing no block of their own:

- Data constants, matching the JSDoc Presence Check step in `.github/scripts/quality-gate.sh`.
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

## Naming Conventions

| Type        | Convention                         | Example                                              |
| ----------- | ---------------------------------- | ---------------------------------------------------- |
| Components  | kebab-case file, PascalCase export | `settings-card.tsx` → exports `SettingsCard`         |
| Hooks       | camelCase                          | `useScrollPosition.ts` → exports `useScrollPosition` |
| Directories | kebab-case                         | `src/components/`                                    |
| Constants   | kebab-case                         | `src/lib/constants/navigation/routes.ts`             |
| Types       | kebab-case                         | `src/types/user.ts`                                  |
