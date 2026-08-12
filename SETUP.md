# Setup

Ordered by dependency, not by importance. Each step is verifiable before the next one starts, and
the step that can destroy files comes last on purpose.

Budget about an hour. Steps 1–5 are the useful minimum; 6–8 are opt-in.

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

---

## 3. Agent tooling — MCP servers, wrappers, plugins

This is what the agent actually reaches for on every task. Hooks stop bad edits; **this decides how
well it works in the first place**, so it is worth ten minutes even though nothing breaks if you
skip it.

### Every tool by name, and where it is covered

Search this table first — several tools below are discussed under generic headings, so their names
only appear in prose.

| Tool | What it is | Ships here? | Covered in |
| :-- | :-- | :-- | :-- |
| **Serena** | Semantic code search and edit over a language server | `.mcp.json` | [below](#serena--install-it-or-delete-the-rules-that-assume-it) |
| **Context7** | Live library documentation lookup | `.mcp.json` | server table below |
| **GitHub MCP** | Pull requests, issues, and reviews inside a session | `.mcp.json` | server table below |
| **Postgres MCP** | Database schema, health, and query plans (`db-dev`, `db-prod`) | `.mcp.json` | server table below · `DATABASE.example.md` |
| **Dokploy · Cloudflare · Hostinger** | Deployment, DNS, and VPS control | `.mcp.json` | server table below — delete if not your vendors |
| **RTK** | Token-reducing shell proxy | **No** — machine-local | [Command wrappers](#command-wrappers--rtk-or-your-own) |
| **Ponytail** | Context-trimming plugin | **No** — machine-local | [Plugins](#plugins--ponytail-or-your-own) |
| **DeepSeek Code Review** | AI review comment on pull requests | `.github/workflows/` | [below](#ai-code-review-on-pull-requests--deepseek) · README § GitHub configuration |
| **react-doctor** | Framework health checks — advisory only | Workflow only | §7 |
| **impeccable** | Interface design and polish skill | **No** — own installer | §7 |

### The servers in `.mcp.json`

Eleven ship. **Most projects should delete most of them.** Every connected server spends context on
its tool definitions before you have asked anything, so an unused server is a permanent tax.

| Server | What it gives the agent | Needs | Keep it if |
| :-- | :-- | :-- | :-- |
| `serena` | Semantic code search and edit over a language server — find a symbol, its references, its implementations, rename it safely | `uvx` ([Astral uv](https://github.com/astral-sh/uv)). No token | **Almost always.** See below |
| `context7` | Current library documentation, fetched live | `npx`. No token | You use libraries that moved recently |
| `github` | Pull requests, issues, reviews, and branches from inside a session | `GITHUB_PERSONAL_ACCESS_TOKEN` | You want the agent to open and read pull requests |
| `db-dev` · `db-prod` | Query and inspect a database — schema, health, index advice, query plans | `DB_DEV_URI` / `DB_PROD_URI`, plus a tunnel if the port is not public | The agent should debug against a real schema |
| `dokploy-mcp` | Deployment platform control — applications, deploys, logs, backups | `DOKPLOY_URL`, `DOKPLOY_API_KEY` | You deploy with Dokploy. Otherwise **delete** |
| `cloudflare` | DNS, Workers, and account resources | OAuth in an interactive session | You use Cloudflare. Otherwise **delete** |
| `hostinger-hosting` · `-domains` · `-dns` · `-vps` | VPS, domain, and DNS management | `HOSTINGER_API_TOKEN` | You host with Hostinger. Otherwise **delete all four** |

Deleting a server is just removing its object from `.mcp.json`. Nothing else references them.

> **The four infrastructure servers are vendor-specific and are the first things to cut.** They are
> in here because the project this was extracted from uses those vendors, not because the layer
> needs them. Replace them with your own provider's server, or run with none — the gate, the hooks,
> and the rules do not care.

### Serena — install it, or delete the rules that assume it

`CLAUDE.md` § Tool Priority contains a **strict enforcement block**: always use Serena for code
files, never use the built-in file readers for them. That block is the single largest behavioural
instruction in the file.

**If Serena is not installed, that instruction is telling your agent not to read your code.** The
block does have a documented fallback — report the failure, log it, then use built-in tools — so it
degrades rather than deadlocks. But you get a warning on every task and a confused agent.

So pick one, deliberately:

```bash
# Install uv, which provides uvx. The server itself needs no separate install —
# the .mcp.json entry fetches it on first run.
curl -LsSf https://astral.sh/uv/install.sh | sh
```

**Or** delete the § Tool Priority section from `CLAUDE.md` and the `serena` entry from `.mcp.json`,
together. Deleting one without the other is the failure case.

Two details in the shipped configuration worth knowing:

**`ENABLE_TOOL_SEARCH: "true"`** defers Serena's tool definitions until they are needed. It cuts the
per-session cost substantially. The trade-off: Serena's own instructions are deferred too, so the
session must call `initial_instructions` once before its first symbol search — which is exactly what
`CLAUDE.md` § Session Start already mandates.

**The `alwaysAllow` list** pre-approves Serena's read and edit tools so you are not answering a
permission prompt every few seconds. Read it before adopting it: it includes symbol editing and
deletion. Trim it if that is more trust than you want to extend by default.

### If you work across several repositories at once

`.claude/SERENA-WORKSPACE.example.md` covers running one Serena project spanning several repos, so
symbol search reaches all of them. It is genuinely useful on a multi-repo product and pure overhead
on a single repo.

Fill it in only if you need it; otherwise delete the file. Two things it will save you: the
umbrella is machine-local configuration that a fresh clone does not inherit, and path prefixes
resolve against the umbrella root rather than your repo — which fails loudly, but only if you know
to expect it.

### Command wrappers — RTK, or your own

If you route shell commands through a wrapper — a token-reducing proxy such as **RTK**, a sandbox,
an audit recorder — declare it in `CLAUDE.md` § Command Wrapper **as a hard rule**, and prefix every
command in that file with it.

The reference project uses one, and it was stripped from this layer on purpose: it is machine-local
tooling that a fresh clone will not have, and a rule pointing at a missing binary fails every
command. The **shape** is left in place so you can slot yours in.

Why it has to be a hard rule rather than a note: a wrapper mentioned in passing gets dropped the
moment a task gets busy, and then half your commands are wrapped and half are not — which is worse
than never wrapping at all, because the numbers stop meaning anything.

### Plugins — Ponytail, or your own

`.claude/settings.json` ships with **no plugins enabled**, and that is deliberate rather than an
oversight.

The reference project runs one — **Ponytail**, which trims context — configured through
`enabledPlugins` plus a couple of environment variables. It was removed here for the same reason as
the command wrapper: a plugin declared but not installed is a startup error for everyone who clones
this.

If you use plugins, they go in the same file:

```jsonc
{
  "enabledPlugins": { "<plugin>@<source>": true },
  "env": { "<PLUGIN_SETTING>": "<value>" }
}
```

Keep them out of `.claude/settings.local.json` if the whole team should get them, and in it if the
choice is yours alone. The `.gitignore` here already excludes the local file.

### AI code review on pull requests — DeepSeek

`.github/workflows/deepseek-review.yml` posts an AI review comment on pull requests into `dev`,
using [`hustcer/deepseek-review`](https://github.com/hustcer/deepseek-review) — which accepts any
OpenAI-compatible endpoint, so the provider is your choice despite the name.

Setup is one secret, and it is covered in **README § GitHub repository configuration**, together
with the security constraint that matters: the workflow runs under `pull_request_target` with your
repository secrets in scope, and **must never check out the pull request's code**.

---

## 4. Wire the hooks

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

## 5. Make the gate runnable

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

## 6. Slash commands and their mirrors — optional

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

## 7. Third-party skills — optional, not vendored

Neither is included here. Both are installed by their own tooling, which owns their versioning.

| Skill | What it is | Install |
| --- | --- | --- |
| [`impeccable`](https://github.com/pbakaus/impeccable) | Interface design and polish — audit, critique, polish intents | `npx impeccable install` |
| `react-doctor` | Framework health checks: security, performance, accessibility, architecture. **Advisory — never fails a build, so do not make it a required status check** | The workflow ships (`.github/workflows/react-doctor.yml`) and runs standalone. Its companion skill does **not** ship — install that separately if you want `/doctor` in a session |

**One thing to know before you add any drift checker of your own:** an installer that writes into
`.claude/skills/`, `.agents/skills/`, and `.claude/commands/` leaves files with no counterpart in
your source directory. A naive checker flags them as orphans and advises deleting or relocating
them, which breaks the next upgrade. `scripts/sync-workflows.sh` handles this with an explicit
`VENDORED` exemption list — copy that pattern.

---

## 8. The AI-config strip pipeline — last, and only if you want it

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
