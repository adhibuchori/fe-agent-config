# Git Workflow

## Commit Message Format

```
<type>: <description>

<optional body>
```

Types: feat, fix, refactor, docs, test, chore, perf, ci

Note: commits carry a `Co-Authored-By: Claude <model> <noreply@anthropic.com>` trailer.
`includeCoAuthoredBy` is unset in both `~/.claude/settings.json` and `.claude/settings.json`, so
Claude Code's default applies and attribution is **on** — set it to `false` in settings to stop it.

## Branch Naming

```
internal/{scope}            single task
internal/{scope}/{context}  parallel tasks in the same scope
```

Merge order: `internal/{scope}/{context}` → `internal/{scope}` → `dev` → `prod`. Branch off
`dev`; never push directly to `dev` or `prod`. See CLAUDE.md § Branching for what each level
is for.

## Pull Request Workflow

When creating PRs:

1. Analyze full commit history (not just latest commit)
2. Use `git diff [base-branch]...HEAD` to see all changes
3. Draft comprehensive PR summary
4. Include test plan with TODOs
5. Push with `-u` flag if new branch

> For the full development process (planning, TDD, code review) before git operations,
> see [development-workflow.md](./development-workflow.md).
