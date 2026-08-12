<div align="center">

# fe-agent-config

**A complete, runnable AI agent configuration layer for a frontend repository.**

Rules, blocking hooks, scoped subagents, slash commands, a 14-step CI quality gate, and a pipeline
that strips the entire layer out of production branches.

Not advice about writing rules. The rules themselves, in the form that executes.

[Setup](SETUP.md) · [Rationale](docs/RATIONALE.md) · [Backend](https://github.com/adhibuchori/be-agent-config) · [Docs site](https://github.com/adhibuchori/docs-agent-config)

</div>

---

## Table of contents

- [The problem this solves](#the-problem-this-solves)
- [The four layers](#the-four-layers)
- [What ships](#what-ships)
- [Repository structure](#repository-structure)
- [Quick start](#quick-start)
- [What is deliberately excluded](#what-is-deliberately-excluded)
- [Requirements](#requirements)
- [Adapting it to your stack](#adapting-it-to-your-stack)
- [Design decisions worth knowing before you edit](#design-decisions-worth-knowing-before-you-edit)
- [FAQ](#faq)
- [License](#license)

---

## The problem this solves

Most AI agent configuration is prose. You write `AGENTS.md`, list your conventions, and hope the
agent reads it. Some days it does.

Prose has no failure mode. When a rule is ignored, nothing reports it — the code just lands, and
you find out in review, or later. So the rule quietly becomes a suggestion, and the document
becomes something people stop maintaining because it stopped mattering.

This layer takes the opposite position: **a rule that cannot fail is not a rule.** Every convention
here is attached to something that exits non-zero — a hook that blocks the tool call before it
happens, a gate step that fails the pull request, or an explicitly labelled `advisory` when no
mechanism exists. Nothing sits in between, unenforced and assumed.

The prose is still here. It is just no longer the enforcement.

---

## The four layers

Each has one job. Keeping them separate is what stops any of them growing into an unreadable
9,000-word document that agents skim and humans stop updating.

| Layer | File | Job | Size |
| :-- | :-- | :-- | --: |
| **Router** | `CLAUDE.md` | What to read for which task. Loaded every session, so kept short on purpose | 283 lines |
| **Guardrail** | `AGENTS.md` | Numbered, citable rules. A review can say "Rule 12" and mean one specific thing | 335 lines |
| **Contract** | `SSOT.md` | What the codebase *is*: layers, naming, API contract, environment | 309 lines |
| **Machine** | `.claude/`, `.mcp.json` | Hooks, subagents, anti-patterns, rule tiers, MCP servers | 60 files |
| **Gate** | `.github/` | The definition of "passing", enforced on every pull request | 5 workflows |

The split matters more than it looks. `CLAUDE.md` is read in full on every single session, so every
line you add there is a permanent tax. `AGENTS.md` is read when a rule is in question. `SSOT.md` is
read when orientation is needed. Collapsing them means paying the full cost every time.

---

## What ships

### Hooks — 9 scripts, plus a shared library

The distinction that governs everything else:

| Type | Non-zero exit means |
| :-- | :-- |
| `PreToolUse` | **The tool call does not happen.** A real guardrail |
| `PostToolUse` | Reported, then ignored. The write already landed |
| `Stop` | Reported, then ignored |

Three `PreToolUse` guards block: edits to generated output, unsafe shell commands, and token leaks.
Four `PostToolUse` hooks format, lint, run tests, and check translation-key parity after the fact.

Anything that must not happen belongs in `PreToolUse`. Put it anywhere else and you get a guard
that looks installed, logs complaints, and prevents nothing.

### Rules — 26 files across 4 tiers

```
.claude/rules/
├── common/       9 files   language-agnostic — transfers as is
├── typescript/   5 files   delete if you are not on TypeScript
├── react/        5 files   delete if you are not on React
└── web/          7 files   delete if this is not a web frontend
```

Each tier is self-contained and extends the one above it. Delete a tier outright rather than
half-editing it — a rule file that contradicts your stack is worse than no rule file.

### Subagents — 4, each narrowly scoped

| Agent | Scope |
| :-- | :-- |
| `sc-reviewer` | Separation of concerns, styling, compiler rules, file length, documentation blocks |
| `sc-i18n-guard` | Translation-key parity between locales; hardcoded UI strings |
| `sc-security-guard` | Content-Security-Policy integrity, secret hygiene, XSS prevention |
| `sc-seo-validator` | Metadata completeness, structured data, Open Graph |

Four narrow agents rather than one broad one, deliberately. A reviewer asked to check everything
returns five vague observations; a reviewer asked to check one thing returns one specific finding
you can act on.

### Slash commands — 16, maintained once

Sources live in `_workflow-source/` and are mirrored into `.claude/commands/` and
`.agent/workflows/` by `scripts/sync-workflows.sh`, with drift detection in `--check` mode.

Covers planning, review, commit, pull-request creation, promotion between branches, review-comment
resolution, branch cleanup, accessibility audit, and session checkpointing.

### Quality gate — 14 steps

`.github/scripts/quality-gate.sh` is the definition of "passing":

format · lint · type check · comment style · comment block length · workflow mirror drift ·
security audit · `.env` not committed · secret scan · tests with coverage · documentation-block
presence · AI config rule drift · production build · source-map leak check

Runs identically on your machine and in CI, so a red pull request is never a surprise.

### AI-config strip pipeline

Four scripts that remove this entire layer from the production branch, so the deployed artifact
carries no agent configuration at all. `strip-paths.sh` is the single source of truth for what gets
removed; the other three source it rather than copying the list.

### Anti-patterns — 5 documented failures

Real incidents, each with the trigger keyword that should surface it before it recurs. An empty
anti-patterns directory teaches nothing, so these ship populated.

---

## Repository structure

```
fe-agent-config/
├── CLAUDE.md                    Router — what to read for which task
├── AGENTS.md                    Guardrail — numbered, citable rules
├── SSOT.md                      Contract — layers, naming, API, environment
├── SETUP.md                     Ordered installation guide
├── LICENSE                      MIT License
├── .mcp.json                    11 MCP servers, neutral env-var names
├── oxlint.json · .oxlintignore  Lint configuration the gate calls
├── .gitleaks.toml               Secret-scan configuration
│
├── .claude/
│   ├── settings.json            Hook wiring, permission allow/deny lists
│   ├── rules/                   26 files · common → typescript → react → web
│   ├── agents/                  4 subagents + INDEX.md
│   ├── anti-patterns/           5 documented failures + INDEX.md
│   ├── hooks/                   9 scripts + lib.sh
│   ├── commands/                16 slash commands (generated)
│   ├── session-feedback/        Behavioural guidance + worked example
│   ├── serena-errors.md         Tool-failure log with its recovery protocol
│   └── *.example.md             3 optional shared docs — fill in or delete
│
├── .agent/workflows/            Command mirror for a second tool (generated)
├── .agents/rules/               Rule mirror for a second tool (generated)
├── _workflow-source/            16 command sources + INDEX.md — edit here
│
├── scripts/
│   ├── sync-workflows.sh        Mirror commands, with --check drift mode
│   ├── sync-rules.sh            Mirror rules, with --check drift mode
│   ├── check-i18n.ts            Translation-key parity
│   ├── env.ts                   Environment-variable validation
│   └── audit-check.ts           Dependency audit wrapper
│
├── .github/
│   ├── workflows/               quality-gate · ci-cd · strip-ai-on-pr
│   │                            deepseek-review · react-doctor
│   ├── scripts/                 quality-gate.sh · strip-paths.sh · strip-ai.sh
│   │                            verify-strip.sh · back-merge-prod.sh
│   │                            check-comment-blocks.sh · check-comment-style.ts
│   ├── PULL_REQUEST_TEMPLATE/   dev.md · promotion.md
│   ├── CODEOWNERS · dependabot.yml
│
└── docs/RATIONALE.md            Why the odd-looking parts are shaped that way
```

**160 files. No application source code.**

---

## Quick start

```bash
git clone https://github.com/adhibuchori/fe-agent-config.git
cd your-project

CFG=../fe-agent-config
cp -R "$CFG"/{.claude,.agent,.agents,_workflow-source,.github,scripts} .
cp "$CFG"/{CLAUDE.md,AGENTS.md,SSOT.md,.mcp.json,oxlint.json,.oxlintignore,.gitleaks.toml} .

# Placeholders are named, never blank — this is your complete to-do list
grep -rn '<[a-zA-Z][a-zA-Z -]*>' CLAUDE.md AGENTS.md SSOT.md .mcp.json .claude/

chmod +x .claude/hooks/*.sh
```

Then follow **[SETUP.md](SETUP.md)** — ordered by dependency, about an hour end to end. The step
that can delete files comes last on purpose.

---

## What is deliberately excluded

**No application source.** No `src/`, no components, no generated API client, no `package.json`, no
lockfile, no `Dockerfile`. This is configuration, not a starter project.

**No third-party skills.** Design and framework-health skills are documented in `SETUP.md` with
their installers rather than vendored. Two hundred files that go stale, are not ours to
redistribute, and whose own installer owns their versioning.

**No secrets, and none required.** Every credential in `.mcp.json` is an environment-variable
reference. Nothing here needs a secret to run.

---

## Requirements

Nothing is mandatory. Every piece degrades to "delete this file" rather than breaking the rest.

| For | You need |
| :-- | :-- |
| Hooks, commands, subagents | An agent runtime that reads `.claude/` and `AGENTS.md` |
| The quality gate | GitHub Actions, plus package scripts named in `SETUP.md` §4 |
| Deployment workflow | A `Dockerfile` and a deploy target — neither ships here |
| MCP servers | The env vars named in `.mcp.json`; delete the servers you do not use |
| Second-tool mirrors | A second tool that reads `.agent/` or `.agents/`. If none, delete both |

---

## Adapting it to your stack

The rules are written against a concrete stack — Next.js, React, TanStack Query, next-intl —
deliberately. A rule genericised into `{{QUERY_LIBRARY}}` is unusable until filled in, and most
people never fill it in.

Adapt by **tier**, not by line:

- `.claude/rules/common/` transfers unchanged to any language.
- `typescript/`, `react/`, `web/` are progressively more specific. Replace a whole tier when it
  does not apply.
- `AGENTS.md` sections map one-to-one onto the tiers. Delete a section with its tier.

The `sc-` prefix on subagents is only a namespace, so project agents sort together and never
collide with built-ins. Rename it to your own initials.

---

## Design decisions worth knowing before you edit

Full detail in **[docs/RATIONALE.md](docs/RATIONALE.md)** — 14 entries, each one something that
cost someone real time. Several patterns here look like clutter and are load bearing. The four that
catch people most often:

**Comma-separated globs stay in one string.** A YAML list looks tidier and stops the rule matching
any file — with no error, no warning, and nothing in the logs.

**`--check` mode exists because write mode cannot replace it.** A write-mode sync run overwrites
staleness before it can observe it. Wire `--check` into CI; wire the write mode into nothing.

**`pull_request_target` runs with your repository secrets.** The AI review workflow uses it to post
comments, and therefore must never check out the pull request's code.

**The strip pipeline verifies both directions.** Checking only that production lost the files
misses the failure where the development branch lost them too.

---

## FAQ

**Will cloning this run any GitHub Actions?**
No. Every workflow triggers on `dev` or `prod`, and this repo has only `main`. Nothing runs on
push and no secrets are needed. They activate when you create those branches in your own repo —
the right order, since a gate has nothing to guard until then.

**Do I have to adopt all of it?**
No, and you should not start by trying. `SETUP.md` §1–§4 is the useful minimum: rules, hooks, and
the gate. The strip pipeline is optional and comes last because it is the only part that deletes
files.

**Is this specific to one agent runtime?**
The rules, gate, and scripts are portable. The hook wiring in `.claude/settings.json` and the
`.mcp.json` format target Claude Code. The `.agent/` and `.agents/` mirrors exist for a second tool
that reads from those paths — delete them if you use only one tool.

**Why is there no `package.json`?**
Because that would make this a starter project rather than a configuration layer. `SETUP.md` §4
lists exactly the four scripts the gate calls, so you can add them to whatever you already have.

**What about a documentation-site repo?**
Use [`docs-agent-config`](https://github.com/adhibuchori/docs-agent-config) instead. A docs site is
this layer with a smaller footprint — no `AGENTS.md`, no `SSOT.md`, only the `common/` and `web/`
rule tiers, two of the four subagents — plus a content pipeline and a changelog workflow that have
no equivalent here. It ships ready to clone rather than requiring you to delete half of this one.

---

## License

MIT License. See [LICENSE](LICENSE).
