# Setup

Ordered by dependency, not by importance. Each step can be checked before the next one starts, and
the step that can delete files comes last on purpose.

Budget about an hour. Steps 0–5 make the layer work on your machine, 6–8 wire the commands, the
skills and GitHub, and 9 is opt-in.

> **Read this first: the workflows arrive disarmed.**
>
> Every workflow in `.github/workflows/` starts only from a pull-request event: nothing runs on a
> push, a schedule or a clone, and nothing opens a pull request on its own (§8 says why). The gate,
> deploy, strip and review workflows also wait for pull requests into `dev` or `prod`, which this
> repo does not have, so they activate when you create those branches in your own repo. The three
> read-only checks (`workflows-lint`, `dependency-review`, `codeql`) run on any pull request; on a
> private repository the last two skip themselves until `CODE_SECURITY` is set (README § GitHub
> repository configuration). No secret is needed to clone this.

---

## 0. Tools you need

| Tool              | Needed for                                                                              | Without it                                                                      |
| :---------------- | :-------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------ |
| Claude Code       | The hooks, commands, subagents and skills in `.claude/`                                 | The layer is only documents                                                     |
| bash 3.2+ and git | Every hook and script (macOS's `/bin/bash` is enough)                                   | Nothing runs                                                                    |
| python3 3.8+      | The command analyzer, `db-guard.sh`, the unlock and `.env` helpers, `ai-config.sh`      | The guards refuse, or fall back to a few plain-text rules; `ai-config.sh` fails |
| jq                | Faster payload reads in the hooks                                                       | Optional: python3 reads them                                                    |
| Bun               | The package scripts, the TypeScript checks and both gate runners                        | The gates cannot run                                                            |
| Node.js 20+       | The `.mjs` checks (folder shape, coverage policy) and Next.js itself                    | Those gates fail                                                                |
| gitleaks          | The staged secret scan before each commit                                               | That pre-commit gate fails                                                      |
| uv                | Serena (`uvx`), the database servers, and the pinned SkillSpector that `skills.sh` runs | Those servers do not start; the skill scan fails and prints the install command |
| bubblewrap, socat | The Bash sandbox on Linux and WSL2 (macOS needs nothing)                                | Claude Code warns and runs commands unsandboxed; the hooks still apply          |
| gh, signed in     | `scripts/ops/pr-ready.sh`, which `/merge-pr` and `/promote` run                         | Those commands cannot read a pull request                                       |

No hook downloads anything. The pull-request gate installs what it runs: the lockfile's packages,
one pinned gitleaks build verified by checksum on a Linux runner, and the pinned SkillSpector
through uv when a skill, command, subagent or hook changed.

---

## 1. Copy the layer in

Copy the layer, not this repository's own documents (`README.md`, this file, `docs/RATIONALE.md`,
`docs/assets/`, `LICENSE`, `.markdownlint-cli2.jsonc`):

```bash
CFG=/path/to/fe-agent-config
cp -R "$CFG"/{.claude,.agent,.agents,_workflow-source,.github,.husky,scripts} .
cp "$CFG"/{CLAUDE.md,AGENTS.md,SSOT.md,.mcp.json,.skillspector-baseline.yaml} .
cp "$CFG"/{oxlint.json,.oxlintignore,.oxfmtrc.json,knip.ts,doctor.config.json} .
cp "$CFG"/{.gitleaks.toml,.dockerignore,.env.development.example,.env.production.example} .
mkdir -p docs && cp "$CFG"/docs/unlock.md docs/   # the hooks' refusals link to it
```

The tool configs overwrite yours of the same name: merge by hand where you already have one.
`PRODUCT.example.md` and `DESIGN.example.md` belong to the optional design skill (§7).

Then **merge `.gitignore`.** `.claude/settings.local.json`, `.claude/state/`, `.skillspector/`
and every real `.env*` file must be ignored before your first commit, not after; the `.env.example`
and `.env.<target>.example` templates stay committed. `.claude/state/` holds the unlock files and
the `.env` backups, and `scripts/env/set.sh` refuses to run until it is ignored. The file also
keeps the generated API client out of git: the gates rebuild it from `openapi.json`.

---

## 2. Fill in every placeholder

Placeholders are named, never blank, so one search finds them:

```bash
grep -rn --exclude-dir=hooks --exclude-dir=anti-patterns --exclude-dir=commands \
  --exclude-dir=skills --exclude=agent-config.example.json '<[a-zA-Z][a-zA-Z -]*>' \
  CLAUDE.md AGENTS.md SSOT.md .mcp.json .env.production.example .claude/ _workflow-source/
```

It skips the hooks, anti-patterns and skills, whose angle brackets are syntax and examples, and the
generated command mirror. It still prints command syntax (`<file>`, `<paths>`, `<sha>`), TypeScript
generics and HTML tags in the rules and checklists (`<html lang>`, `<dialog>`); leave those. Two
placeholders sit outside that search, in `.github/`: `@your-github-handle` in `CODEOWNERS`, and
`DOCS_REPO: <github-org>/<docs-repo>` in `ci-cd.yaml`, needed only for the docs changelog
([README § GitHub repository configuration](README.md#step-4-cross-repository-token-optional)).

| File                                                 | What to replace                                                                                                                                                                 |
| :--------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `CLAUDE.md`                                          | `<Project Name>`, and the Project Snapshot: stack, dev command and port                                                                                                         |
| `AGENTS.md`                                          | `<Project Name>`; `<backend-service>`, the one API this app calls; `<docs-repo>` in § L, the docs site that reads the `@documented` markers                                     |
| `SSOT.md` §1–§2                                      | Scaffolding (owner, date, the subsystem diagram): replace it wholesale                                                                                                          |
| `SSOT.md` §3–§7                                      | Stack table, layer map, API contract, env vars, infrastructure: edit in place                                                                                                   |
| `.claude/agents/*.md`                                | `<Project Name>` in each subagent's title and first line                                                                                                                        |
| `_workflow-source/promote*.md`                       | The deploy table (`<deploy platform>`, `<app-name>`, `<app-id>`, `<app-host>`) and the adapter's commands. Edit here, then run `bash scripts/sync/workflows.sh`                 |
| `_workflow-source/plan-fullstack.md`                 | `<backend-repo>`, `<frontend-repo>`, `<content-repo>` and `<backend-service>`: the repositories a full-stack plan reads. Delete the command if this app has no backend of yours |
| `_workflow-source/review.md`                         | `<backend-service>`, `<frontend-app>` (the app that owns sign-in, if not this one) and `<staging-url>`                                                                          |
| `.env.production.example`                            | `<api-host>` and `<app-host>`                                                                                                                                                   |
| `.claude/*.example.md`, `.claude/mcp/*.example.json` | Only the ones you keep (below, and [§3](#servers-you-load-on-demand))                                                                                                           |

Five on-demand references ship as `.claude/*.example.md`: `OPERATIONS`, `CI-RUNNERS`, `DATABASE`,
`ANALYTICS` and `SERENA-WORKSPACE`. Copy one to its name without `.example` and fill it in; its row
in `CLAUDE.md` § On-demand References already points at the filled name, and nothing imports it,
so it costs no context until a task reads it. Never `@`-import one: an import loads the whole file
into every session. **Delete the ones you do not need, with their rows.** An unfilled template is
worse than an absent one, because an agent will try to use it.

**Commit one `.env.<target>.example` per environment.** Two ship: `.env.development.example` and
`.env.production.example`, with every key the app reads and placeholder values only. Add a key to
both whenever the app starts reading one. They do three jobs:

- `bun run env:init` creates `.env.development` and `.env.production` from them, and `bun dev`
  refuses to start while a key the template gives a value is empty in the real file.
- `bash scripts/env/show.sh <file>` reports the keys a real file is missing compared with its
  template.
- `/promote` and `/promote-deploy` audit the live production configuration against
  `.env.production.example`, and cannot run that audit without it.

The templates stay readable and editable for every command; the real files do not (§4).

---

## 3. Agent tooling: MCP servers, wrappers, plugins

This decides how well the agent works in the first place. Nothing breaks if you skip it, but it is
worth ten minutes.

### Every tool by name

| Tool                               | What it is                                            | Ships here?                                                       | Covered in                                                          |
| :--------------------------------- | :---------------------------------------------------- | :---------------------------------------------------------------- | :------------------------------------------------------------------ |
| **Serena**                         | Semantic code search and edit over a language server  | `.mcp.json`                                                       | [below](#serena-install-it-or-delete-the-rules-that-assume-it)      |
| **Context7**                       | Live library documentation lookup                     | `.mcp.json`                                                       | server table below                                                  |
| **GitHub MCP**                     | Pull requests, issues and reviews inside a session    | `.mcp.json`                                                       | server table below                                                  |
| **Postgres MCP**                   | Schema, health and query plans (`db-dev`, `db-prod`)  | `.mcp.json`                                                       | server table below · `DATABASE.example.md`                          |
| **Cloudflare**                     | DNS, Workers and account resources                    | `.claude/mcp/cloudflare.example.json`, loaded on demand           | [below](#servers-you-load-on-demand)                                |
| **Deploy platform · VPS provider** | Deployment and VPS control                            | `.claude/mcp/*.example.json`, loaded on demand                    | [below](#servers-you-load-on-demand)                                |
| **Command wrapper**                | Output filter, sandbox or audit recorder              | **No**, machine-local                                             | [Command wrappers](#command-wrappers)                               |
| **Plugins**                        | Session add-ons                                       | **No**, machine-local                                             | [Plugins](#plugins)                                                 |
| **DeepSeek Code Review**           | AI review comment on pull requests                    | `.github/workflows/`                                              | [below](#ai-code-review-on-pull-requests-deepseek) · README § CI/CD |
| **react-doctor**                   | React health checks; advisory only                    | Workflow + skill (`.claude/skills/react-doctor/`)                 | [§7](#7-skills-two-ship-one-is-installed-by-reference)              |
| **impeccable**                     | Interface design and polish skill                     | **No**: installed by reference; `PRODUCT`/`DESIGN` templates ship | [§7](#7-skills-two-ship-one-is-installed-by-reference)              |

### The servers in `.mcp.json`

Five ship, each pinned to an exact version. **Most projects should delete some of them.** Every
connected server spends context on its tool definitions before you ask anything, so an unused
server is a permanent tax.

| Server               | What it gives the agent                                                                         | Needs                                                             | Keep it if                                        |
| :------------------- | :---------------------------------------------------------------------------------------------- | :---------------------------------------------------------------- | :------------------------------------------------ |
| `serena`             | Find a symbol, its references and implementations; rename it safely                             | `uvx` ([Astral uv](https://github.com/astral-sh/uv)). No token    | **Almost always.** See below                      |
| `context7`           | Current library documentation, fetched live                                                     | `npx`. No token                                                   | You use libraries that moved recently             |
| `github`             | Pull requests, issues, reviews and branches from inside a session (hosted server)               | `GITHUB_PERSONAL_ACCESS_TOKEN`                                    | You want the agent to open and read pull requests |
| `db-dev` · `db-prod` | Schema, health, index advice and query plans. Both start read-only (`--access-mode=restricted`) | `DB_DEV_URI` / `DB_PROD_URI`, plus a tunnel if the port is closed | The agent should debug against a real schema      |

Deleting a server is removing its object from `.mcp.json`. The `.claude/settings.json` entries that
name `db-prod` or `github` then match nothing, which is harmless. `bash scripts/check/ai-config.sh`
fails on any `npx`, `bunx` or `uvx` server that is not pinned to a version: an unpinned package runs
whatever was published last, the moment a session starts.

**Permissions for MCP tools live in `.claude/settings.json`, never in `.mcp.json`.** Claude Code
reads no permission field there, so an `alwaysAllow` list in `.mcp.json` does nothing. To stop
answering a prompt for Serena's read tools, add them to `permissions.allow`, for example
`"mcp__serena__find_symbol"`, and think before adding its editing tools. Never allow
`mcp__db-prod__execute_sql`: it is an `ask` rule on purpose.

**`--access-mode=restricted` is what keeps production read-only.** The server runs every query in a
read-only transaction, and because `bypassPermissions` mode skips `ask` rules and a text check can
misread SQL, that server mode is the layer that holds. To let the agent write to dev, switch
`db-dev` alone to `--access-mode=unrestricted` and give the dev role write grants. If you give
`db-prod` write access for incidents, `db-guard.sh` holds every write until you unlock `db` (§4).

### Servers you load on demand

A server you reach for once a month should not cost context in every session. Three examples ship
in `.claude/mcp/`, outside `.mcp.json`: `deploy-platform.example.json` (deployments, logs),
`vps-provider.example.json` (VPS, domains, DNS) and `cloudflare.example.json` (DNS, Workers and
account resources; a hosted server that reads `CLOUDFLARE_API_TOKEN` from your shell). To use one:

1. Copy it to `.claude/mcp/<name>.json` and fill in your provider's MCP package, pinned to the exact
   version you checked, and its host. Rename the env keys to the ones that package reads, and keep
   the `${VARIABLE}` values that point at your shell. `ai-config.sh` checks the pin of the copy;
   the `.example.json` placeholder fails that check until you replace it. The Cloudflare example
   is a hosted server with no package to pin: copy it as it is.
2. Load it for one session: `claude --mcp-config .claude/mcp/<name>.json`.

If your deployment platform's server can redact environment values in its output, turn that on: a
tool result lands in the transcript. `/promote` and `/promote-deploy` name the deploy tools as
placeholders in their "This repo's deploy target" section (§2). Delete the files you will never
use.

### Serena: install it, or delete the rules that assume it

`CLAUDE.md` § Agent Tooling tells the agent to use Serena for `.ts`/`.tsx` files, and `AGENTS.md`
Rule 0 repeats it. If Serena is not installed, those lines send the agent to tools that are not
there: it has a documented fallback (retry, log the failure, use the built-in tools), so it degrades
rather than deadlocks, but it spends a call finding that out on every task. So pick one,
deliberately:

- **Install [uv](https://docs.astral.sh/uv/getting-started/installation/)**, which provides `uvx`.
  The `.mcp.json` entry fetches the pinned server on first run.
- **Or delete** the Serena bullets from `CLAUDE.md` § Agent Tooling, the Serena lines in
  `AGENTS.md` Rule 0 and 0b, and the `serena` entry from `.mcp.json`, together. Deleting one
  without the others is the failure case.

Two details in the shipped entry:

- **`ENABLE_TOOL_SEARCH: "true"`** defers Serena's tool definitions until they are needed, which
  cuts the per-session cost. Its own instructions are deferred too, so the session calls
  `initial_instructions` once before its first symbol search, which `CLAUDE.md` § Agent Tooling
  already requires.
- **The pin** (`serena@v1.7.0`) keeps a new release from changing your tools mid-project. Upgrade
  deliberately: change the pin, restart the session, and confirm the handshake with
  `claude mcp list`. Serena's editing tools pass through the same write hooks as `Edit`.

`.claude/SERENA-WORKSPACE.example.md` covers one Serena project spanning several repositories, so
symbol search reaches all of them. It is useful on a multi-repo product and pure overhead on a
single repo: a shared workspace is machine-local and a fresh clone does not inherit it, and paths
then resolve against the workspace root rather than your repo. Delete it if you do not need it.

### Command wrappers

If you route shell commands through a wrapper (an output filter, a sandbox, an audit
recorder), declare it in `CLAUDE.md` § Command Wrapper **as a hard rule**, prefix every command in
that file with it, and list it under `commandWrappers` in `.claude/agent-config.json` (the example
file shows the format). `safety-check.sh` peels a listed wrapper before judging the command; an
unlisted one hides the command it runs, so `<wrapper> git push origin main` would be judged as
`<wrapper>`.

None ships here: a wrapper is machine-local, and a rule pointing at a missing binary fails every
command. It has to be a hard rule rather than a note, because a wrapper mentioned in passing gets
dropped once a task gets busy, and half-wrapped commands make its numbers meaningless.

### Plugins

`.claude/settings.json` enables **no plugins**, deliberately: a plugin declared there but not
installed is a startup error for everyone who clones the repo. If the whole team should get one,
add it to that file:

```jsonc
{
  "enabledPlugins": { "<plugin>@<source>": true },
  "env": { "<PLUGIN_SETTING>": "<value>" }
}
```

If the choice is yours alone, put it in `.claude/settings.local.json`, which `.gitignore` already
excludes.

### AI code review on pull requests: DeepSeek

`.github/workflows/deepseek-review.yml` posts an AI review comment on pull requests into `dev`,
using [`hustcer/deepseek-review`](https://github.com/hustcer/deepseek-review), which accepts any
OpenAI-compatible endpoint, so the provider is your choice despite the name. Add a
`DEEPSEEK_CODE_REVIEW_TOKEN` secret and it runs. Its `sys-prompt` describes this stack and lists the
rules the gate cannot check; edit it when yours differs. Three things to keep if you edit the
workflow:

- **Never add `actions/checkout`, and never switch to `pull_request_target`.** The workflow runs on
  `pull_request` (a branch of this repo gets the secret; a fork's run is skipped) and on
  `issue_comment` for `/ask-deepseek`, which runs from the default branch with the secret in scope.
  That path is safe only because nothing checks out or runs the pull request's code.
- **`dev` only, and no `synchronize`.** A `dev → prod` diff re-adds the whole AI layer the strip
  removed and exceeds the provider's diff limit. Without `synchronize`, a push does not stack
  another review; comment `/ask-deepseek` to re-run it.
- **Tell it only what the gate checks on the same pull request.** The prompt says which checks
  already ran, so the review spends its budget on judgement; keep that list true.

---

## 4. Wire the hooks and the unlock

`.claude/settings.json` already wires all eight hooks, together with the permission rules. Keep the
executable bits, then prove the hooks on your own machine:

```bash
chmod +x .claude/hooks/*.sh scripts/ops/unlock.sh scripts/env/*.sh scripts/check/hook-probes.sh
bash scripts/check/hook-probes.sh   # every rule, both ways, in temp folders; about nine minutes
```

Run the `chmod` line yourself (in your terminal, or with `!`): once the hooks are wired they refuse
it from Claude, because it changes a guard script.

On macOS, `/bin/bash scripts/check/hook-probes.sh` proves the hooks under bash 3.2.

### The hook contract

What every hook here relies on, and what to keep if you write your own:

- **Input is JSON on stdin.** Claude Code sets no `CLAUDE_TOOL_INPUT_*` variable, so a hook that
  reads one reads nothing.
- **Only exit 2 blocks, and only in `PreToolUse`.** The tool call is cancelled and stderr is the
  reason Claude reads. Any other exit code, `1` included, and a crash or a timeout, lets the call
  through. So every guard exits 2, and refuses when it cannot read its input. A malformed
  `.claude/agent-config.json` is not a refusal: the defaults apply and Claude is warned.
- **`PostToolUse` runs after the write landed.** It cannot undo anything; it reaches Claude only
  through `hookSpecificOutput.additionalContext`. Hooks on one event run in parallel, so format and
  lint share one script (`post-edit.sh`) and cannot race on the same file.
- **`SessionStart` and `UserPromptSubmit` hooks end in `|| true`**: an exit 2 on a prompt erases
  what the user typed.
- **Paths are anchored.** Each hook runs as `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<name>.sh"`
  with a timeout (10 s for the guards and session hooks, 20 s for `post-commit.sh`, 60 s for
  `post-edit.sh`), because a hook starts in the session's current folder, not the repo root.
- **No network.** No hook opens a connection or installs anything.
- **No hook reads permission from the prompt.** A refused command stays refused whoever asks; the
  user runs it with `!`.

**Test a guard by triggering it, never by reading it.** A guard whose path pattern does not match
your layout never fires and never complains, and reading the script cannot tell you that.
`hook-probes.sh` feeds every rule a call it must stop and one it must let through. After changing a
hook or `.claude/agent-config.json`, run it again, then ask the agent to edit a file the guard
should protect, such as one under `src/lib/api/generated/`.
[`.claude/hooks/README.md`](.claude/hooks/README.md) lists what each hook refuses, what it does when
python3 or jq is missing, and how to turn one off: remove its entry from `.claude/settings.json`.

### Per-repo settings

`.claude/agent-config.json` holds this repository's hook settings; `.claude/agent-config.example.json`
lists every key with its default (protected branches and paths, generated paths, command wrappers,
the production SQL tool). A key you leave out keeps its default. The shipped file sets one key,
`localePairs`, so `post-edit.sh` reminds the agent to update `id.json` whenever `en.json` changes
alone; list your own locales there, or remove the key in a single-locale app.

`generatedPaths` defaults to `src/lib/api/generated`, `src/generated` and the OpenAPI spec. If your
generator writes elsewhere, set the key, then trigger the guard to prove it matches.

### The unlock: `.env` files and production writes

The hooks refuse the agent's shell reads and writes of `.env*` files, and hold its SQL writes to
production. Only you open either one, for a few minutes, with a command the hooks refuse to run for
the agent. They read each command as text and refuse any command they cannot resolve, and the Bash
sandbox below adds a boundary the operating system enforces: [`docs/unlock.md`](docs/unlock.md)
explains the mechanism and what it still does not stop. Two lines of setup:

1. `.claude/state/` in `.gitignore` (§1). It holds the unlock files, the `.env` backups and the
   audit log; `scripts/env/set.sh` refuses to run until it is ignored.
2. The `unlock` alias in your `package.json` (§5), so the command is `bun unlock`.

Then run it yourself, with `!` in front inside Claude Code:

| Package manager | Open `.env*` (20 min)           | Open DB writes (15 min)        | Status · lock everything                                             |
| :-------------- | :------------------------------ | :----------------------------- | :------------------------------------------------------------------- |
| bun             | `! bun unlock env`              | `! bun unlock db`              | `! bun unlock status` · `! bun unlock off`                           |
| npm             | `! npm run unlock env`          | `! npm run unlock db`          | `! npm run unlock status` · `! npm run unlock off`                   |
| pnpm            | `! pnpm unlock env`             | `! pnpm unlock db`             | `! pnpm unlock status` · `! pnpm unlock off`                         |
| yarn            | `! yarn unlock env`             | `! yarn unlock db`             | `! yarn unlock status` · `! yarn unlock off`                         |
| no package.json | `! ./scripts/ops/unlock.sh env` | `! ./scripts/ops/unlock.sh db` | `! ./scripts/ops/unlock.sh status` · `! ./scripts/ops/unlock.sh off` |

While `env` is locked the agent lists a file with `bash scripts/env/show.sh <file>`, which masks the
secrets; while it is open, it changes a value with `scripts/env/set.sh`, which backs the file up
first.

### When a command is refused

`safety-check.sh` peels wrappers (`env`, `sudo`, `timeout`, `xargs` and the rest the hooks README
lists, plus your `commandWrappers`) and package runners (`npx`, `bunx`, `pnpx`, and `npm`, `pnpm`,
`yarn` and `bun` `exec`, `dlx` and `x`) and judges the command inside; a runner's shell text (a
`-c`, `--call` or `--shell-mode` string, or the words of `bun exec` and `yarn exec`) is judged as a
script. It refuses by category: git that loses work or skips the pre-commit gate, pushes to or
deletion of a protected branch, git settings that change what git runs, loads or connects to
(aliases, includes, command-carrying keys such as `core.sshCommand`, proxies, `url.*.insteadOf`,
`safe.directory`, and more) whatever their value, any shell access to a real `.env*` file, the
unlock from the agent, and any shell change to the guards themselves (the hooks, the probes,
`unlock.sh`, `scripts/env/` and the settings that turn the guards on). README § What gets blocked
has each list.

It fails closed. A payload that is not JSON, an analyzer crash or an analysis past 8 s is refused,
and so is a command it cannot resolve, whether or not it names a `.env*` file or the unlock: `eval`
of built text, a decoded payload, a script piped into a shell or interpreter, a command substitution
used as a command name or a file operand, a path built through `IFS`, an array or `printf`, a
package runner whose command or shell text is built from `$( )` or an unknown variable, a pager or
editor command it cannot read, inline code that opens or changes a file or runs a command, a `sed`
or `awk` program whose file or command is built at run time, paths handed to a command that changes
files by `xargs` or `$( )`, and a copy or archive that lands on `.claude/state/` or a `.env*` file.
The refusal says why, and ends with the way through: if you meant the command, run it yourself with
`!` in front, which runs it as you, with your own access, outside the hooks and (in an ordinary
session) outside the sandbox. Never widen `.claude/settings.json` or `.claude/agent-config.json` to
get past one.

Without python3, only plain-text rules stand in: pushes to protected branches, recursive deletes of
protected paths, a hard reset, a forced `clean`, `--no-verify`, `HUSKY=0`, any real `.env*` name,
the unlock script, its alias or its folder, any mention of `scripts/env/`, of a file that turns the
guards on, or of a guard script (`.claude/hooks/`, `hook-probes`). Everything else runs unchecked on
such a machine, so install python3 (§0).

What the hooks do not catch, since they read the command line and not the files it runs: a script,
test, build config or git hook the agent writes and then runs; a program that runs commands of its
own and is not a known wrapper (`watch`, `script`, `flock`, `parallel`), judged by name only; the
app reading `.env*` when it runs; and an edit to the hooks through the Edit tool, which
`.claude/settings.json` asks you about first (the shell cannot change them). The sandbox below
covers the two that matter most, reading `.env*` and forging an unlock, and keeps sandboxed
commands out of the hooks and the unlock script as well.

### The Bash sandbox

`.claude/settings.json` turns on [Claude Code's sandbox](https://code.claude.com/docs/en/sandboxing)
for Bash by default (`"sandbox": {"enabled": true}`). The operating system then enforces, for every
sandboxed command and its children, what the hooks can only read as text: `denyRead` keeps them off
every `.env*` file (`.envrc`, `.env-*` and `.env_*` included, at any depth) and the backups in
`.claude/state/env-backups/`, with `allowRead` reopening the `*.example` templates; `denyWrite`
keeps them out of `.claude/state/unlock/`, `.claude/hooks/` and `scripts/ops/unlock.sh`; and
`excludedCommands` leaves only `scripts/env/show.sh` and `scripts/env/set.sh` outside, the two
helpers that must reach `.env*` files.

- **Platforms.** macOS needs nothing; Linux and WSL2 need `bubblewrap` and `socat` (§0). WSL1 and
  native Windows are not supported. Where the sandbox cannot start, Claude Code warns and runs
  commands unsandboxed unless `sandbox.failIfUnavailable` is `true`, and the hooks still apply. Run
  `/sandbox` in a session to see its state and anything missing.
- **The app reads `.env`.** `bun dev`, `bun run build` and `bun run env:check` read `.env.<target>`
  through `scripts/next/env.ts` and Next.js, so under the sandbox they fail on the first read.
  Claude Code then offers to rerun the command outside the sandbox, through its normal permission
  flow, which asks you first in the default mode. The hooks still check the rerun. Set
  `sandbox.allowUnsandboxedCommands` to `false` to forbid every such retry.
- **Other tools the sandbox breaks** (`docker`, sometimes `gh` on macOS) fail the same way. If the
  retries get tedious, list them under `sandbox.excludedCommands` in your own
  `.claude/settings.local.json`, where the entries add to the shared list.
- **Your `!` commands** run outside the sandbox, except in a background session with
  `allowUnsandboxedCommands: false` and on Linux with `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` set. There
  the sandbox also refuses your own write to `.claude/state/unlock/`: run `unlock` in your own
  terminal instead.
- **Off.** Set `"sandbox": {"enabled": false}` in `.claude/settings.json` (or in your own
  `.claude/settings.local.json`). The hooks keep working.

---

## 5. Make the gates runnable

Two runners share one list of checks. `bash scripts/check/gates.sh` runs
`scripts/check/gates.list` on your machine, and `.husky/pre-commit` runs it on every commit with
`--hook`, choosing the gates by what is staged. `.github/scripts/quality-gate.sh` runs the same
checks and more, the build included, on every pull request. Both call package scripts by these
names, so add them to your `package.json`:

```jsonc
{
  "scripts": {
    "dev": "bun run scripts/next/env.ts check development && next dev",
    "dev:prod": "bun run scripts/next/env.ts check production && bun --env-file=.env.production run next dev",
    "build": "bun run scripts/next/env.ts check production --soft && next build",
    "start": "bun run scripts/next/env.ts check production --soft && next start",
    "env:init": "bun run scripts/next/env.ts init",
    "env:check": "bun run scripts/next/env.ts check development",
    "format": "oxfmt src scripts .github/scripts",
    "format:check": "oxfmt --check src scripts .github/scripts",
    "lint": "oxlint -c oxlint.json --ignore-path=.oxlintignore",
    "fl": "bun run format && bun run lint",
    "fl:ci": "bun run format:check && oxlint -c oxlint.json --ignore-path=.oxlintignore",
    "type-check": "tsc --noEmit",
    "test": "vitest run",
    "test:coverage": "vitest run --coverage",
    "generate:api": "orval",
    "sync:rules": "bash scripts/sync/rules.sh",
    "sync:workflows": "bash scripts/sync/workflows.sh",
    "check:dead-code": "knip",
    "check:i18n": "bun run scripts/check/i18n.ts && bun run scripts/check/i18n-casing.ts",
    "check:hooks": "bun run scripts/check/hooks.ts",
    "check:reexport": "bun run scripts/check/no-reexport.ts",
    "check:soc": "bun run scripts/check/soc.ts",
    "check:tailwind": "bun run scripts/check/tailwind-classes.ts",
    "check:error-codes": "bun run scripts/check/error-codes.ts",
    "check:error-catch": "bun run scripts/check/error-catch.ts",
    "check:dialog-desc": "bun run scripts/check/dialog-desc.ts",
    "check:responsive": "bun run scripts/check/responsive.ts",
    "check:skeleton-switch": "bash scripts/check/skeleton-switch.sh",
    "measure:waterfall": "bun run scripts/measure/waterfall.ts",
    "ops:pr-ready": "bash scripts/ops/pr-ready.sh",
    "unlock": "bash scripts/ops/unlock.sh",
    "prepare": "husky"
  }
}
```

Then install the tools behind them, pinned to the exact versions you get:
`bun add -d husky knip oxfmt oxlint vitest @vitest/coverage-v8 jsdom typescript orval`, plus
`playwright-core` if you keep `measure:waterfall`. `prepare` installs the pre-commit hook on
`bun install`. §0 lists the tools outside `package.json`.

Keep the names: `gates.list`, the quality gate, `coverage-policy.mjs` (which checks that the
pre-commit hook still reaches `test:coverage`) and `@format` (which reads the scope of `format` and
`fl:ci`) all call these scripts by name. `gates.sh` reads the package manager from the lockfile.
`bun run test` runs Vitest; a bare `bun test` is Bun's own runner and fails for the wrong reasons.

**Keep `scripts/env/` to its three helpers.** The safety hook trusts `show.sh`, `set.sh` and
`envfile.py` with `.env*` files, so the agent's shell may read them but never change, replace, move
or delete them, and `.claude/settings.json` asks you before any edit under `scripts/env/`. Running
another script from that folder is allowed, but every file there also counts as a hooks file, so
staging one runs the nine-minute hook probes. That is why the environment preflight the `dev`,
`build` and `start` scripts run lives in `scripts/next/`.

**Three optional modules** ship with a check each: `check:dialog-desc`, `check:responsive` and
`check:skeleton-switch`. Adopt one with its rule, or delete the rule, its standard under
`.claude/docs/standards/`, its script and its `gates.list` line together (the skeleton module also
takes the `skeleton` skill). The pull-request gate runs a module exactly when `gates.list` lists
it. `measure:waterfall` is the optional measurer that `.claude/rules/web/data-fetching.md` W7
names; delete it with its package script if you measure in the browser instead.

**`vitest.config.ts`.** `coverage-policy.mjs` refuses to pass until the coverage block asks for
100% on the logic layer and every exclusion carries its reason:

```ts
coverage: {
  provider: 'v8',
  /* Directory patterns: a file no test imports lands in the report at 0% instead of vanishing. */
  include: ['src/hooks/**', 'src/lib/**', 'src/store/**', 'src/i18n/**', 'src/proxy.ts'],
  thresholds: { statements: 100, branches: 100, functions: 100, lines: 100 },
  exclude: [
    '**/index.ts',
    'src/lib/api/generated/**',
    /* Static seed data: object literals with no branch to test. List each file by path. */
  ],
},
```

**`tsconfig.json`.** The checks under `scripts/` run on Bun and use its globals; add `"scripts"` to
`exclude`, or install `@types/bun`, so `tsc --noEmit` type-checks the app rather than the tooling.

**`next.config.ts`, only if you want dev-only pages.** `/rca`'s lowest rung and the UI rules use a
throwaway `page.dev.tsx` that only `next dev` serves. Next serves it once the development server
lists `dev.tsx` as a page extension:

```ts
import type { NextConfig } from 'next';
import { PHASE_DEVELOPMENT_SERVER } from 'next/constants';

const nextConfig: NextConfig = {
  /* your existing settings */
};

const EXTENSIONS = ['tsx', 'ts', 'jsx', 'js'];

export default function config(phase: string): NextConfig {
  const pageExtensions =
    phase === PHASE_DEVELOPMENT_SERVER ? ['dev.tsx', ...EXTENSIONS] : EXTENSIONS;
  return { ...nextConfig, pageExtensions };
}
```

`knip.ts` already lists `src/app/**/page.dev.tsx` as an entry, so such a page is not reported as
unused. A production build never serves one.

Run both before you ever open a pull request:

```bash
bash scripts/check/gates.sh                        # the pre-commit list, every gate
bash .github/scripts/quality-gate.sh origin/dev    # the pull-request gate, build included
```

A gate that is red for reasons everyone knows about is a gate nobody reads: delete an optional
module's line rather than let it fail.

### On dependency audits

`scripts/check/audit.ts` wraps `bun audit` and fails only on high and critical advisories that
match an installed version. When it fires, **check where the advisories come from before reaching
for an ignore flag.** They often all arrive through one parent dependency; force the transitive
package to a patched release with `overrides`, and record which advisory each override answers
(`SSOT.md` §3). A flag left behind after the problem is fixed hides the next report for a
different vulnerability.

> `ci-cd.yaml` expects a deploy platform that builds from git source and exposes a deploy webhook
> (`DEPLOY_WEBHOOK_URL`). Neither ships here; that part is yours. If you deploy differently,
> replace the workflow rather than editing around it.

---

## 6. Slash commands and their mirrors

Optional, but the commands assume the GitHub settings in §8, squash merging off above all.

```bash
bash scripts/sync/workflows.sh           # write the mirrors
bash scripts/sync/workflows.sh --check   # verify without writing; this is the gate's mode
```

Edit commands in `_workflow-source/`, never in the mirrors. `--check` is the mode that catches
drift: a write-mode run **overwrites staleness before it can observe it**. Wire `--check` into your
gate; wire the write mode into nothing.

- `/merge-pr` and `/promote` read a pull request's readiness with `scripts/ops/pr-ready.sh`, which
  needs a signed-in `gh`. Only a passing check counts: a skipped or neutral one is named and
  blocks, and the command asks you before it passes `--allow-skipped` for checks that skip by
  design, such as dependency review and CodeQL on a private repository without `CODE_SECURITY`.
- `/promote` and `/promote-deploy` need their "This repo's deploy target" section filled once
  (§2). They hand every push to `dev` or `prod` to you as a `!` command, because the safety hook
  refuses those pushes from the agent.

`.agent/workflows/` exists for a second tool that reads commands from that path, and
`.agents/rules/` is the rule mirror for Antigravity. If no such tool is in use, each is a folder
kept in sync for a reader who does not exist, and you may delete it, but not on its own: both
`--check` modes fail when their mirror is missing.

- **`.agent/workflows/`**: also remove it from `TARGETS_ALL` in `scripts/sync/workflows.sh`.
- **`.agents/rules/`**: also delete `scripts/sync/rules.sh`, its line in `gates.list`, its
  "Rules Mirror Check" step in `.github/scripts/quality-gate.sh` and the `sync:rules` script.

Decide knowingly rather than inheriting either one.

---

## 7. Skills: two ship, one is installed by reference

| Skill                                                 | What it is                                                                                                       | How it arrives                                                                                                                                                                                                                                                                                                      |
| :---------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `react-doctor`                                        | Framework health checks: security, performance, accessibility, architecture. `/react-doctor` runs a local triage | **Ships** in `.claude/skills/react-doctor/`, adapted from the vendor's own skill under its Modified MIT License (the `LICENSE` beside it names two uses that need the vendor's written permission). Pinned to `react-doctor@0.9.14`; `doctor.config.json` turns its dead-code pass off, because Knip owns dead code |
| `skeleton`                                            | Order of work for a loading skeleton, measured at four widths                                                    | **Ships** in `.claude/skills/skeleton/` as part of the optional skeleton module; delete it with `.claude/rules/web/skeletons.md`                                                                                                                                                                                    |
| [`impeccable`](https://github.com/pbakaus/impeccable) | Interface design and polish: shape, critique, audit, polish                                                      | **By reference.** Nothing of it is committed here; install it as below                                                                                                                                                                                                                                              |

React Doctor is **advisory: it never fails a build, so do not make it a required status check.**
Its workflow runs on pull requests only. By default a React Doctor run sends its diagnostics and
repository metadata to the vendor's score API, with crash reports and telemetry, and a full scan
(or one whose diff touches `package.json`) also looks up every dependency at Socket.dev. The skill
passes `--no-score` and `--no-supply-chain` on every run, so a scan from a session stays on the
machine. When you raise the pin, raise it in the skill, its `references/` and
`.github/workflows/react-doctor.yml` together.

### Installing impeccable

```bash
DO_NOT_TRACK=1 npx skills@1.7.0 add pbakaus/impeccable --skill impeccable --agent claude-code
```

That copies the skill into `.claude/skills/impeccable/`, where Claude Code reads it, and writes
`skills-lock.json` with its source and a hash of the tree (`npx skills@1.7.0 update` refreshes
both). `DO_NOT_TRACK=1` (or `DISABLE_TELEMETRY=1`) stops the installer's usage reporting. The
vendor's own installer, `npx impeccable install`, installs the same skill and also offers a design
hook in `.claude/settings.local.json`; that hook runs on every UI edit, outside this template's
guards, so read it before accepting (`--no-hooks` skips it). Either way:

- **No binary is committed.** The skill's engine is downloaded once per machine, outside the repo,
  and `.gitignore` keeps a `scripts/bin/` folder inside any skill out of git in case an installer
  puts one there.
- **Commit the tree and `skills-lock.json` together**, then accept the tree by its hash under
  `vendored:` in `.skillspector-baseline.yaml` after reading what `bash scripts/check/skills.sh`
  reports (`.claude/OPERATIONS.md` § Skill scanning). An upgrade changes the hash and fails the
  gate until its findings are read again.
- **Give it its two inputs.** `PRODUCT.md` is yours: `.claude/settings.json` denies
  `Edit(PRODUCT.md)`, which covers every tool that writes files, so an agent cannot write it. Copy
  `PRODUCT.example.md` to `PRODUCT.md` and fill it in, or let `/impeccable init` interview you and
  save its draft yourself. `DESIGN.md` has no such rule: copy `DESIGN.example.md`, or let
  `/impeccable document` write it from the code.
- **Its working files stay out of git.** `.gitignore` already carries the vendor's block from its
  README ("Keeping `.impeccable` out of git"), between `# impeccable-ignore-start` and
  `# impeccable-ignore-end`: most of `.impeccable/` is per-developer state, and the shared files the
  README names (`config.json`, `live/config.json`, `design.json`, `surfaces/`, `critique/`) stay
  tracked. Refresh the block from the README when you upgrade the skill.

Not using it? Delete `PRODUCT.example.md` and `DESIGN.example.md`. The prod strip
(`.github/scripts/strip-paths.sh`) removes `PRODUCT.md`, `DESIGN.md`, both templates,
`skills-lock.json` and `.impeccable/` either way.

**Before you add a drift checker of your own:** an installer writes into `.claude/skills/` and
`.agents/skills/`, and some also drop a command into `.claude/commands/`. None of it has a
counterpart in `_workflow-source/`. `scripts/sync/workflows.sh` mirrors commands only, so a skill
tree is never its concern, and a command an installer owns goes in the script's `VENDORED` list
rather than being flagged as an orphan
([RATIONALE §4](docs/RATIONALE.md#4-third-party-installers-leave-legitimate-orphans)).

---

## 8. GitHub: pull-request-only CI

README § GitHub repository configuration walks through the branches, secrets and variables. Three
settings belong here because the commands and the CI depend on them.

### Turn off squash merging

In **Settings → General → Pull Requests**, allow merge commits and turn squash merging off.
`/merge-pr` and `/promote` merge with `--merge`, and `/branch-cleanup` deletes a branch only when
GitHub reports it zero commits ahead of `dev`, which only a merge commit makes possible: a
squash-merged branch always reads as ahead, so it is kept, never deleted on a guess.

### Create `dev` and `prod`, and make `dev` the default

Nothing in `.github/workflows/` that gates, deploys or strips runs until pull requests into those
branches exist. Pull requests target `dev`; `prod` is a promotion target.

### Why only pull-request events, and no schedulers

Every workflow here starts from a pull-request event: `pull_request`, a merged pull request
(`types: [closed]` with a `merged` guard) for the deploy and the strip, and `issue_comment` for an
on-demand review. There is no `push:` trigger and no `schedule:`, and nothing opens a pull request
on its own: dependency updates are pull requests a person opens.

- **A push adds nothing a pull request did not already check.** `dev` and `prod` change only
  through merged pull requests, whose gate ran on the merge result; a `push:` trigger would run the
  same checks again on the same code, on every runner minute you pay for.
- **A timer runs on code nobody changed.** A scheduled scan spends minutes every week and opens
  pull requests nobody asked for, and in a template it would do so in every copy. Updates are a
  decision instead: `pinact run -u --min-age 7` for the pinned actions (it skips releases younger
  than seven days) and `bun update` for packages, each in an ordinary pull request that dependency
  review and the gate then read.
- **The gate's toolchain is pinned too.** `quality-gate.yaml` installs exact releases of Bun
  (`bun-version`) and uv (`version`), so a new release cannot change `bun install --frozen-lockfile`,
  `bun audit` or the tests with nothing in the repository changing. Raise both by hand in one pull
  request: Bun to the release you run locally, the one that writes your `bun.lock`, and uv to a
  release at least seven days old.
- **A deploy follows a merge, not a push.** A pull request closed without merging, and a direct
  push to `prod`, deploy nothing.
- **The cost is stated, not hidden.** An advisory published after a merge surfaces at the next pull
  request that touches dependencies, or when you run `bun run scripts/check/audit.ts` yourself;
  nothing watches the repository between changes.

If you add a workflow, keep to the same rules; `workflows-lint.yml` runs actionlint, zizmor and
`pinact --check` on any pull request that changes `.github/`.

---

## 9. The AI-config strip pipeline: last, and only if you want it

**This is the only part that deletes files. Everything else should be working before you touch
it.** The idea: your production branch carries no agent configuration at all. Rules, hooks,
subagents and MCP config exist on `dev` and are removed on the way to `prod`.

| Script               | Role                                                                            |
| :------------------- | :------------------------------------------------------------------------------ |
| `strip-paths.sh`     | **The single source of truth** for what gets removed. The other three source it |
| `strip-ai.sh`        | Removes those paths on the production branch                                    |
| `verify-strip.sh`    | Asserts they are gone from `prod` **and still present on `dev`**                |
| `back-merge-prod.sh` | Merges `prod` back into `dev` so the branches do not diverge                    |

The list removes what configures an agent: `.claude/`, `.agent/`, `.agents/`, `_workflow-source/`,
`CLAUDE.md`, `AGENTS.md`, `SSOT.md`, `.mcp.json`, `.skillspector-baseline.yaml` and the other agent
files it names. Everything under `scripts/` and `docs/` stays, and that is a decision, not an
oversight. The build runs `scripts/next/env.ts`; `gates.list`, `quality-gate.sh` and the `unlock`
alias in `package.json` name the rest; README and this file link to `docs/unlock.md`. With
`.claude/` gone, the hook probes, the AI-config check and both mirror checks print that their
subject is not on this branch and exit 0, `scripts/env/` holds no secret, and an unlock opens
nothing because no hook is left to read it.

Three things that are not obvious, each of which has already cost someone a debugging session:

- **One list, sourced, never copied.** When `STRIP_PATHS` was duplicated across scripts, updating
  one and not the others made the strip half-land: production kept part of the config and nothing
  reported an error.
- **Verify both directions.** Checking only that `prod` lost the files misses the failure where
  `dev` lost them too.
- **Merge, never rebase, on the way back.** Rebasing rewrites the strip commit and the branches
  diverge permanently.

Adopt it in this order:

1. Run `strip-ai.sh` on a throwaway branch and inspect what disappeared.
2. Run `verify-strip.sh` and confirm it fails when you deliberately skip a path.
3. Only then rely on `strip-ai-on-pr.yml`.

---

## Verify the whole thing

```bash
bash .github/scripts/check-comment-blocks.sh      # exits 0
bash scripts/sync/workflows.sh --check            # command mirrors in sync
bash scripts/sync/rules.sh --check                # rule mirror in sync
bash scripts/check/ai-config.sh                   # citations, budget, hook wiring, pins
bash scripts/check/ai-config-probes.sh            # the pin rule, proved both ways
bash scripts/check/hook-probes.sh                 # every hook rule, both ways
bash scripts/check/gates.sh                       # the pre-commit list
bash .github/scripts/quality-gate.sh origin/dev   # the pull-request gate
```

Then the test no script performs: open a session and ask the agent to edit a file under
`src/lib/api/generated/`. If it does, the generated-output guard is prose rather than a guardrail:
check `generatedPaths` against your layout, and treat that as the general remedy whenever a rule is
not holding: move it into a `PreToolUse` hook or a gate step. In the same session, `/sandbox` shows
whether the Bash sandbox is running.
