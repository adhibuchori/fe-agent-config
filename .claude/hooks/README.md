# Claude Code hooks

These scripts guard what an agent does in this repo. `.claude/settings.json` wires them;
`scripts/check/hook-probes.sh` proves each rule both ways (what it must stop, what it must let
through) and runs in pre-commit and CI whenever a hook, `settings.json` or the probes change.

## The contract

- Claude Code sends the tool call as **JSON on stdin**. No `CLAUDE_TOOL_INPUT_*` variable exists, so
  a hook that reads one does nothing.
- **Exit 2 blocks** a PreToolUse call, and stderr is the reason Claude reads. Every other exit code,
  `1` included, lets the call through.
- After a tool ran, a hook reaches Claude only through `hookSpecificOutput.additionalContext`;
  plain stdout from PreToolUse and PostToolUse goes to the debug log.
- Hooks start in the session's current folder, so `settings.json` runs each one as
  `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<name>.sh"` with a `timeout`, and `lib.sh` anchors to
  `$CLAUDE_PROJECT_DIR`.
- Hooks on one event run in parallel. Format and lint run in one script (`post-edit.sh`) so they
  cannot race on the same file.
- SessionStart and UserPromptSubmit hooks end in `|| true`: an exit 2 there would erase the user's
  prompt.
- No hook opens a network connection or installs anything. They run git, python3, jq, standard
  Unix tools and the project's own formatters and linters, nothing else.
- Installed as a plugin (Claude Code sets `CLAUDE_PLUGIN_ROOT`), every hook exits 0 at once, before
  reading its input, in a project that has neither `.claude/agent-config.json` nor
  `.claude/agent-config-kit.lock`. Either file opts the project in, and the opt-in sticks: the
  plugin records the project in `$CLAUDE_PLUGIN_DATA/opted-in-projects`, so when both files are
  gone later the hooks say so on stderr and keep guarding. To stop them, disable the plugin for the
  project or delete its line from that record yourself. Copied into a repo as files, the hooks
  always run.

## Fail modes

Only exit 2 stops a PreToolUse call: a crash, exit 1 or Claude Code's own timeout lets it through.
So each hook's choice is explicit, and `scripts/check/hook-probes.sh` proves every cell below.

| Hook | Kind | Payload not one JSON object | python3 missing | jq missing | python3 broken or hanging |
| --- | --- | --- | --- | --- | --- |
| `safety-check.sh` | guard | refuse | plain-text rules (see below) | full analyzer | refuse |
| `mcp-guard.sh` | guard | refuse | works (jq) | works | works (jq) |
| `generated-guard.sh` | guard | refuse | works, but `replace_in_files` is refused | works | as python3 missing |
| `migration-guard.sh` | guard | refuse | works, but `replace_in_files` is refused | works | as python3 missing |
| `db-guard.sh` | guard | refuse | its SQL tool refused, reads included; any other tool passes (jq) | works | as python3 missing |
| `post-edit.sh` | feedback | silent | no JSON validity note | works | silent where python3 was needed |
| `post-commit.sh` | feedback | silent | silent | works | silent |
| `prompt-intent.sh` | feedback | silent | silent | works | silent |
| `session-start.sh` | feedback | works (reads no payload) | works | works | works |

- **Refuse** means exit 2 with a reason, what to fix, and how to turn the guard off: the user
  removes its entry from `.claude/settings.json` (or disables the plugin that installs it). Without
  either python3 or jq, every guard but `safety-check.sh` refuses; that one judges the raw payload
  with its plain-text rules.
- **Hanging** is bounded by the hooks' own timers, well inside the 10 s hook timeout: 3 s for a
  quick python3 read, 5 s for the `replace_in_files` scope check, 8 s for the command analyzer.
  Where the machine has no `timeout` command (macOS), `lib.sh` stops the process itself.
- **Slow** is bounded too: each guard has one deadline for its whole run, 9 s. Every capped step
  gets at most what is left of it, and a guard still running when it passes refuses the call and
  says it ran out of time, so steps that each keep to their own cap never add up past the timeout,
  which would let the call through.
- **A symlink** a file guard is asked to write is judged as named and as the file it points to (a
  dangling link too), followed with `realpath`, `readlink` or python3. With none of them it is
  refused.
- A project folder that cannot be entered makes a guard refuse and a feedback hook stay silent.
- A malformed `.claude/agent-config.json` is not a failure: the defaults apply and Claude is warned.

## The hooks

Every repo ships these:

- `lib.sh`, sourced by the others: shared helpers, the config loader and the shell-command
  analyzer.
- `safety-check.sh`, PreToolUse on `Bash`: refuses destructive and irreversible commands (next
  section).
- `mcp-guard.sh`, PreToolUse on the GitHub MCP writes: refuses `push_files`,
  `create_or_update_file`, `delete_file` and `create_branch` onto a protected branch.
- `db-guard.sh`, PreToolUse on the production SQL tool (`mcp__db-prod__execute_sql`): lets one
  read-only statement through (`SELECT`, `SHOW`, `VALUES`, `TABLE`, `EXPLAIN`, `WITH ... SELECT`)
  and holds everything else until the user unlocks `db` (`docs/unlock.md`). Several statements, a
  comment that could hide one, quoting databases read differently (a backslash included) and SQL
  it cannot parse count as writes. It gates a server that accepts writes; the template's starts
  read-only (`--access-mode=restricted`), which also stops a function of your own that writes
  behind a `SELECT`. The plugin wires it on every MCP tool: a call to any other tool passes before
  python3 is needed (jq reads the name, bash matches it).
- `post-commit.sh`, PostToolUse on `Bash`: shows what a commit carried, and warns when it holds
  paths its pathspec did not name (sessions sharing a checkout share one git index).
- `post-edit.sh`, PostToolUse on the write tools: formats, then lints, the file just written, with
  the project's own tools.
- `prompt-intent.sh`, UserPromptSubmit: points a `/debug` shorthand at this repo's `/rca` command
  when it has one, and prunes the state of sessions idle for two days.
- `session-start.sh`, SessionStart: makes the zsh that runs Claude's commands behave like bash on
  unmatched globs, `=word` and word splitting.

Optional, shipped where they apply:

- `generated-guard.sh`, PreToolUse on the write tools: refuses hand edits to generated output
  (`generatedPaths`), a symlink that points into it included. Frontends and docs sites.
- `migration-guard.sh`, PreToolUse on the write tools: refuses hand edits to generated migrations
  (`migrationsDirs`), for drizzle-kit and Alembic. Backends and data pipelines that own a schema.
  A folder the repo does not have guards nothing.

The write tools are `Write`, `Edit`, `MultiEdit` and Serena's `replace_content`,
`replace_symbol_body`, `insert_after_symbol`, `insert_before_symbol`, `replace_in_files`,
`rename_symbol` and `safe_delete_symbol`. The file hooks resolve Serena's `relative_path`, and
check a folder-wide `replace_in_files` against every file it would reach.

An optional hook is wired with one more PreToolUse entry. Wire only the hooks this repo ships:
`scripts/check/ai-config.sh` fails on a hook command whose file is missing.

```json
{
  "matcher": "Write|Edit|MultiEdit|mcp__serena__(replace_content|replace_symbol_body|insert_after_symbol|insert_before_symbol|replace_in_files|rename_symbol|safe_delete_symbol)",
  "hooks": [
    {
      "type": "command",
      "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/generated-guard.sh\"",
      "timeout": 10
    }
  ]
}
```

## What `safety-check.sh` refuses

- **Recursive delete** (`rm -r`) of a protected path, the repo, a parent folder or the home folder,
  and `rm`, `rmdir`, `unlink` or `shred` fed by `xargs`: it deletes work git may not hold. Use
  `git rm -r <path>`. A throwaway named `zz-*`, `*-probe` or `__probe*`, or ignored by git, that
  holds nothing git tracks stays deletable, and so does anything in a temp folder.
- **`find` that deletes** (`-delete`, `-exec rm`) outside a temp folder: the paths it removes are
  never shown. Print the list with `-print`, check it, then delete named paths.
- **Commands that wipe uncommitted work**, another session's included: a hard reset
  (`reset --hard`), `clean -f` without a pathspec or on a protected one, `checkout .` or
  `checkout -f`, `restore .`, `stash` without a pathspec, `stash clear`. Name the paths you own:
  `stash push -- <paths>`, `checkout -- <file>`.
- **Skipping the pre-commit gate**: `--no-verify`, `commit -n`, `HUSKY=0`, `SKIP=` on a commit, or
  `core.hooksPath` pointed anywhere but the hooks git already uses. Fix what the gate reports.
- **A push to, or the deletion of, a protected branch**, by refspec, by `--all` or `--mirror`, or
  by the checked-out branch when no destination is named; `branch -d`, `update-ref -d` and
  `gh api -X DELETE` on its ref. Protected branches change through pull requests: push a work
  branch and open one. The user runs a release push with `!`.
- **`gh pr merge --delete-branch`**: it deletes the PR's head branch, which can be a protected one.
  Merge, then delete the work branch by name.
- **Any shell read or write of a real `.env*` file** or of `set.sh`'s backups: `cat`, `grep`,
  `sed`, `diff`, `source`, redirects, copies, globs such as `.env*`, a recursive `grep` or
  `rg --hidden` that reaches one, `python -c`, `node -e` or a heredoc that opens one, and inline
  code that prints what a loader took from one (`bun -e 'console.log(process.env)'`, `dotenv
  list`). Secret values stay out of the transcript. List a file with
  `bash scripts/env/show.sh <file>` (secrets masked); change a value with `scripts/env/set.sh`,
  which runs only while the user has unlocked `env`. Templates (`*.example`) stay open.
- **The unlock, from the agent**: running `scripts/ops/unlock.sh` or the `unlock` package script
  directly, through a shell, `source`, stdin, a copy or link, a glob, a known wrapper (below), a
  package runner, a git alias or `find -exec`; running a script whose file the analyzer cannot
  name; and writing, linking, moving or deleting anything in `.claude/state/unlock/`. Only the user
  unlocks, with `!` (`docs/unlock.md`). The routes the analyzer does not see are listed under
  "What it does not catch".
- **Changing `scripts/env/` or `unlock.sh` from the shell**: they may be read (`cat`, `grep`,
  `git diff`, `shellcheck`) and copied out, not edited, replaced, moved or deleted. The Edit tool
  asks the user first.
- **Changing the files that turn the guards on from the shell**: `.claude/settings.json`,
  `.claude/settings.local.json`, `.claude/agent-config.json` and `.claude/agent-config-kit.lock`,
  in this repo or any other checkout, and under the plugin its record of the projects that opted
  in. The shell may read them (`cat`, `grep`, `jq`, `git diff`), copy them out and stage them; it
  may not delete, move, link, overwrite, truncate or edit them in place, by any route the analyzer
  can follow. Change them with the Edit tool, which asks first. A fixture under a temp folder is
  not one of them.
- **Git settings that change what git runs, which config it loads, where it connects or where it
  works**, whatever their value: `-c`, `--config-env`, `GIT_CONFIG_PARAMETERS` or
  `GIT_CONFIG_KEY_n` setting an alias (`alias.*`), an include (`include.path`,
  `includeIf.*.path`), a command (`core.sshCommand`, `core.fsmonitor`, an editor or pager that is
  a command, `credential.*helper`, `diff.external`, filter, merge and tool drivers,
  `gpg.program`, ...), `protocol.*.allow`, an http(s) proxy, `sslVerify` or extra header,
  `url.*.insteadOf`, `safe.directory`, `core.worktree`, `init.templateDir` or
  `submodule.*.update`; and the same keys written with `git config` (or a section renamed with
  `--rename-section`). Plain settings stay open (`user.*`, `color.*`, `core.quotepath`,
  `init.defaultBranch`), and so do a pager or editor that is a plain viewer (`less`, `cat`,
  `more`, `true`), `core.fsmonitor=false`, and config reads. `core.hooksPath` follows the
  pre-commit gate rule above.
- **`alembic downgrade`**, only where `alembic.ini` exists: it drops columns and the data in them.
  Write a new forward revision.

The analyzer reads a command the way a shell does: quotes, `$'...'`, heredocs, `$( )`, backticks,
process substitution, `bash -c`, `eval`, aliases, loop variables, exported variables, `pushd`, and
text piped into a shell. Nesting deeper than six levels is refused rather than half read.

- **Wrappers are peeled** and the command they run is judged: `env` (`-S` included), `command`,
  `builtin`, `exec`, `nohup`, `time`, `sudo`, `doas`, `nice`, `ionice`, `timeout` and
  `gtimeout`, `stdbuf`, `setsid`, `arch`, `xcrun`, `unbuffer`, `chronic`, `caffeinate` and
  `xargs`. Add your own with `commandWrappers`.
- **Package runners are wrappers too**: `npm`, `pnpm`, `yarn` and `bun` `exec`, `dlx` and `x`,
  `npx`, `bunx` and `pnpx`. Their command is judged as a command, and the text they run as shell
  code (a `-c`, `--call` or `--shell-mode` string, the words of `bun exec` and `yarn exec`, which
  join them into one script) is judged as a script. A command name or shell text built from
  `$( )` or a variable it cannot resolve is refused. A `package.json` script is read before it
  runs.
- A temp folder (`/tmp`, `$TMPDIR`) outside the repo holds fixtures: the delete, `find`,
  work-wiping and gate-skipping git rules are relaxed there. Pushes, branch deletion, the git
  settings, the `.env*` and unlock rules and the `gh` rules apply everywhere.

**It fails closed on what it cannot read.** A payload that is not a JSON object is refused, and so
is every command when python3 is present but the analyzer crashes or runs past 8 s, or when the
guard reaches its 9 s deadline. A command it
cannot resolve is refused rather than guessed: a command name built by `$( )`, a file operand of a
reader it cannot name, decoded or computed code run by a shell or `eval`, code a shell or
interpreter reads from a pipe it cannot read, a script it cannot name, inline interpreter code that
opens a file, and the package-runner and git-setting forms above. Each refusal says why; when the
command is really meant, the user runs it with `!`, which runs as the user, outside the hooks and
the sandbox, with the user's own access (see "The sandbox layer" for the one exception).

**Without python3** only plain-text rules stand in, and Claude is told so when jq is there to say
it: pushes to protected branches; recursive deletes of protected paths, the repo, a parent or the
home folder; a hard reset, a forced `clean`, `--no-verify` and `HUSKY=0`; any real `.env*` name
(reads, writes, copies and `source` alike); the unlock script, its package alias or its folder;
any mention of `scripts/env/`; and any mention of a file that turns the guards on. Everything else,
a wrapper or package runner around any other command included, runs unchecked on such a machine:
install python3. The analyzer keeps the same rules for a command it cannot tokenise even after
closing a stray quote.

### What it does not catch

The hooks read command text before it runs. They are a guardrail against slips and against
instructions hidden in files Claude reads, not a security boundary:

- **Code in files is run, not read.** A script Claude writes and then runs, a Makefile target, a
  test, a build or framework config, a git hook: the analyzer judges the command line, never the
  file's contents. The same holds for settings git reads from a config file Claude wrote with a
  file tool.
- **Programs that run commands of their own** are judged by name only unless listed above: `watch`,
  `script`, `flock`, `parallel`, `ssh` to this machine, an editor, a task runner reading its
  own file. Add a wrapper you use to `commandWrappers`.
- **The app reads `.env*` when it runs.** A server, test run or build loads the values it needs;
  the hooks refuse the obvious ways to print them, but a program's own output can still show one.
- **The hooks are files in the repo.** A change to them changes what they refuse; review changes
  under `.claude/` like any other code.
- **Without python3** only the plain-text rules above run.

The sandbox below closes the gaps that matter most (reading `.env*`, forging an unlock) for every
process, whatever the command line says.

### The sandbox layer

`.claude/settings.json` turns on Claude Code's Bash sandbox
([docs](https://code.claude.com/docs/en/sandboxing)) by default (`sandbox.enabled: true`). The
operating system then enforces, for every command Claude runs and its child processes: no read of a
real `.env*` file or of `set.sh`'s backups (`sandbox.filesystem.denyRead`, with `allowRead`
re-opening the `*.example` templates), and no write under `.claude/state/unlock/`
(`sandbox.filesystem.denyWrite`). Only `scripts/env/show.sh` and `scripts/env/set.sh` run outside it
(`sandbox.excludedCommands`).

- **Platforms**: macOS (built in), Linux and WSL2 (with `bubblewrap` and `socat` installed). Not
  WSL1 or native Windows. Where it cannot start, Claude Code warns and runs commands without it
  unless `sandbox.failIfUnavailable` is `true`; the hooks apply either way.
- **Escape hatch**: a command that fails inside the sandbox may be retried outside it, through the
  normal permission prompt. Set `sandbox.allowUnsandboxedCommands` to `false` to forbid that.
- **`!` commands** the user types run outside the sandbox, except in a background session under
  strict mode (`allowUnsandboxedCommands: false`) and on Linux with
  `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` set, where they are sandboxed too. There, run `unlock` in your
  own terminal: the sandbox refuses the user's write to `.claude/state/unlock/` as well.
- **Turn it off** with `"sandbox": {"enabled": false}` in `.claude/settings.json` (or
  `settings.local.json`); the hooks keep running.

**No hook reads permission from the prompt.** A refused command stays refused whoever asks; the
user runs it themselves with `!`. Never widen `settings.json` or `agent-config.json` to get past a
refusal.

## Configuration

`.claude/agent-config.json` is optional in a repo that carries the hooks as files;
`.claude/agent-config.example.json` documents every key with its default. A key you set replaces
its default whole; a broken file or key falls back to the defaults, and Claude is warned. Under the
plugin, the file (even `{}`) or `.claude/agent-config-kit.lock` is also what turns the hooks on for
the project, and once on they stay on (see the contract above).

- `protectedBranches` (`safety-check.sh`, `mcp-guard.sh`): `dev`, `prod`, `main`, `master`.
- `protectedPaths` (`safety-check.sh`): `src`, `app`, `components`, `content`, `tests`, `scripts`,
  `.claude`, `.agent`, `.agents`, `_workflow-source`, `.github`, `.git`, `AGENTS.md`, `SSOT.md`,
  `CLAUDE.md`, `PRODUCT.md`, `DESIGN.md`.
- `generatedPaths` (`generated-guard.sh`): `src/lib/api/generated`, `src/generated`, and
  `openapi.json`, `openapi.yaml`, `openapi.yml`.
- `migrationsDirs` (`migration-guard.sh`): `src/db/migrations`, `drizzle`,
  `src/app/db/migrations/versions`, `alembic/versions`, `migrations/versions`.
- `commandWrappers` (`safety-check.sh`): none beyond the built-in wrappers and package runners.
- `localePairs` (`post-edit.sh`): none, so the check is off.
- `dbWriteGuard` (`db-guard.sh`): an object; `toolPattern` is a regex matched against the whole
  tool name, default `mcp__db-prod__execute_sql`. Keep the hook's matcher in `settings.json`
  covering it.

Environment variables, all optional:

- `AGENT_WORKSPACE_ROOT`: multi-repo mode, off when unset. It names a folder holding several repos
  (up to two levels below it). Sibling repos there are protected like this one, a session opened at
  that folder follows each file's own repo, and Serena paths relative to it resolve.
- `AGENT_HOOK_STATE_DIR`: where the per-session state lives, the HEAD each commit started from,
  which `post-commit.sh` reads. Default: `$CLAUDE_PLUGIN_DATA/hook-state` under the plugin,
  `$TMPDIR/claude-hook-state` otherwise.

Set by Claude Code, read only: `CLAUDE_PROJECT_DIR` (the project the hooks anchor to),
`CLAUDE_PLUGIN_ROOT` (plugin mode, which turns on the project gate) and `CLAUDE_PLUGIN_DATA`.

## Requirements

- bash 3.2 or newer (macOS `/bin/bash` included) and git.
- python3 3.8 or newer: the command analyzer, the config loader, the Serena scope checks and
  `db-guard.sh`.
  Without it only the plain-text rules above run (see Fail modes).
- jq is optional: faster payload reads, and the payload and config reader when python3 is missing.
- `realpath` or `readlink` (both standard on macOS and Linux) let the file guards follow a
  symlink without python3.
- Formatters and linters are the project's own, found in `node_modules/.bin`, `.venv/bin` or
  `PATH`: `oxfmt` and `oxlint` for TypeScript, JavaScript, JSON, CSS and Markdown; `ruff` for
  Python. A tool the project lacks is skipped. A hook never downloads a package.

## Changing a hook

1. Change the script, then add a probe it must stop and one it must let through
   (`scripts/check/hook-probes.tsv` for `safety-check.sh`, `scripts/check/hook-probes.sh` for the
   others).
2. Run `bash scripts/check/hook-probes.sh` (on macOS, `/bin/bash scripts/check/hook-probes.sh`
   proves bash 3.2). A syntax error in `lib.sh` exits 2 and blocks every tool call, so the harness
   runs `bash -n` on every hook first. Keep `shellcheck -x -S style .claude/hooks/*.sh` clean.
3. Prove the new probe is load-bearing: disable the rule, watch the probe fail, restore it.

`HOOKS_DIR` and `PROBES_FILE` point the harness at another hooks folder or probe table. Hooks the
folder does not ship are skipped; `safety-check.sh` is required. Besides the rules, the harness
proves the Fail modes table, a linked git worktree judged exactly like its main checkout, and the
plugin-mode project gate. `HOOK_PROBE_CRASH`, `HOOK_PROBE_NO_TEMP` and `HOOK_PROBE_CAP` exist for
it alone, and each can only make a hook stricter.
