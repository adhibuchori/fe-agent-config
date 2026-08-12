# Setup

Ordered by dependency, not by importance. Each step is verifiable before the next one starts, and
the step that can destroy files comes last on purpose.

Budget about an hour. Steps 1–4 are the useful minimum; 5–7 are opt-in.

> **Read this first: the workflows arrive disarmed.**
>
> Every workflow in `.github/workflows/` triggers on `dev` or `prod` only. This repo ships with
> just `main`, so nothing runs, and no secrets are needed. They activate when you create those two
> branches in your own repo — deliberately, because a quality gate has nothing to guard until there
> is a branch to promote into.

---

## 1. Copy the layer in

Copy everything except this file, `README.md`, and `docs/RATIONALE.md`:

```bash
CFG=/path/to/fe-agent-config
cp -R "$CFG"/{.claude,.agent,.agents,_workflow-source,.github,scripts} .
cp "$CFG"/{CLAUDE.md,AGENTS.md,SSOT.md,.mcp.json,oxlint.json,.oxlintignore,.gitleaks.toml} .
```

Then **read `.gitignore`.** `.claude/settings.local.json` and any `.env*` must be ignored before
your first commit, not after.

---

## 2. Fill in every placeholder

Placeholders are named, never blank, so one command gives you the full list:

```bash
grep -rn '<[a-zA-Z][a-zA-Z -]*>' CLAUDE.md AGENTS.md SSOT.md .mcp.json .claude/ .github/
```

Work through it in this order:

| File | What to replace |
| --- | --- |
| `CLAUDE.md` | Project name, stack summary, dev command and port |
| `SSOT.md` §1–§2 | Product context and ecosystem — these are scaffolding, replace them wholesale |
| `SSOT.md` §3–§7 | Stack table, layer map, API contract, env vars — edit in place |
| `.mcp.json` | Environment-variable names for tokens; delete servers you do not use |
| `.github/CODEOWNERS` | `@your-github-handle` |

Three optional shared docs ship as `.claude/*.example.md`. Fill one in, rename it to drop
`.example`, and uncomment its import line at the bottom of `CLAUDE.md`. **Delete the ones you do
not need** — an unfilled template is worse than an absent one, because an agent will try to use it.

### If you route commands through a wrapper

A token-reducing proxy, a sandbox, a recorder. If you have one, declare it in `CLAUDE.md` as a hard
rule and prefix every command in that file with it. Mentioning a wrapper in passing does not work;
it gets dropped the moment a task gets busy. If you have no wrapper, the commands as written are
already correct.

---

## 3. Wire the hooks

`.claude/settings.json` already references all ten. Make them executable and confirm the runtime
picks them up:

```bash
chmod +x .claude/hooks/*.sh
```

**The distinction that matters:** `PreToolUse` hooks can **block** — `exit 1` stops the tool call
before it happens. `PostToolUse` and `Stop` hooks are advisory; a non-zero exit is reported and
ignored. So anything that must not happen belongs in `PreToolUse`, and putting it anywhere else
produces a guard that looks installed and enforces nothing.

**Test a guard by triggering it, never by reading it.** Ask the agent to edit a file the guard
should protect. A guard whose path pattern does not match your layout never fires and never
complains — that is the failure mode, and reading the script will not reveal it.

Then delete what does not apply. `i18n-sync-check.sh` is dead weight in a single-locale app, and a
hook that always passes trains everyone to ignore hook output.

---

## 4. Make the gate runnable

`.github/scripts/quality-gate.sh` is the definition of "passing". It calls package scripts, so
those must exist:

```jsonc
{
  "scripts": {
    "fl:ci": "<format check> && <lint>",
    "type-check": "tsc --noEmit",
    "test:coverage": "<test runner> --coverage",
    "build": "<production build>"
  }
}
```

Run it locally against your base branch before you ever open a pull request:

```bash
bash .github/scripts/quality-gate.sh origin/dev
```

Comment out the steps you have not set up yet, rather than letting them fail. A gate that is red
for reasons everyone knows about is a gate nobody reads.

> `ci-cd.yaml` expects a `Dockerfile` and a deploy webhook, neither of which ships here — that part
> is yours. If you deploy differently, replace the workflow rather than editing around it.

---

## 5. Slash commands and their mirrors — optional

Commands are maintained **once** in `_workflow-source/` and mirrored into `.claude/commands/` and
`.agent/workflows/`.

```bash
bash scripts/sync-workflows.sh           # write the mirrors
bash scripts/sync-workflows.sh --check   # verify without writing — this is the CI mode
```

`--check` is the mode that catches drift, and the reason is worth internalising: a write-mode run
**overwrites staleness before it can observe it**. Wire `--check` into your gate; wire the write
mode into nothing.

`.agent/workflows/` exists for a second tool that reads commands from that path. **If no such tool
is in use, delete it** — it is a dozen files kept in sync for a reader who does not exist. Do that
knowingly rather than inheriting it.

---

## 6. Third-party skills — optional, not vendored

Neither is included here. Both are installed by their own tooling, which owns their versioning.

| Skill | What it is | Install |
| --- | --- | --- |
| [`impeccable`](https://github.com/pbakaus/impeccable) | Interface design and polish — audit, critique, polish intents | `npx impeccable install` |
| `react-doctor` | Framework health checks: security, performance, accessibility, architecture. Advisory, never fails a build | Ships as a skill plus `.github/workflows/react-doctor.yml` |

**One thing to know before you add any drift checker of your own:** an installer that writes into
`.claude/skills/`, `.agents/skills/`, and `.claude/commands/` leaves files with no counterpart in
your source directory. A naive checker flags them as orphans and advises deleting or relocating
them, which breaks the next upgrade. `scripts/sync-workflows.sh` handles this with an explicit
`VENDORED` exemption list — copy that pattern.

---

## 7. The AI-config strip pipeline — last, and only if you want it

**This is the only part that deletes files. Everything else should be working before you touch it.**

The idea: your production branch carries no agent configuration at all. Rules, hooks, subagents,
and MCP config exist on `dev` and are removed on the way to `prod`.

Four scripts, and the ordering between them is the whole design:

| Script | Role |
| --- | --- |
| `strip-paths.sh` | **The single source of truth** for what gets removed. The other three source it |
| `strip-ai.sh` | Removes those paths on the production branch |
| `verify-strip.sh` | Asserts they are gone from `prod` **and still present on `dev`** |
| `back-merge-prod.sh` | Merges `prod` back into `dev` so the branches do not diverge |

Three things that are not obvious, each of which has already cost someone a debugging session:

**One list, sourced — never copied.** When `STRIP_PATHS` was duplicated across scripts, updating
one and not the others made the strip half-land: production kept part of the config and nothing
reported an error.

**Verify both directions.** Checking only that `prod` lost the files misses the failure where `dev`
lost them too. `verify-strip.sh` asserts both, and only the second assertion catches that.

**Merge, never rebase, on the way back.** `back-merge-prod.sh` merges deliberately. Rebasing rewrites
the strip commit and the branches diverge permanently.

Adopt it in this order:

1. Run `strip-ai.sh` on a throwaway branch and inspect what disappeared.
2. Run `verify-strip.sh` and confirm it fails when you deliberately skip a path.
3. Only then wire it into `strip-ai-on-pr.yml`.

---

## Verify the whole thing

```bash
grep -rn '<[a-zA-Z][a-zA-Z -]*>' CLAUDE.md AGENTS.md SSOT.md   # nothing unfilled
bash .github/scripts/check-comment-blocks.sh                   # exits 0
bash scripts/sync-workflows.sh --check                         # mirrors in sync
bash .github/scripts/quality-gate.sh origin/dev                # the real gate
```

Then the test no script performs: open a session and ask the agent to do something a rule forbids.
If it proceeds, the rule is prose rather than a guardrail — move it into a `PreToolUse` hook or a
gate step, and treat that as the general remedy whenever a rule is not holding.
