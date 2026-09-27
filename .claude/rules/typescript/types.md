---
paths:
  - '**/*.ts'
  - '**/*.tsx'
  - '**/*.mts'
  - '**/*.cts'
---

# No `any` (TypeScript)

When `AGENTS.md` carries a numbered no-`any` rule, it says the same; this file is what loads while
you edit TypeScript.

- No explicit `any`: not `: any`, `as any`, `any[]`, `Record<string, any>`, `Promise<any>`, nor a
  generic that defaults to it. Enforced by oxlint `typescript/no-explicit-any` at **error**, in
  tests too.
- No way around the gate: no `oxlint-disable` or `eslint-disable` for this rule (oxlint honours
  both), and no `any` smuggled in through a type alias or a dependency's loose re-export.
- Untrusted or external data is `unknown`, then narrowed with a type guard or parsed with Zod.
  A type that depends on the caller is a generic.
- A third-party signature that seems to demand `any` gets a typed adapter at the boundary — the
  one place that knows the library's shape — never a cast in feature code.
- No double assertion through `unknown` (`x as unknown as T`): it switches off the overlap check a
  single `as` still makes. `scripts/check/double-assertion.sh` refuses it in pre-commit and CI.
- A test fake is a real object (a jsdom element, `new Request`, the web framework's own request
  context, the auth library's real context built by a shared test helper), a complete fixture from
  a factory, or a builder in the shared test helpers folder. When production code only reads part
  of a type, narrow the parameter to `Pick<...>` instead of faking the whole.
