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
- [GitHub repository configuration](#github-repository-configuration)
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
| `agents-reviewer` | Separation of concerns, styling, compiler rules, file length, documentation blocks |
| `agents-i18n-guard` | Translation-key parity between locales; hardcoded UI strings |
| `agents-security-guard` | Content-Security-Policy integrity, secret hygiene, XSS prevention |
| `agents-seo-validator` | Metadata completeness, structured data, Open Graph |

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

## GitHub repository configuration

Everything the workflows need, in the order you should set it up. **Nothing here is required to
clone and read the layer** — this is for when you wire the gate into a real repository.

Skip to [the checklist](#checklist) if you just want the list.

### What costs money, and what does not

**Everything required to make this layer work is free.** Only the enforcement layer on top of it is
tier-dependent, and it is tier-dependent in one specific way: **private repositories.**

| Feature | Public repo | Private repo on the free plan |
| :-- | :-- | :-- |
| Actions minutes | Free, unmetered | Monthly allowance, then billed |
| Workflows, secrets, variables | Free | Free |
| Container registry (`ghcr.io`) | Free | Storage allowance, then billed |
| Dependabot alerts + security updates | Free | **Free** |
| Secret scanning + push protection | Free | Paid add-on |
| Code scanning | Free | Paid add-on |
| `CODEOWNERS` auto-review-request | Free | Paid — Pro, Team, or Enterprise |
| **Branch protection / rulesets** | **Free** | **Paid — Pro, Team, or Enterprise** |

So the honest summary:

- **Public repository:** every step below is available to you at no cost.
- **Private repository, free plan:** everything through the container registry works. Branch
  protection does not — see [Nice to have — branch protection](#nice-to-have--branch-protection) below.

> Plans and limits change. Check GitHub's current pricing page before concluding a feature is out
> of reach — this table reflects the tiers at the time of writing, not a promise.

### Step 0 — Create the branches (this is what turns the workflows on)

```bash
git checkout -b dev  && git push -u origin dev
git checkout -b prod && git push -u origin prod
```

Until these exist, **no workflow can trigger** — every one of them is scoped to `dev` or `prod`.
That is why cloning this repo costs zero Actions minutes.

Then set `dev` as the default branch: **Settings → General → Default branch**. Pull requests should
target `dev` by default; `prod` is a promotion target, not a place to open work against.

### Step 1 — Repository secrets

**Settings → Secrets and variables → Actions → New repository secret**

| Secret | Required for | How to get it |
| :-- | :-- | :-- |
| `GITHUB_TOKEN` | everything | **Do not create this.** GitHub injects it automatically per run. It appears in the workflows but never in your settings |
| `NEXT_PUBLIC_API_URL` | `ci-cd.yaml` build args | Your backend's public base URL. Not a secret in the cryptographic sense — it ships in the client bundle — but it belongs here because it differs per environment |
| `NEXT_PUBLIC_APP_URL` | `ci-cd.yaml` build args | This app's own public URL |
| `DOKPLOY_WEBHOOK_URL` | `ci-cd.yaml` deploy job | Dokploy → your application → **Deployments → Webhook URL**. Treat it as a credential: anyone holding it can trigger a deploy |
| `DEEPSEEK_CODE_REVIEW_TOKEN` | `deepseek-review.yml` | See [Step 3](#step-3--ai-review-token-optional) |
| `APP_REPO_TOKEN` | changelog dispatch | See [Step 4](#step-4--cross-repository-token-optional) |

Delete the workflow rather than inventing a value for a secret you do not need. A workflow failing
on a missing secret every single run trains people to ignore red marks.

> The two `NEXT_PUBLIC_*` values are also read by `quality-gate.yaml`, which sets
> `NEXT_PUBLIC_API_URL: http://localhost:4000` inline. The gate builds without a live backend on
> purpose — a gate that needs your infrastructure up is a gate that goes red for reasons unrelated
> to the change under review.

### Step 2 — Repository variables (not secrets)

**Settings → Secrets and variables → Actions → Variables tab**

| Variable | Purpose |
| :-- | :-- |
| `CI_RUNNER` | Runner label. Every job reads `${{ vars.CI_RUNNER \|\| 'ubuntu-latest' }}`, so **leaving it unset is valid** and gives you GitHub's hosted runners. Set it only to point at a self-hosted or third-party runner |

Variables are visible in logs; secrets are masked. A runner label is not sensitive, which is why it
is a variable.

### Step 3 — AI review token (optional)

`deepseek-review.yml` posts an AI review comment on pull requests into `dev`.

1. Create an API key at your provider's console (the shipped workflow uses
   [`hustcer/deepseek-review`](https://github.com/hustcer/deepseek-review), which accepts any
   OpenAI-compatible endpoint).
2. Add it as `DEEPSEEK_CODE_REVIEW_TOKEN`.
3. Confirm **Settings → Actions → General → Workflow permissions** allows pull-request writes, or
   the comment cannot be posted.

> **Read this before enabling it.** The workflow uses `pull_request_target`, which runs with your
> repository secrets in scope so it can comment on fork pull requests. **It therefore must never
> check out the pull request's code.** The shipped workflow reads the diff through the API and does
> not check out. If you modify it, keep that property — adding an `actions/checkout` of the PR ref
> hands your secrets to anyone who opens a pull request.

Two other deliberate details: no `synchronize` in the trigger types (the action has no sticky
comment, so every push would add another review), and `dev` only (a `dev → prod` diff re-adds the
whole stripped AI config and exceeds the provider's diff limit).

Not wiring this up? Delete the workflow file.

### Step 4 — Cross-repository token (optional)

Only if a **separate documentation repository** should regenerate its changelog when this app
deploys. `ci-cd.yaml` fires a `repository_dispatch` at it.

1. Create a **fine-grained personal access token**: your avatar → **Settings → Developer settings →
   Personal access tokens → Fine-grained tokens**.
2. **Resource owner:** the org or account owning the docs repo. **Repository access:** only that
   repo.
3. **Permissions:** `Contents: Read and write` — that is the one `repository_dispatch` requires.
   Nothing else.
4. Add it here as `APP_REPO_TOKEN`, and edit the target URL in `ci-cd.yaml`.

The dispatch step is guarded by `if: env.APP_REPO_TOKEN != ''`, so **leaving the secret unset skips
it silently** rather than failing the deploy. Do not delete the step to disable it.

> Prefer fine-grained over classic tokens, and set an expiry you will actually notice. A classic
> token scoped to `repo` can write to every repository you can reach; this one needs write access
> to exactly one.

### Step 5 — Container registry

`ci-cd.yaml` pushes to **GitHub Container Registry** (`ghcr.io`) and needs no secret — it
authenticates with the injected `GITHUB_TOKEN`. What it does need:

**Settings → Actions → General → Workflow permissions** → **Read and write permissions**.

The workflow also declares `packages: write` at job level. Both are required; the repository-level
setting is a ceiling the job-level declaration cannot exceed.

After the first successful push, the package appears under your profile's **Packages** tab, private
by default. Make it public there if your deploy target pulls it anonymously.

### Step 6 — Dependabot

`.github/dependabot.yml` ships configured. It needs no secret, but it does need
**Settings → Code security → Dependabot alerts** and **security updates** enabled to be useful.

Its pull requests target `dev`, so they run the full gate like any other change.

### Nice to have — branch protection

**This step is optional, and on a private repository it is a paid feature** (GitHub Pro, Team, or
Enterprise). On a public repository it is free.

Everything above works without it. What it adds is the difference between the gate **reporting** a
failure and the gate **preventing** a merge.

If you have it, **Settings → Rules → Rulesets → New branch ruleset**, applied to `dev` and `prod`:

| Setting | Value | Why |
| :-- | :-- | :-- |
| Require a pull request before merging | on | The gate triggers on `pull_request`. Direct pushes bypass it entirely |
| Require status checks to pass | on, select **Quality Gate** | Without this the gate reports and merges anyway |
| Require branches to be up to date | on | Otherwise the gate passes against a stale base |
| Block force pushes | on | The strip pipeline's history is not recoverable from a force push |

> **`react-doctor` is advisory and must not be a required check.** It reports framework health and
> never fails a build; marking it required makes it a blocking gate it was not designed to be.

#### If you do not have it

The gate still runs on every pull request and still shows red or green. What is missing is only the
block. Three things close most of that gap for free:

**1. Run the gate before you push.** It is the same script CI runs, so there are no surprises:

```bash
bash .github/scripts/quality-gate.sh origin/dev
```

**2. Make it automatic with a pre-push hook.** This genuinely enforces — the push does not happen:

```bash
# .husky/pre-push
bash .github/scripts/quality-gate.sh origin/dev
```

Local hooks can be skipped with `--no-verify`, so this is discipline rather than a wall. But it
catches the ordinary case, which is someone forgetting, not someone deliberately bypassing.

**3. `CODEOWNERS` still requests reviewers.** The shipped file says as much in its own comment:
without branch protection it is a prompt, not a gate. A prompt is still worth having.

If the repository can be public, making it public is the cheapest way to get real enforcement —
branch protection, secret scanning, and push protection all become free at once.

### Checklist

```
□ Branches dev and prod created and pushed          ← nothing runs until this
□ Default branch set to dev
□ Secrets: NEXT_PUBLIC_API_URL, NEXT_PUBLIC_APP_URL
□ Secret:  DOKPLOY_WEBHOOK_URL          (or delete the deploy job)
□ Secret:  DEEPSEEK_CODE_REVIEW_TOKEN   (or delete deepseek-review.yml)
□ Secret:  APP_REPO_TOKEN               (or leave unset — the step self-skips)
□ Variable: CI_RUNNER                   (or leave unset — defaults to ubuntu-latest)
□ Workflow permissions → Read and write (required for ghcr.io)
□ Dependabot alerts enabled

Nice to have — free on public repos, paid on private:
□ Branch ruleset on dev and prod, Quality Gate required
□ CODEOWNERS updated from @your-github-handle (the file is free to add;
  auto-requesting reviewers from it needs a paid plan on a private repo)
```

### Verifying it without burning minutes

Open one throwaway pull request into `dev` with a whitespace change. That exercises
`quality-gate.yaml`, `deepseek-review.yml`, and `react-doctor.yml` in a single run, and costs one
gate execution rather than one per workflow.

Do not test the deploy path this way — merging to `prod` triggers a real deploy and the strip
pipeline. Test that only when the branch actually holds what you want deployed.

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

The `agents-` prefix is only a namespace, so project subagents sort together in the picker and never
collide with a built-in name. Rename it to anything you like — just rename the `name:` field in the
frontmatter and the row in `.claude/agents/INDEX.md` together, since the gate's index-coverage check
verifies both directions.

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
