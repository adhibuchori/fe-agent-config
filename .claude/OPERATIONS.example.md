# Operations — Hooks, GitHub and CI, Reviews, MCP, Deploys, Access

> **List it in the CLAUDE.md "On-demand References" table; never `@`-import it.** An import loads
> the whole file into every session. This is a template: copy it to `.claude/OPERATIONS.md`, fill
> every `<placeholder>`, and delete the sections your project does not use.
>
> Each entry names a trap and how to avoid it. Read the section that matches the task before
> acting, and add to it through `/learn-session`: one entry per learning, with its reason.
>
> Commands are named as this template ships them. Installed from the agent-config-kit plugins, the
> same commands carry the plugin's prefix: `/agent-core:learn-session`, `/agent-core:rca`,
> `/agent-core:branch-cleanup`, `/agent-core:promote` and `/agent-deploy:promote-deploy`.

## Claude Code hooks

**The contract.** The tool call arrives as JSON on **stdin**. Exit **2** blocks a PreToolUse call,
and its stderr is the reason Claude reads; every other exit code lets the call through, `1`
included. PostToolUse stdout is only logged: findings reach Claude as
`hookSpecificOutput.additionalContext`. Claude Code never sets `CLAUDE_TOOL_INPUT_*` environment
variables, so a hook that reads them does nothing and exits 0 every time.

**Hooks on one event run in parallel**, and start in the session's current directory:

- Reference every hook as `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<name>.sh"` with a `timeout`,
  so a `cd` earlier in the session cannot break it.
- Two PostToolUse hooks on the same file race. Format and lint run in one script (`post-edit.sh`),
  in that order.
- SessionStart and UserPromptSubmit hooks end in `|| true`: a failure there must never erase a
  prompt.

| Script               | Event                             | Job                                                                                                |
| -------------------- | --------------------------------- | -------------------------------------------------------------------------------------------------- |
| `lib.sh`             | —                                 | shared helpers and the shell-command analyzer (quoting, heredocs, `$( )`, `bash -c`)               |
| `session-start.sh`   | SessionStart                      | makes zsh behave like bash on unmatched globs, `=word` and word splitting                          |
| `prompt-intent.sh`   | UserPromptSubmit                  | points `/debug` at `/rca`; prunes idle sessions' hook state                                        |
| `safety-check.sh`    | PreToolUse (Bash)                 | destructive commands, protected-branch pushes, skipped hooks, `.env*` reads and writes, the unlock |
| `mcp-guard.sh`       | PreToolUse (GitHub MCP writes)    | GitHub MCP writes straight onto a protected branch                                                 |
| `db-guard.sh`        | PreToolUse (production SQL tool)  | SQL that may write, until the user runs `unlock db` (`docs/unlock.md`)                             |
| `generated-guard.sh` | PreToolUse (Write, Edit, Serena)  | hand edits to generated output (frontends and docs sites)                                          |
| `migration-guard.sh` | PreToolUse (Write, Edit, Serena)  | hand edits to generated migrations (backends and pipelines that own a schema)                      |
| `post-commit.sh`     | PostToolUse (Bash)                | shows what a commit carried; warns on paths its pathspec did not name                              |
| `post-edit.sh`       | PostToolUse (Write, Edit, Serena) | format, then lint, in one script so they cannot race                                               |

A hook whose tool or folder the repo does not have switches itself off, so one copy serves every
stack. Per-repo settings live in `.claude/agent-config.json` (see
`.claude/agent-config.example.json`), every key optional; a key the file sets replaces its default
whole:

| Key                 | Default                                        | Read by                                  |
| ------------------- | ---------------------------------------------- | ---------------------------------------- |
| `protectedBranches` | `dev`, `prod`, `main`, `master`                | `safety-check.sh`, `mcp-guard.sh`        |
| `protectedPaths`    | source, test, script and agent-config folders  | `safety-check.sh` (destructive commands) |
| `generatedPaths`    | a generated API client and an OpenAPI contract | `generated-guard.sh`                     |
| `migrationsDirs`    | the usual drizzle and Alembic folders          | `migration-guard.sh`                     |
| `commandWrappers`   | none                                           | `safety-check.sh`: wrappers peeled off   |
| `localePairs`       | none                                           | `post-edit.sh`: files that change as one |

`commandWrappers` names commands that run another command (a secrets loader, an output filter), so
the analyzer judges the command they wrap. Multi-repo workspaces stay off unless
`AGENT_WORKSPACE_ROOT` names the folder that holds the repos.

**How the guards fail.** They fail closed: a payload that is not a JSON object, a `python3` that
crashes or runs past its cap, or SQL `db-guard` cannot read refuses the call; only a machine with no
`python3` falls back to plain-text rules for the most dangerous cases (`.env*` names, the unlock,
the guard files themselves). Each guard keeps one deadline for its whole run, inside Claude Code's
hook timeout (which would let the call through), and says so when it runs out of time. The command
analyzer reaches `python3` through a file descriptor, never as an argument, because Linux caps one
argument's size. Every `git` a hook starts disables `core.fsmonitor`, a linked worktree is guarded
like its main checkout, and a symlink is judged both as named and as the file it points to.

**A guard the agent could rewrite would guard nothing.** The shell may read, run and copy out the
guard scripts, the probes, the unlock script and `scripts/env/`, and only read the settings files;
every write route the analyzer can read (redirects, `tee`, `cp`/`mv`, `sed -i`, inline `python -c`,
`git checkout -- <file>`, …) is refused. A change goes through the Edit tool, where the user sees
the diff, or the user runs it with `!`.

**No hook reads permission from the prompt.** What is costly to undo stays refused whoever asks: a
push to a protected branch (the user runs it with `!`), deleting one,
`gh pr merge --delete-branch`, skipped hooks (`--no-verify`, `HUSKY=0`, `core.hooksPath`),
`alembic downgrade` in a repo that has `alembic.ini`, shell writes to `.env` files, and destructive
commands. When to commit is the working agreements' call, not a hook's.

**Prove every rule both ways.** `scripts/check/hook-probes.sh` and `scripts/check/hook-probes.tsv`
hold what each hook must stop and what it must let through; pre-commit runs them when a hook
changes, and CI runs them on every pull request. A new rule adds a probe of each kind. Beyond the
probes, verify a hook by its effect: run `claude -p` in a disposable copy whose git remote is
removed.

## GitHub and CI

- Never write GitHub's skip-CI marker anywhere in a commit message, PR title or PR body, not even to
  describe it. It matches anywhere in the text, and in a promotion PR title it silences the
  production deploy. No command writes it: the workflows run only on pull request events, so a push
  has no run to skip.
- Merge with `--merge`, and turn squash merging off in the repository settings. A merge commit keeps
  every commit and its own date; squash re-dates the work to the merge day, and leaves the merged
  branch "ahead" of `dev`, so `/branch-cleanup`'s merged check can never pass for it.
- Branches follow the branch model in CLAUDE.md § Branching: `internal/{scope}` → `dev` → `prod`.
  The head of a promotion PR is `dev` itself: never `gh pr merge --delete-branch`. Delete an
  `internal/*` head by name after the merge, once `headRefName` has been printed, unless the user
  keeps it as a long-lived scope branch.
- Know what a promotion PR runs. If the gate is skipped or reduced for `dev` → `prod`, the real
  signal is the gate on the last PR into `dev`, or the full gate run locally on merged `dev`.
- A long-lived `internal/<scope>` branch falls behind `dev` after each promotion. When it is zero
  commits ahead, fast-forward it: `git push origin origin/dev:refs/heads/internal/<scope>`, then
  confirm `git rev-list --count origin/internal/<scope>..origin/dev` prints 0.
- Workflows run on pull request events only (`pull_request`, a merged PR's `closed`,
  `issue_comment`, `repository_dispatch`, `workflow_call`). No `push` trigger and no scheduled
  (cron) workflow: nothing runs or opens a pull request on its own. Update dependencies by hand
  (`pinact run -u` for actions, the package manager for packages); dependency review checks them on
  the pull request.
- Read check results unfiltered: `gh pr checks <n>` (`rtk proxy gh pr checks <n>` where RTK is
  installed), never through an output wrapper whose summary shifts between calls.
  `bash scripts/ops/pr-ready.sh <n>` reads a PR's checks, mergeability,
  unresolved threads and head branch in one call, and exits 0 only when it can be merged. A skipped
  or neutral check is not a pass: it blocks until the user confirms it is expected, and then
  `--allow-skipped` accepts it.
- A review bot that fetches the diff media type is refused past GitHub's diff size limit (HTTP 406),
  and may trigger only on some PR events. Record its absence on the PR; never read it as a pass.
- A gitleaks negative test needs a genuinely random value: documented examples are allowlisted
  upstream, and low-entropy strings fail the entropy check.
- Every job sets `timeout-minutes`. Runner pools and their variables are in
  `.claude/CI-RUNNERS.md`.

## Reviews

- `/security-review` diffs the whole branch against its base. On a long-lived branch, scope review
  subagents to `git diff $(git merge-base HEAD <base>)...HEAD -- <source dirs>` and exclude the
  agent-config folders (`.agent/`, `.agents/`, `.claude/`).
- Tell a review subagent which gates are already green, so it spends its budget on judgement.
- Rank findings by whether they assert something checkable, and run the cheapest check first.
- Re-read the approved plan against the diff; an unimplemented item never announces itself.
- A handler duplicated across two components usually hides a second defect. Look for it before
  fixing the first.
- Report "consistent but wrong" idioms as observations with a reason, not as drive-by diffs.
- Decline a bot's finding with evidence, after verifying the one sub-point that could be right.

## MCP servers

**Pin every server.** `.mcp.json` pins each `npx`/`uvx` package to an exact version (`@x.y.z`,
`@vX`, `==x.y.z`); `scripts/check/ai-config.sh` fails on an unpinned one. Hosted HTTP servers carry
no version: the endpoint is the provider's. Upgrade deliberately: change the pin, restart the
session, and confirm the handshake with `claude mcp list`.

| Server              | Pin                                           | Note                                              |
| ------------------- | --------------------------------------------- | ------------------------------------------------- |
| `serena`            | `git+https://github.com/oraios/serena@v1.7.0` | symbol-level search and edits                     |
| `github`            | hosted HTTP                                   | `GITHUB_PERSONAL_ACCESS_TOKEN` in the shell       |
| `context7`          | `@upstash/context7-mcp@4.1.1`                 | current library docs                              |
| `db-dev`, `db-prod` | `postgres-mcp==0.3.0` with `mcp==1.9.4`       | restricted access mode; see `.claude/DATABASE.md` |

**Rarely used servers load on demand.** Every configured server adds its tool list to each
session. A server you reach for once a month lives in `.claude/mcp/<name>.json` instead, loaded for
one session with `claude --mcp-config .claude/mcp/<name>.json`. Three examples ship:
`deploy-platform.example.json`, `vps-provider.example.json` and `cloudflare.example.json` (a hosted
server; it reads `CLOUDFLARE_API_TOKEN` from your shell). Copy one to `<name>.json`, fill the
placeholders, and pin the package to the exact version you verified. The pin check skips the
`*.example.json` templates and reads every copy, so a copy still carrying `<pinned-version>` fails
until it names a real version.

- The example env names (`DEPLOY_PLATFORM_URL`, `DEPLOY_PLATFORM_API_KEY`,
  `VPS_PROVIDER_API_TOKEN`) stand for whatever names your package reads: rename the keys to its
  own, and keep the `${VARIABLE}` values pointing at your shell.
- A package that ships several servers (hosting, DNS, domains) is one entry per server you need,
  each `npx --package=<package>@<version> <server-command>` at the same pin. Load only those.
- If the deploy platform's server can redact environment values in its output, turn that on: a
  tool result is part of the transcript.
- Disable the server's tool groups your plan cannot use. They fail when called, and they cost tokens
  in every session that loads the server.
- Secrets are `${VARIABLE}` references resolved from your shell, never literals. Claude Code expands
  them; a `curl` copied from the file sends the literal text and gets a 401.

**Permissions for MCP tools live in `.claude/settings.json`, never in `.mcp.json`**, which has no
permission field Claude Code reads (`alwaysAllow` there is ignored). `mcp__db-prod__execute_sql` is
an `ask` rule. `bypassPermissions` mode skips `ask` rules, which is why `db-prod` also runs in
restricted access mode.

## Deploys

Deploy target: `<deploy platform>`, app `<app-name>` (`<app-id>`), `https://<app-host>`. The
`/promote` and `/promote-deploy` commands carry the adapter commands for this target.

**Read state cheapest call first.** "Did it deploy" is answered by the newest deployment entry, not
by the whole app record. Deployment lists are not guaranteed sorted: pick the newest by its
created-at timestamp, never by position.

**Verify against a time threshold.**

- Count only deployments created after the merge (`gh pr view <n> --json mergedAt -q .mergedAt`,
  in UTC). "No new entry yet" means not finished, never success.
- A webhook that never fired leaves no failed deployment behind, only an absence, and it fails per
  app: one app's success proves nothing about another's.
- A green Actions run is not evidence that production changed.
- Size the wait from the app's own build history, and wait once.

**A status field may not separate "building" from "healthy".** A `/health` 200 during a build is the
previous container answering.

**Environment writes are read-modify-write.**

- Read the whole current configuration first: runtime env, build arguments, build secrets. Write it
  back with your change, and confirm by variable count before and after.
- Saving does not redeploy. Say so, because "updated" reads as "live".
- Never write to the platform's own database when it has an API: values may be encrypted at rest,
  and a naive string append can blank a production environment.
- When plaintext must not enter the transcript, do the read-modify-write on the host, or through a
  file that only key names are printed from.

**A deploy webhook expects a push payload.** A bare `POST` can be declined with a 3xx that deploys
nothing, and `curl --fail` does not treat 3xx as failure. Use the repository's trigger script,
which checks the status code.

**A host behind an access proxy or SSO answers an anonymous request with its sign-in page**, often
with a 200. That proves routing, not the build: the evidence is the deployment record.

Capabilities can live as separate stacks or services on the platform: search before saying one does
not exist. A cleanup job may prune containers, images and build cache; it never prunes volumes.
Delete volumes one at a time, so an `in use` refusal can stop you.

## Container firewall trap

**Docker publishes ports around the host firewall.** The daemon writes its own iptables rules, and
they run before UFW's, so `ufw status` never describes what the internet can reach through a
published port. UFW governs only what the host itself serves, such as SSH.

- Publish a port only you need to `127.0.0.1` (`127.0.0.1:5432:5432`), and reach it through a
  tunnel.
- Or drop it for the public interface in the `DOCKER-USER` chain, in iptables and ip6tables:

  ```
  iptables -I DOCKER-USER -i <public-interface> -p tcp -m conntrack --ctstate NEW --ctorigdstport <port> -j DROP
  ```

  `--ctorigdstport` matches the published port, because `DOCKER-USER` sees packets after DNAT, when
  the destination is already the container's port. `-i <public-interface>` keeps loopback (where a
  tunnel lands) and container-to-container traffic working.

- Make the rules survive a Docker restart (a unit ordered after `docker.service`), and re-check
  after a deploy that changes port publishing and after a Docker upgrade.
- A network that answers every outbound TCP connect itself cannot test exposure: every port looks
  open from it. Test from another network, or prove it on the host with `iptables -vnL DOCKER-USER`
  counters.
- Reach a database or cache through the tunnel on `127.0.0.1`, never through the public IP and
  port, GUI clients included.

## Skill scanning

`scripts/check/skills.sh` runs SkillSpector, pinned by the script, over skills, commands
(`_workflow-source/`), subagents and hooks.

| Command                                             | When                                                                    |
| --------------------------------------------------- | ----------------------------------------------------------------------- |
| `bash scripts/check/skills.sh --staged`             | pre-commit, when a skill, command, subagent or hook is staged           |
| `bash scripts/check/skills.sh --changed origin/dev` | the CI gate, only when the PR touches one                               |
| `bash scripts/check/skills.sh`                      | full static scan                                                        |
| `bash scripts/check/skills.sh --llm`                | adding or upgrading a vendored skill; sends the scanned text to a model |

The gate fails on any unsuppressed finding at MEDIUM or above, and on a target it could not read.
Triage every finding as a claim:

1. **Real, in your own content** — fix the source (`_workflow-source/`, then sync).
2. **In a vendored skill, real or not** — never edit it; its lock hash pins it. Decide with the
   user: turn it off, remove it, or accept it under `vendored:` in `.skillspector-baseline.yaml`
   with the reason and the tree hash the gate prints.
3. **A false positive in your own content** — a narrow `rules:` entry (rule id, file, matched text)
   with a `reason`. Never suppress a whole rule id.

A `vendored:` entry stops blocking only while the recorded hash matches, so an upgrade fails the
gate until it is triaged again.

## Unlock

`.env*` files and production writes are locked by default and only the user opens them, for a few
minutes (`bun unlock env`, `bun unlock db`; `npm run unlock …` where there is no bun). While `env`
is open the agent changes one value with `scripts/env/set.sh`, reading the value from stdin so it
never enters the transcript; `scripts/env/show.sh` prints every key with secrets masked, locked or
not. The whole flow, what it does not stop, and the per-package-manager commands: `docs/unlock.md`.

## Secret scan

`bash scripts/check/secrets.sh` runs `gitleaks` over the staged changes on every commit (the gates
list, or `.pre-commit-config.yaml`) with the repo's `.gitleaks.toml`, so a secret is refused before
it is committed, not found after it is pushed. It fails, never skips, when gitleaks is missing; a
release other than the one CI pins still scans, with a warning. CI scans the pushed history again.

## Server access

Reach a server through one path you can prove is guarded, and keep a break-glass path for when it
is down:

- **One way in.** SSH through a tunnel behind an identity-aware access proxy, with the public SSH
  port closed at the firewall except for the provider's own console. Prove the closed state from
  outside after any change: a direct connect to port 22 must time out, and the tunnel must work.
- **Break-glass, cheapest step first:** a name that does not resolve is the local resolver (compare
  with a public resolver); an expired access session is a fresh login; a hanging tunnel is the
  tunnel service (restart it from the provider's web console); no tunnel at all means opening port
  22 briefly from a trusted network, fixing, and closing it again; a host that will not boot is the
  provider's recovery mode.
- **Keep what the console depends on.** A provider may rotate its own keys in `authorized_keys`;
  deleting them can lock its web console out.
- **A network that answers every connect itself** (some mobile carriers) cannot test exposure: test
  from another network, or read the firewall counters on the host.

## Edge: client IP behind a CDN or proxy

A rate limiter or an audit log that keys on a client-IP header is only as honest as the path to the
origin:

- **Accept traffic only from the CDN** when you trust its client-IP header. Anything that can reach
  the origin directly can send that header itself and mint a fresh rate-limit bucket per request,
  on exactly the routes (sign-in, one-time codes) the limiter protects.
- **Restrict at the reverse proxy's router, not the host firewall**, when the same ports serve sites
  that are not behind the CDN: a firewall rule would take them offline. Attach the allowlist
  through the deploy platform's own settings, so a redeploy does not silently drop a hand edit.
- **Do not make the proxy "trust" the CDN's forwarded headers** to fix this: a proxy that
  overwrites `X-Real-Ip` with the real peer is unforgeable; one told to preserve what the CDN sends
  passes a client-supplied value straight through.
- **Verify the real peer address reaches the proxy** before allowlisting (a packet capture on the
  container bridge), and leave port 80 open for ACME HTTP-01 when it only redirects to HTTPS.
- **Keep internal hops internal.** A frontend server calling its backend through the public URL goes
  back out through the CDN, which overwrites the client-IP header with the server's own address and
  collapses every visitor into one bucket. Call the internal service address.
- The CDN's address ranges change: re-check the allowlist when legitimate traffic starts to 403.
