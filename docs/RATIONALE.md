# Rationale

Why the odd-looking parts of this configuration are shaped the way they are.

Every entry below guards against a failure that is slow to diagnose. Several look like clutter and
are load bearing — this file exists so you can tell which is which before you tidy anything.

**One rule while reading: if a pattern here looks needlessly complicated, do not simplify it.**
Each one is followed by what breaks when you do.

---

## 1. One rule, two scope dialects

The same rule is written for two tools, and each reads its scope differently. Get either one wrong
and the rule stops loading, with no error, no warning and nothing in the logs. This is the
archetype for the whole file: the failure is silent, and silence reads as success.

**Claude Code (`.claude/rules/*.md`) takes a YAML list under `paths:`.** You write this side.

```yaml
---
paths:
  - 'src/components/**'
  - 'src/hooks/**'
---
```

A rule with a `paths:` list loads only once the session reads a matching file. A rule without one
loads into **every** session, next to `CLAUDE.md`, so it spends the always-loaded budget (§14).
Only `common/working-agreements.md` goes without `paths:`, on purpose.

**Antigravity (`.agents/rules/*.md`) takes one comma-separated string under `globs:`.**
`scripts/sync/rules.sh` writes this side from the first; never edit it by hand.

```yaml
---
trigger: glob
globs: "src/components/**, src/hooks/**"
---
```

The Glob Pattern field there is a single 250-character input. A YAML list looks tidier, parses as
valid YAML, and leaves the field empty, so the rule matches **no** file. The sync script turns each
`paths:` list into that string, fails past 250 characters, and gives a rule without `paths:`
`trigger: always_on`, so the rule loads in both tools at the same moments. Its `--check` mode fails
when a mirror drifts (§3). `.claude/anti-patterns/agent-rules-frontmatter-silent-drop.md` records
the other ways that side fails.

A glob that matches nothing fails the same silent way in either dialect: after a folder move, check
each rule's globs against the new layout.

---

## 2. `PreToolUse` blocks; everything else only complains

The single most important thing to understand about hooks.

| Event              | What exit 2 does                                                            | Any other exit code               |
| ------------------ | --------------------------------------------------------------------------- | --------------------------------- |
| `PreToolUse`       | **The tool call does not happen**, and stderr is the reason the agent reads | The call goes ahead, `1` included |
| `PostToolUse`      | Stderr reaches the agent, but the write has already landed                  | Nothing the agent sees            |
| `UserPromptSubmit` | The prompt is dropped: what the user typed is erased                        | The prompt goes ahead             |
| `SessionStart`     | Nothing it can block; stderr reaches only the user                          | The session starts                |

So a rule that must not be violated belongs in `PreToolUse` and exits 2. Put it in `PostToolUse`,
or exit 1, and you get a guard that appears installed, logs complaints, and prevents nothing. The
two prompt-side hooks here end in `|| true`, because an exit 2 there costs the user their prompt.
A crash and a hook timeout count as "any other exit code": a guard that crashes lets the call
through, which is why every guard here refuses when it cannot read its input (§15).

Three more parts of the contract, each a way a guard ends up doing nothing:

- **The tool call arrives as JSON on stdin.** A hook that reads a `CLAUDE_TOOL_INPUT_*` variable
  reads nothing, because none is set, and a guard that reads nothing lets everything through.
- **After a tool ran, a hook reaches the agent only through
  `hookSpecificOutput.additionalContext`.** Plain stdout from a `PostToolUse` hook goes to the
  debug log, so a reminder printed there is never read.
- **Hooks on one event run in parallel.** A formatter and a linter wired as two `PostToolUse`
  hooks race on the same file, and the linter can judge the text the formatter is rewriting. So
  one script, `post-edit.sh`, formats and then lints.

**Corollary: test a guard by triggering it.** A guard whose path pattern does not match your
directory layout never fires and never complains. Reading the script tells you what it intends;
only triggering it tells you what it matches. `scripts/check/hook-probes.sh` does that for every
rule, both ways.

---

## 3. `--check` mode, and why write mode cannot replace it

Mirror scripts run in two modes. Only one detects drift:

```bash
bash scripts/sync/workflows.sh           # write
bash scripts/sync/workflows.sh --check   # verify — this is the CI mode
```

A write-mode run **overwrites staleness before it can observe it**. Run it in CI and the mirrors
always look in sync, because the run just rewrote them: whatever drifted is erased, never reported.

`--check` catches four distinct things, and a checker that skips any one of them misses real drift:

1. A target file that no longer matches its source.
2. An **orphan** — a target with no source. This is the direction naive checkers forget.
3. `INDEX.md` drift, verified **both ways**: every command listed, and every listed command real.
4. Commands a third-party installer owns, which are exempt — see §4.

`scripts/sync/rules.sh --check` does the same for the rule mirror, and both run in pre-commit and
in the pull-request gate.

---

## 4. Third-party installers leave legitimate orphans

A skill installed by its own tooling writes into `.claude/skills/` and `.agents/skills/`, and some
installers also drop a command into `.claude/commands/`. None of it has a counterpart in
`_workflow-source/`, by design: the installer owns its versioning.

A naive drift checker flags these as orphans and advises deleting them or moving them into the
source directory. Both suggestions break the next upgrade.

`scripts/sync/workflows.sh` mirrors commands only, so a skill tree is never its concern. A command
an installer drops into a mirror goes in the script's `VENDORED` list, as a path relative to the
mirror (`tool/run.md`), and is then exempt from the orphan and `INDEX.md` checks. The list ships
empty: the design skill this template points at (`impeccable`, SETUP.md §7) is a user-invocable
skill, so `/impeccable` needs no file in `.claude/commands/`. If you add a drift checker of your
own, give it the same exemption before it files its first false report.

The same script reads a subfolder of `_workflow-source/` as a command namespace
(`_workflow-source/<folder>/<name>.md` is `/<folder>:<name>`) and keeps the folder in both mirrors,
so a namespaced command is neither flattened nor reported as an orphan.

---

## 5. The review workflow never uses `pull_request_target`

The AI review workflow needs a secret (the provider's token) and write access to post a comment.
`pull_request_target` offers both even to forks, by running the base branch's workflow with every
repository secret in scope, which is why it is the usual choice and why it is dangerous: a step
that checks out and runs the pull request's code hands those secrets to whoever opened it. GitHub
is moving to block that combination by default, and zizmor already reports the trigger.

So the workflow runs on `pull_request`, where a branch of this repository gets the secret and a
fork's run gets none and is skipped, and on `issue_comment` for an on-demand `/ask-deepseek`, which
runs from the default branch with the secret and is filtered to owners, members and collaborators
before a runner starts. Neither path checks out the pull request: the action reads the diff over
the API. Keep that property if you edit it; it is what makes the comment path safe on a fork.

Two smaller decisions in the same workflow, both deliberate:

- **No `synchronize` in the trigger types.** The action posts no sticky comment, so every push
  would add another review.
- **Base branch only, not the promotion branch.** A `dev → prod` diff re-adds the entire AI config
  that the strip pipeline removed, and the provider rejects a diff that size.

---

## 6. The strip pipeline: one list, both directions, merge not rebase

Three rules, each against a failure the strip is prone to.

**One list, sourced — never copied.** `STRIP_PATHS` lives in `strip-paths.sh`; the other three
scripts source it. Duplicated, one updated copy beside a stale one makes the strip half-land:
production keeps part of the config, and nothing reports an error.

**Verify both directions.** Asserting that `prod` lost the files misses the failure where `dev`
lost them too. Only the second assertion catches that, and it is the one people leave out.

**Merge, never rebase, on the back-merge.** Rebasing rewrites the strip commit, and the branches
diverge permanently.

One more: `git rm --cached` leaves the files present but untracked, which blocks a subsequent
rebase for reasons that look unrelated to the strip.

---

## 7. The skip-CI marker that disarms gates silently

GitHub's skip-CI marker matches anywhere in a commit message, and on the head commit of a pull
request it stops every workflow that pull request would start. A workflow that stamps the marker on
a commit it pushes to the development branch therefore prevents nothing there, and disarms the
quality gate on **every** promotion opened from that commit.

**A pull request with no checks at all is not a slow queue.** Three causes, all of which report as
"pending" rather than as a failure, so they survive indefinitely:

1. A skip-CI marker on the head commit.
2. A conflicting pull request — the provider builds a merge commit to run `pull_request`
   workflows; a conflict means no merge commit, so nothing starts.
3. A gate whose trigger omits the review branch. `branches: [prod]` alone lets everything reach the
   development branch ungated.

Check `mergeable` and the head commit's message before concluding CI is slow. That is also why
neither commit the strip pipeline writes carries a marker. Nothing is triggered by a push, so a
marker prevents nothing anywhere; and the back-merge commit on the development branch can be the
head of the next promotion pull request, where a marker disarms everything.

---

## 8. CI script divergence between repos is usually correct

If you run this layer in more than one repository, their quality gates will differ, and the tempting
conclusion is that they have drifted and should be unified.

Check what the variance tracks first. If the gates cluster by **repo role** — applications,
services, documentation sites, each with a consistent shape — that is not drift. Documentation
repos do not need the same checks as applications; a backend does not need translation-key parity.

Unifying that deletes legitimate checks. Divergence by role is the correct design; the useful thing
to hunt for is divergence **within** a role.

---

## 9. Generated clients are invisible to symbol search

If your generated API client is gitignored and your symbol-search tool respects gitignore, the
client does not exist as far as symbol search is concerned. Searches for generated hooks or types
return nothing, even though the code is on disk.

This is the one case where an empty result does not mean "absent from the scope you searched" — the
files are filtered out before the search rather than rejected by it.

Use the committed API spec instead. Turning off the gitignore filter is not the fix: it also
exposes every `.env` file to symbol search and file reads.

---

## 10. Frontend-specific: text that is hostile to the docs generator

If you generate a documentation site from JSDoc, two classes of source text will break the build,
and both come from the source being *correct*:

**Multi-line destructured parameters inside a table cell.** The newline ends the inline-code span,
leaving an unbalanced `{` that the parser reads as an expression. Collapse whitespace and escape
the delimiters before the value reaches a table cell.

**Element names in prose.** A JSDoc line describing `<Foo>` parses as an unclosed tag. Escape `<`
before tag-shaped text in prose.

A brace-balance heuristic is the obvious detector and gives false positives on multi-line balanced
expressions. Escaping at render time is more reliable than detecting at write time.

---

## 11. Rule documents get longer as the risk gets quieter

Counter-intuitive, and worth stating so you do not "fix" it.

A backend rule document is typically **larger** than a frontend one, while its contract document is
**much smaller**. Security and data-access rules have to be spelled out — "validate input at system
boundaries" cannot be compressed into one actionable sentence; it needs the boundary list and the
failure behaviour. Meanwhile backend architecture is more uniform, so the contract states the shape
once.

The practical implication: **do not normalise document length across repos.** If your backend rule
document is as short as your frontend one, there are probably security rules that were never
written down.

---

## 12. State intentional absences explicitly

If an architectural layer does not exist yet, the contract document should say so in as many words:

```markdown
The service hook layer does not exist yet. All data fetching currently goes through the client.
This is deliberate and planned, not drift.
```

Without that sentence, the next audit reports it as a finding, and someone spends an afternoon
re-deriving that it was intentional.

**Every deliberate absence is worth one sentence in the contract.** This is the cheapest rule in
the file and the one most often skipped.

---

## 13. Count file-presence claims; do not infer them

A claim of the form "file X does not exist in repo Y" must be **counted**, not assumed.

A presence claim is cheap to make and easy to get wrong: the directory you expect may exist after
all, and one that differs may have been written by a skill installer rather than by any
architectural decision. Only a count tells them apart.

Auditing file presence is far cheaper than auditing intent, and it is the kind of claim that gets
repeated once written down. Run the `ls`. The counts in this repository's README come from
`git ls-files` for the same reason.

---

## 14. What loads every session has a byte budget

`CLAUDE.md` plus every rule without `paths:` loads before the task does, on every task, so it is
the most expensive text in the repository. `scripts/check/ai-config.sh` holds it to 15,000 bytes in
pre-commit and in the pull-request gate. Today it is 12,789: `CLAUDE.md` at 8,511 and
`working-agreements.md` at 4,278.

- **Bytes, not lines.** A line count rewards long lines; the budget reads `wc -c`.
- **No `@` imports in `CLAUDE.md`.** An import pulls a whole file into every session. The check
  refuses one even inside an HTML comment, so a commented-out import cannot come back unnoticed.
  `CLAUDE.md` § On-demand References names each file and says when to read it instead.
- **Over budget, move text out, do not compress it.** Anything tied to a path becomes a `paths:`
  rule; anything a person reads becomes a doc; anything deterministic becomes a hook or a gate.

What fails when the budget goes: the rules that matter compete with boilerplate for the same
attention, and nobody can say which lines the agent actually weighed.

---

## 15. Guards read commands like a shell, and prove it with probes

A guard that matches substrings fails both ways. It blocks harmless commands: a commit message that
mentions `git push origin main` is not a push. And it misses real ones: `git -C . push origin
main`, `bash -c '...'`, `eval`, a push after `&&`. `safety-check.sh` reads a command the way a
shell does (quotes, heredocs, `$( )`, backticks, `bash -c`, `eval`, aliases, pipes into a shell)
and judges each command it finds. Wrappers (`timeout`, `sudo`, `env`, `xargs`, ...) and package
runners (`npx`, `bunx`, `npm`/`pnpm`/`yarn`/`bun` `exec`, `dlx`, `x`) are peeled, and the shell
text a runner takes (a `-c` string, or the words `bun exec` and `yarn exec` join) is read as a
script.

It **fails closed**. Only exit 2 blocks (§2), so a guard that crashes, or runs past its timeout,
would let the call through; instead, a payload it cannot parse, an analyzer crash or an analysis
over 8 s is refused. Without python3 a few plain-text rules stand in (protected pushes, recursive
deletes, a hard reset, a forced `clean`, `--no-verify`, `HUSKY=0`, `.env*` names, the unlock), and
Claude is told so; everything else runs unchecked on that machine.

The same holds for a command it can parse but cannot resolve. `eval` of built text, a decoded
payload, a script piped into a shell, a command substitution used as a command name or a file
operand, a path built through `IFS` or an array, a package runner whose command or shell text is
built from `$( )` or an unknown variable: each is refused whether or not `.env` or the unlock
appears in plain text, because a guess that lets one through is the failure the guard exists to
prevent. A git setting that changes what git runs, loads or connects to (an alias, an include,
`core.sshCommand`, a credential helper, a proxy, `url.*.insteadOf`, `safe.directory`, ...) is
refused whatever its value, whether passed with `-c`, `GIT_CONFIG_*` or written with `git config`,
because each hands git something to run, load or reach that the command line does not show. The
refusal names the way through: the user runs the command with `!`, which runs as the user, outside
the hooks and (in an ordinary session) outside the sandbox. Over-refusal costs one keystroke; a
false allow costs a secret.

`scripts/check/hook-probes.sh` proves every rule both ways, what it must stop and what it must let
through, in temporary repositories, with the fail modes (python3 missing, jq missing, a broken
payload) and a linked git worktree included. It runs in pre-commit when a commit stages a hook,
`settings.json`, the probes, `unlock.sh` or a file under `scripts/env/` (a commit of other code
skips it, since it takes minutes), and on every pull request. A change to a hook adds one probe it
must stop and one it must let through, and is proven load-bearing by breaking the rule and
watching the probe fail.

The limit is stated, not hidden: a text analyzer reads the command line, not the script a command
runs, so a file the agent writes and then runs is executed unread, and a program that runs commands
of its own (`watch`, `flock`, `parallel`) is judged by name only. That is why
`.claude/settings.json` also turns on Claude Code's Bash sandbox by default, which the operating
system enforces on every sandboxed process: no reads of `.env*` files or the backups, no writes
under `.claude/state/unlock/`. The hooks are the guardrail; the sandbox is the boundary below it
where the platform supports it (macOS, or Linux and WSL2 with `bubblewrap` and `socat`; where it
cannot start, Claude Code warns and runs without it unless `sandbox.failIfUnavailable` is set, and
the hooks still apply). `"sandbox": {"enabled": false}` turns it off and leaves the hooks running.
`docs/unlock.md` lists what the two still do not stop.

---

## 16. MCP servers are pinned, and their permissions live in `settings.json`

`.mcp.json` starts five servers, and each one runs code fetched at session start. An unpinned
`npx` or `uvx` package runs whatever was published last, the moment a session opens, so every
server here is pinned to one release: a full `x.y.z` version, a full commit SHA or a digest.
`ai-config.sh` fails on anything that can move (a bare name, `@latest`, a range, `@1` or `@1.2`, a
short SHA), and `ai-config-probes.sh` proves that rule both ways on temp repos. Move a pin on
purpose, after reading what changed.

Claude Code reads no permission field from `.mcp.json`: an `alwaysAllow` list there looks like
configuration and pre-approves nothing. Permissions for MCP tools live in `.claude/settings.json`,
which is where the `ask` rule on `mcp__db-prod__execute_sql` sits.

That `ask` rule is not the layer that holds production, though. `bypassPermissions` mode skips
`ask` rules, so both database servers start with `--access-mode=restricted`, which makes the server
itself run every query read-only. Servers used once a month live in `.claude/mcp/*.example.json`
and load per session with `claude --mcp-config`, so their tool definitions cost no context the rest
of the time.

---

## 17. Skills, commands, agents and hooks are scanned like dependencies

A skill, a slash command, a subagent or a hook is text the agent follows with its own permissions.
An instruction hidden in an HTML comment, or a shell step that sends a `.env` file somewhere, is a
supply-chain risk like a compromised package, and review rarely catches it because the file reads
as documentation.

`scripts/check/skills.sh` runs SkillSpector, pinned to one commit, over the skills, the command
sources in `_workflow-source/`, the subagents and the hooks: the staged targets in pre-commit, the
changed ones on a pull request. It runs locally (`--static`); the
`--llm` mode, which sends file text to a provider, is never used in CI.

- **Fix the text first.** Most findings are wording: an extra HTML comment, or a sentence that reads
  like an instruction to bypass something. Reword it.
- **Suppress narrowly, with a reason.** `.skillspector-baseline.yaml` holds one entry per finding
  (id, file, matched text, reason), third-party trees by hash, and files the scanner read only in
  part, by exact file and reason code. A file read only in part fails otherwise: an unread part is
  not a clean one.
- **Review every diff to the baseline by hand.** It is the list of findings this gate ignores.

---

## 18. Merge commits, never squash

`/merge-pr` and `/promote` merge with `gh pr merge --merge`, and SETUP §8 turns squash merging off.
`/branch-cleanup` deletes a branch only when GitHub reports it `0` commits ahead of `dev`, which is
exact only when merges are merge commits. A squash-merged branch always reads as ahead, so the
cleanup would either keep every branch or delete on a guess, and it is written never to guess.

A merge commit also keeps each commit with its own date and author, where a squash folds a branch
into one commit dated the merge day. `git log --first-parent` gives the one-line-per-change view
when you want it. The strip's back-merge into `dev` is a merge for the same reason (§6).

---

## 19. The deploy is a webhook, and names no vendor

`ci-cd.yaml` builds nothing. When a pull request into `prod` is merged, it posts to the
`DEPLOY_WEBHOOK_URL` secret through `.github/scripts/trigger-deploy.sh`, retrying while a build
still refuses connections, and the deployment platform builds from git.

- **Every platform has a deploy hook**; not every platform wants a registry image. A build-and-push
  job assumes one deployment model and costs minutes and storage on every promotion.
- **Switching platforms is one secret.** Nothing in the workflows, scripts or commands names a
  vendor. The promotion commands keep the platform as placeholders (`<deploy platform>`,
  `<read-env command>`), and the on-demand MCP examples use neutral names (`deploy-platform`,
  `vps-provider`) that you point at your provider's package.
- **A pull request closed without merging deploys nothing**, and neither does a direct push to
  `prod`: the job checks `merged` and the base branch itself, and deploys the fixed ref
  `refs/heads/prod`.
- **The `NEXT_PUBLIC_*` values are build arguments on the platform**, not Actions secrets:
  `next build` inlines them, so they belong where the build runs. `.env.production.example` lists
  them, and the promotion commands audit the platform's configuration against it.

If your platform pulls a prebuilt image, add that job yourself; the template does not assume one.

---

## 20. CI starts only from pull requests

No workflow here has a `push:` or `schedule:` trigger, and nothing opens a pull request on its own.
Every run is tied to a change someone proposed.

- **A push trigger re-checks what a pull request already checked.** `dev` and `prod` change only
  through merged pull requests, whose gate ran on the merge result. The deploy and the strip run on
  the merged pull request instead (`types: [closed]` with a `merged` guard).
- **A schedule runs on code nobody changed**, spends minutes every week, and opens pull requests
  nobody asked for; copied into every repository made from this template, it does all three
  everywhere. Updates are a decision: `pinact run -u --min-age 7` for the pinned actions, `bun
  update` for packages, each in an ordinary pull request that dependency review and the gate read.
- **`pull_request_target` is never used** (§5), every `uses:` is pinned to a full commit SHA, the
  top-level token is `contents: read`, and no `${{ }}` expression reaches a `run:` block.
  `workflows-lint.yml` checks those with actionlint, zizmor and `pinact --check` whenever
  `.github/` changes.

The cost is accepted on purpose: an advisory published after a merge surfaces at the next pull
request that touches dependencies, or when someone runs the audit by hand. Nothing watches the
repository between changes.

---

## 21. The unlock: opened by the user, closed by the clock

An earlier design let a phrase in the prompt lift a deny rule for one action. Anything the agent
reads (a file, an issue, a web page) can contain that phrase, so a prompt-side permission is a
permission for whoever writes text the agent reads. No hook here reads permission from the prompt.

What replaced it:

- **Only the user opens it.** `scripts/ops/unlock.sh env|db` writes `.claude/state/unlock/<target>`
  with an expiry time. The user runs it with `!`, which does not pass through the hooks; the hooks
  refuse it from the agent in the forms the probes cover, and refuse any write, copy, link or
  delete under `.claude/state/unlock/`. A file that is expired, readable by others, a link, or
  tracked by git counts as locked. A command the analyzer cannot resolve is refused (§15), and a
  package runner's shell text (a `-c` string, or the words `bun exec` and `yarn exec` join) is
  unwrapped and checked like `bash -c`. What stays open to a text analyzer is what it cannot read:
  a script file the agent writes and then runs, and a program the hooks do not know that runs
  commands of its own.
- **It closes by itself.** `env` opens for 20 minutes and `db` for 15 by default, so a forgotten
  unlock does not stay open; `off` closes both at once.
- **Secrets stay out of the transcript.** The shell never reads a real `.env*` file. `show.sh` lists
  every key with secrets masked; `set.sh` changes one value while `env` is open, backs the file up
  and logs only the key name.
- **Production reads are always allowed; writes wait.** `db-guard.sh` lets one read-only statement
  through and holds anything else, including SQL it cannot parse. The server itself also starts
  read-only (§16), because `bypassPermissions` skips `ask` rules and a text parser can be fooled by
  a function of your own that writes.

The hooks are a guardrail against slips and injected instructions (§15). Under them,
`.claude/settings.json` turns on Claude Code's Bash sandbox, which denies every sandboxed write
under `.claude/state/unlock/` and every sandboxed read of a `.env*` file, whatever route the
command took; `docs/unlock.md` says what the two layers still do not stop.

---

## 22. Every AI-layer check passes on a stripped branch

After a merge into `prod`, the strip pipeline removes `.claude/`, `_workflow-source/`, `CLAUDE.md`
and the rest of the layer, but `scripts/check/` and the pull-request gate stay. `/promote-deploy`
re-runs the gate on that stripped `prod`, and a hotfix branch cut from `prod` starts without the
layer too. A check that fails when its inputs are gone would turn every such run red for no reason,
and a gate that is always red is a gate nobody reads.

So each check of the layer states what it does on a checkout without it, and exits 0:
`ai-config.sh` when `.claude/` is absent, `sync/workflows.sh` and `sync/rules.sh` when their source
folder is absent, `hook-probes.sh` when `.claude/hooks/safety-check.sh` is absent, and the skill
scan when `.claude/` is gone. Each prints that it skipped, so the log still says what did not run.
A check you add to the layer needs the same line, tested on a stripped checkout before you rely on
it.
