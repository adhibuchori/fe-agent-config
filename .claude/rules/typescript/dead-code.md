---
paths:
  - '**/*.ts'
  - '**/*.tsx'
  - '**/*.mts'
  - '**/*.cts'
  - '**/*.mjs'
  - 'knip.ts'
  - 'package.json'
---

# Dead code (TypeScript)

Blocking in pre-commit and the Quality Gate.

- Knip (`check:dead-code`, config in `knip.ts`) reports unused files, exports, types,
  dependencies and unlisted or unresolved imports. Where React Doctor also runs, its own dead-code
  pass is off (`doctor.config.json`), so Knip is the one source.
- A finding is fixed, not silenced. Unused anywhere: delete it. Used only in its own file: drop
  `export`. Reached by a convention or a config the tool cannot follow: add it to Knip's `entry`
  with a comment saying which. Generated or vendored: ignore it by its narrowest path.
- Never ignore a file or `ignoreDependencies` a package because it "might be used later".
- `knip --fix` edits many files at once: read its diff before committing, and rerun type-check,
  lint and tests, because deleting one export can orphan an import the linter then refuses.
