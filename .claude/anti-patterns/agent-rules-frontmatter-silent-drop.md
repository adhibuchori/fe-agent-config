# Antigravity rule frontmatter fails silently

**Applies to:** `.agents/rules/*.md` and anything generating them (`scripts/sync-rules.sh`)
**Discovered:** 2026-08-07
**Status:** Permanent (Antigravity parser behaviour)

## Symptom

A rule file exists on disk, looks correct, and is valid Markdown — but never appears in
Customizations → Rules, or appears with its Glob Pattern field empty. **No error is shown
anywhere.** The only signal is a missing row in a panel you have to open manually.

## Root cause

Three distinct failures, all of which produce a file that _looks_ fine:

### 1. Unquoted `: ` in `description:` — rule is dropped entirely

```yaml
# BROKEN — ": severity" opens a nested mapping, YAML parse fails, rule vanishes
description: Read before reviewing code or marking a task done: severity levels, approval criteria.

# CORRECT
description: "Read before reviewing code or marking a task done: severity levels, approval criteria."
```

### 2. Glob patterns as a YAML list — rule loads but matches nothing

The Glob Pattern input is a **single 250-character text field**, not a list. A YAML list parses
fine and leaves the field empty, so the rule never activates.

```yaml
# BROKEN — valid YAML, empty field, never triggers
globs:
  - '**/*.tsx'
  - 'next.config.ts'

# CORRECT — one comma-separated string, quoted (a bare leading `*` is a YAML alias)
globs: '**/*.tsx, next.config.ts'
```

### 3. Unquoted shell variable expands globs against the working tree

Building that string with `printf '%s, ' $patterns` runs pathname expansion, so `src/hooks/**`
becomes every file it currently matches. Observed output included `node_modules/decimal.js` and
`coverage/prettify.js`, and one rule blew past the 250-char cap at 554.

Join with a `while IFS= read -r` loop, or wrap in `set -f` — the same guard
`.github/scripts/strip-ai.sh` already uses for its pathspec list.

## Fix

Never hand-edit `.agents/rules/`. Edit `.claude/rules/` and run `bun sync:rules`.
`scripts/sync-rules.sh` quotes every value by construction, joins patterns without expansion, and
fails hard past 250 chars. Its `validate_fm()` re-reads what it emitted and rejects any
frontmatter line that is not `trigger: <mode>` or `key: "<quoted>"`.

## Verified format

| Field         | Value                                                       |
| :------------ | :---------------------------------------------------------- |
| Directory     | `.agents/rules/` — note the `s`, unlike `.agent/workflows/` |
| Trigger modes | `always_on` · `model_decision` · `glob` · `manual`          |
| `description` | Required for `model_decision`. Always quote it.             |
| `globs`       | Comma-separated string, max 250 chars. Always quote it.     |
| Content limit | 12,000 characters per rule, frontmatter excluded            |

## Scope

Antigravity IDE only. Claude Code reads `.claude/rules/` and is unaffected.
Both directories are already in `STRIP_PATHS`, so neither reaches prod.
