# Unlocking secrets and database writes

Two things are locked by default. Only you can open them, and each one closes again by itself
after a few minutes.

| Target | Locked by default                          | Opens for  | While open, Claude may                   |
| ------ | ------------------------------------------ | ---------- | ---------------------------------------- |
| `env`  | Changing `.env*` files                     | 20 minutes | change values with `scripts/env/set.sh`  |
| `db`   | SQL that writes to the production database | 15 minutes | run `INSERT`, `UPDATE`, `DELETE` and DDL |

`db` matters only when your production database server accepts writes. The template's server
starts read-only; "Which database setup `db` is for" below explains the choice.

Claude never sees the raw text of a `.env*` file. These stay allowed, locked or not:

- **Listing a `.env` file.** `bash scripts/env/show.sh .env.production` prints every key. Settings
  such as `PORT=3000` show in full; secrets show as their first four characters and their length
  (`sk_l…(51 chars)`), or only the length when they are short. It also lists keys that are
  missing compared with `.env.production.example`.
- **Reading the database.** One `SELECT`, `SHOW`, `VALUES`, `EXPLAIN` or `WITH … SELECT` statement.
- **Templates.** `.env.example` and `.env.<target>.example` hold no secrets; any command may read
  or edit them.

## The command

Run it yourself. In Claude Code, type `!` first, so the command runs as you, outside Claude.

| Your repo uses | Open `.env*`                    | Open DB writes                 |
| -------------- | ------------------------------- | ------------------------------ |
| bun            | `! bun unlock env`              | `! bun unlock db`              |
| npm            | `! npm run unlock env`          | `! npm run unlock db`          |
| pnpm           | `! pnpm unlock env`             | `! pnpm unlock db`             |
| yarn           | `! yarn unlock env`             | `! yarn unlock db`             |
| no Node        | `! ./scripts/ops/unlock.sh env` | `! ./scripts/ops/unlock.sh db` |

- The same command takes `status` (what is open, and until when) and `off` (lock everything now):
  `! bun unlock status`, `! bun unlock off`.
- Add minutes to choose how long: `bun unlock env 5`. Any whole number from 1 to 240 works.
- `off env` or `off db` locks one target and leaves the other open.
- The package manager forms need `"unlock": "bash scripts/ops/unlock.sh"` in `package.json`
  `scripts`. Repos without Node use the script directly. It needs only bash and python3.
- You can also run it in your own terminal, outside Claude Code.

## An example session

You ask Claude to rotate an API key in production:

```text
Claude:  API_KEY lives in .env.production. It is locked; please run: ! bun unlock env
You:     ! bun unlock env
         🔓 .env unlocked until 14:32 (20 min) — lock now: bun unlock off env
Claude:  printf '%s' "$NEW_KEY" | bash scripts/env/set.sh .env.production API_KEY
         ✓ API_KEY updated in .env.production: sk_l…(51 chars) · backup .claude/state/env-backups/…
You:     ! bun unlock off
         🔒 everything locked (env, db)
```

The same flow works for the database: Claude runs its reads, and when a write is needed it asks
you for `! bun unlock db` or hands you the statement to run yourself.

## Why `!`

Claude's commands pass through the repo's hooks first, and, where the sandbox runs, inside it. The
hooks refuse Claude running the unlock command or its `package.json` alias, and creating, copying,
linking or deleting the files that hold an unlock, by every route they can read ("What the lock
does not stop" lists the ones they cannot); the sandbox refuses any write to those files. A command
you start with `!` runs as you, with your own access, outside Claude's hooks and (in an ordinary
session) outside the sandbox, so it is the one way in. Asking in the chat does not unlock anything.

## What is locked, exactly

- **`.env*` files.** Claude's own file tools may not open or edit them (the repo's
  `.claude/settings.json` denies `Read(.env*)` and `Edit(.env*)`, templates excepted). The hooks
  refuse the shell commands that read or write one: `cat`, `grep`, `sed`, `diff`, `source`,
  redirects, copies, a `python -c` or `node -e` that opens one, and the same inside a wrapper
  (`timeout`, `sudo`, `env`, ...) or a package runner (`npx`, `bun exec`, `pnpm exec`, ...). A
  recursive `grep` over a folder that holds one is refused unless it leaves `.env*` out
  (`--exclude='.env*'`). So is inline code that prints what a loader took from one, such as
  `bun -e 'console.log(process.env)'` (bun loads `.env` by itself) or `dotenv list`.
- **Anything the analyzer cannot resolve is refused (fail-closed).** When it cannot tell what a
  command touches, it blocks with the reason and the hint to run it yourself with `!` if it is
  meant. These forms are refused whether or not they name `.env` or the token in plain text:
  computed or decoded code (`eval`, sourcing computed text, a base64/xxd payload decoded and then
  run or read, and code a shell or interpreter reads from stdin out of something it cannot read,
  such as `cat notes.txt | sh`, `curl … | bash` or `bash < <(…)`); a command that git or a pager
  runs from a setting or variable (`git -c core.pager=…`, `core.fsmonitor`, `diff.external`,
  `git config core.sshCommand …`, `GIT_PAGER`, `EDITOR`, …), which is checked as the command it is
  and refused when its value cannot be read; a command or process substitution used as the
  command name or as a file operand of a reader/writer (only a literal `git ls-files <pathspec>` or
  `git diff --name-only`, with no option before the subcommand, whose pathspecs cannot match
  `.env*` is allowed, so `cat $(git ls-files '*.md')` still works); a path built through `IFS`,
  `shopt -s dotglob`, an array or a `printf` substitution; a package runner whose command or
  shell text is built from `$( )` or an unknown variable (`npx`, `bunx`, `npm/pnpm/yarn/bun exec`,
  `dlx`; their `-c` strings and the scripts `bun exec` and `yarn exec` run are checked like
  `bash -c`), a build tool reading its recipe from stdin (`make -f /dev/stdin`, `just`, `task`);
  a git setting that changes what git runs or loads (an alias, an include, `core.sshCommand`,
  `core.fsmonitor`, a credential helper, `protocol.*.allow`, a proxy, `url.*.insteadOf`, ...),
  set with `-c` or written with `git config`, whatever its value; inline interpreter
  code that opens, lists or builds a path to a file; a copy, move, link or archive landing on
  `.claude/state/` or a `.env*` file; and `xargs` feeding a file reader from a pipeline. Over-
  refusal is the point: when in doubt it stops and hands the command to you.
- **The two helper scripts** are the exceptions: `show.sh` always, and `set.sh` only while `env` is
  open. `set.sh` keeps every other line and comment, backs the old file up to
  `.claude/state/env-backups/` (the backups are locked like the files) and logs the key name,
  never the value. Claude's shell may read `scripts/env/` but not change it; a change to it goes
  through the Edit tool, which asks you first.
- **Production writes.** `.claude/hooks/db-guard.sh` checks each call to the production SQL tool
  (`mcp__db-prod__execute_sql`, or `dbWriteGuard.toolPattern` in `.claude/agent-config.json`).
  Anything but one read-only statement waits for `db`: a write, several statements, `SET ROLE`,
  a comment that could hide a statement, a string a backslash could split differently, or SQL it
  cannot parse.
- **Which database setup `db` is for.** The template's production server starts read-only
  (`--access-mode=restricted` in `.mcp.json`), so the server itself refuses every write and
  `unlock db` changes nothing. Keep it that way unless you want Claude able to fix production data
  during an incident. If you do, give that server write access; from then on `db-guard.sh` holds
  every write until you run `unlock db`.

## How it works

`unlock env` writes `.claude/state/unlock/env` holding the time the unlock ends. The folder is
private to you (0700) and each file 0600. The hooks and scripts accept only a file written that
way: an expired file, one that is readable by others, a link, or one git tracks counts as locked.
`status` and every other run remove expired files. `off` deletes them.

Add `.claude/state/` to `.gitignore`. It holds the unlock files, the backups (which contain
secrets) and the audit log. `set.sh` refuses to run until it is ignored.

## What the lock does not stop

The hooks read each command before it runs. They are a guardrail against slips and against
instructions hidden in files Claude reads. They refuse what they cannot resolve rather than guess,
but they read text, so honest limits remain:

- **The application reads `.env` when it runs.** A program that loads `.env` itself — bun, Next.js,
  dotenv, `docker --env-file`, `--env-file` — sees the values, and that is expected: the app needs
  them. The hooks refuse the obvious ways to *print* them (see above), but a build log or a server's
  own output could still surface a value. This is a property of running the app, not something a
  command guard removes.
- **Programs the hooks do not know run commands of their own.** Known wrappers and package runners
  are unwrapped; `watch`, `script`, `flock`, `parallel`, an editor, or a task runner reading its
  own file are judged by name only. The repo can list more wrappers in `commandWrappers`.
- **Without python3** the hooks fall back to a few plain-text rules (`.claude/hooks/README.md`,
  "Fail modes"); a `.env*` name, the unlock script or its folder, and `scripts/env/` stay refused
  there, most other checks do not run.
- **A script file Claude writes and then runs is executed, not read.** The hooks check the command
  line, so `bash ./my-script.sh` runs whatever that file contains; they do not open and parse the
  script. Computed and hidden *command lines* are refused (see the fail-closed list above), but a
  named script's contents are the code's own review surface. The same holds for a config file
  Claude writes and git then reads (`.git/config`, an `include.path` file): its settings are
  not parsed.
- **The hooks are files in the repo.** Claude's Bash could change them, and a change there would
  change what they refuse. `.claude/settings.json` asks before `Edit(scripts/env/**)` and the
  unlock script, and the analyzer refuses shell changes to the helper files and to the files that
  turn the guards on (`.claude/settings.json`, `settings.local.json`, `agent-config.json`,
  `agent-config-kit.lock`); still, review changes under `.claude/` like any other code.
- **A write-enabled production server** turns a SQL function of your own that writes into something
  that reads like a query, so it can pass without `unlock db`. The read-only server mode
  (`--access-mode=restricted`) is the layer below that stops it.

## The sandbox layer

For a boundary the operating system enforces against any process, not just the command lines the
hooks read, `.claude/settings.json` turns on
[Claude Code's Bash sandbox](https://code.claude.com/docs/en/sandboxing). Its default block:

- **`sandbox.filesystem.denyRead`** blocks sandboxed commands from reading `.env*` files (`.envrc`
  included, at any depth) and the backups in `.claude/state/env-backups/`, with `allowRead`
  re-opening `*.example` templates only.
- **`sandbox.filesystem.denyWrite`** blocks writes under `.claude/state/unlock/`, so no sandboxed
  command can forge a token even by a route the analyzer never saw.
- **`sandbox.excludedCommands`** excludes only `scripts/env/show.sh` and `scripts/env/set.sh`, the
  two helpers that must reach `.env` files; everything else runs inside the boundary.

Because the deny is enforced by the OS for every sandboxed command and its children, it holds even
where the text-based analyzer cannot. It is on by default (`"sandbox": {"enabled": true}`), and
its limits are these:

- **Platforms.** macOS needs nothing; Linux and WSL2 need `bubblewrap` and `socat`. WSL1 and native
  Windows are not supported. Where the sandbox cannot start, Claude Code warns and runs commands
  without it (unless `sandbox.failIfUnavailable` is `true`); the hooks still apply.
- **The retry outside it.** A command that fails inside the sandbox can be retried outside it, and
  that retry goes through Claude Code's normal permission prompt. The app itself, which must read
  `.env`, runs that way. Set `sandbox.allowUnsandboxedCommands` to `false` to forbid the retry.
- **Your `!` commands** run outside the sandbox, except in a background session with
  `allowUnsandboxedCommands: false` and on Linux with `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` set. There
  the sandbox also refuses your own write to `.claude/state/unlock/`: run `unlock` in your own
  terminal instead.
- **Turning it off.** Set `"sandbox": {"enabled": false}` in `.claude/settings.json` (or in your
  `.claude/settings.local.json`). The hooks keep running.
