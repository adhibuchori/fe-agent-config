# Explaining and configuring rules

Explain React Doctor rules and edit `doctor.config.*` safely. Use this when a user
wants to understand a rule or change which rules run — not for fixing diagnostics
(that is the main `react-doctor` skill / `/react-doctor`).

Adapted from React Doctor's own `references/explain.md` (Modified MIT License, see
[../LICENSE](../LICENSE)); the commands are pinned and scans keep their results local.

Triggers: "why did this rule fire", "I disagree with this rule", "turn this rule off",
"stop flagging X", "too noisy", "disable design rules".

## Workflow

1. Identify the rule key from the diagnostic (e.g. `react-doctor/no-array-index-as-key`).
2. Explain it before changing anything:

   ```bash
   bunx react-doctor@0.9.14 --no-score rules explain react-doctor/no-array-index-as-key
   ```

3. Pick the narrowest control that matches the user's intent (see decision guide).
4. Apply it with a `rules` subcommand (edits your `doctor.config.*` or `package.json#reactDoctor` in place, preserving other fields and formatting).
5. Validate the change did what they wanted:

   ```bash
   bunx react-doctor@0.9.14 --no-score --no-supply-chain --verbose --scope changed
   ```

## Commands

```bash
bunx react-doctor@0.9.14 --no-score rules list                         # every rule + its effective severity
bunx react-doctor@0.9.14 --no-score rules list --configured            # only what your config changed
bunx react-doctor@0.9.14 --no-score rules list --category Performance  # filter by category
bunx react-doctor@0.9.14 --no-score rules explain <rule>               # why it matters + how to configure
bunx react-doctor@0.9.14 --no-score rules disable <rule>               # rule never runs
bunx react-doctor@0.9.14 --no-score rules enable <rule>                # turn back on at its recommended severity
bunx react-doctor@0.9.14 --no-score rules set <rule> warn              # off | warn | error
bunx react-doctor@0.9.14 --no-score rules category "React Native" off  # whole category
bunx react-doctor@0.9.14 --no-score rules ignore-tag design            # skip a rule family (design, test-noise, …)
bunx react-doctor@0.9.14 --no-score rules unignore-tag design
```

`--no-score` keeps every run's telemetry and crash reports on the machine, not only scans'
(`../SKILL.md` § Keep scans local).

Rule references accept the full key (`react-doctor/no-danger`), the bare id (`no-danger`), or a legacy key (`react/no-danger`).

## Decision guide

Match the control to the intent — prefer the narrowest one:

- **User disagrees with one rule / it's a false positive for them** → `rules disable <rule>` (sets `rules.<key> = "off"`; the rule stops running everywhere). This is the default for "I don't want this rule".
- **Rule is fine but wrong severity** → `rules set <rule> warn` or `rules set <rule> error`.
- **A disabled-by-default rule they want on** → `rules enable <rule>`.
- **A whole area is unwanted** (e.g. all React Native rules) → `rules category "<Category>" off`.
- **A behavioral family is noisy** (`design`, `test-noise`, `migration-hint`) → `rules ignore-tag <tag>`.
- **Keep it locally but hide from PR comment / score / CI gate only** → do NOT disable. Edit `surfaces` in your config (`surfaces.prComment.excludeRules`, `surfaces.score.excludeTags`, `surfaces.ciFailure.excludeCategories`). The rule still shows in local `cli` output.
- **Restore test or story findings to production health** → set `surfaces.score.includeFileContexts` or `surfaces.ciFailure.includeFileContexts` to `["test"]`, `["story"]`, or both. Other surface exclusions still apply.

How the layers combine: `ignore.tags` disables every rule carrying that tag **before** linting, so a tagged rule stays off even if `rules`/`categories` set it to `warn`/`error` (a rule-level override cannot re-enable a tag-ignored rule). For rules that aren't tag-disabled, `rules` overrides `categories` overrides the rule's default. `surfaces` is visibility-only and never changes whether a rule runs.

## Config shape

Config lives in `doctor.config.ts` (or `.js`/`.mjs`/`.cjs`/`.json`/`.jsonc`), or the `reactDoctor` key in `package.json`. The `rules` commands edit whichever exists — TS/JS edits preserve formatting — and create `doctor.config.json` when none does, stamping `$schema`. This repo's `doctor.config.json` sets `deadCode: false`; keep that key when editing it.

```ts
// doctor.config.ts
export default {
  rules: { 'react-doctor/no-array-index-as-key': 'off' },
  categories: { 'React Native': 'warn' },
  ignore: { tags: ['design'] },
};
```

## Educating the user

When explaining a rule, lead with the "Why it matters" guidance from `rules explain`, then the affected code in this repo. Only after they understand it should you offer to disable it — many "bad" rules are catching real issues.
