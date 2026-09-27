# Serena — Shared Multi-Repo Workspace Scoping

> **List it in the CLAUDE.md "On-demand References" table; never `@`-import it.** An import loads
> the whole file into every session. This is a template, only relevant if you run several repos
> side by side and want one Serena project to span them: copy it to `.claude/SERENA-WORKSPACE.md`
> and fill every `<placeholder>`. With a single repo, delete this file and its table row — the
> default single-repo behaviour needs no documentation.

## What this is

On a machine configured for it, opening a session in any of your repos activates a **single shared
Serena project** covering `<N>` repos at once. Symbol tools — `find_symbol`,
`find_referencing_symbols`, `find_declaration`, `find_implementations` — then search all of them.

## This is machine-local configuration, not repo configuration

The shared workspace is enabled by two files that are **not in git** and belong to no repo:

- `~/.claude.json` — a local-scope MCP override per repo path, pointing Serena's `--project` at the
  workspace root instead of `.`
- `<workspace-root>/.serena/project.yml` — the project name, with each repo listed under
  `ls_workspace_folders`

The `.mcp.json` committed in every repo specifies `--project .`. **A fresh clone therefore gets a
single-repo Serena, not the shared workspace.**

> Do not "fix" `.mcp.json` by hard-coding the workspace path. It embeds one machine's absolute paths
> and assumes a specific parent-directory layout, which breaks Serena for everyone else who clones
> the repo. The split — committed default, machine-local override — is the point.

## Check which mode you are in, before your first path-scoped call

Serena reports the active project in an `<active-project>` block.

**Where that block appears depends on tool search.** With `ENABLE_TOOL_SEARCH: "true"` in
`.mcp.json`, Serena's tools *and* its instructions are deferred — the session system prompt carries
only a stub, and `<active-project>` arrives in the `initial_instructions` response instead.
Confirming the mode therefore costs exactly one call, which the session owes anyway.

| Active project          | `relative_path` resolves against | Prefix to use                       |
| ----------------------- | -------------------------------- | ----------------------------------- |
| the workspace's name    | the workspace root               | `<path-to-repo>/...`                |
| anything else           | the repo you opened              | none — plain repo-relative (`src/`) |

Getting this wrong fails **loudly** — Serena raises rather than returning an empty result, so a
prefix mistake can never be mistaken for "the symbol does not exist":

| Wrong `relative_path`             | What you get                                                        |
| --------------------------------- | ------------------------------------------------------------------- |
| repo prefix omitted               | `FileNotFoundError: <workspace-root>/src`                           |
| part of the repo path omitted     | `FileNotFoundError: <workspace-root>/<repo>/src`                    |
| a path outside every workspace    | `ValueError: ... outside of configured workspaces` — **and it lists every valid workspace** |

That last error is self-documenting: it prints the configured roots, which is the fastest way to
recover the correct prefix.

## Default to narrow

Workspace-wide search costs more tokens per query and returns cross-repo matches you usually did not
ask for. **Pass `relative_path` to scope every search you can.** Widen only for genuine cross-repo
reach — tracing a contract shared between a backend and its frontends, or auditing every consumer
of a pattern.

```jsonc
/* narrow — one repo, shared workspace active */
{ "name_path_pattern": "Foo", "relative_path": "<path-to-repo>" }

/* narrow — shared workspace NOT active, session opened in that repo */
{ "name_path_pattern": "Foo", "relative_path": "src" }

/* wide — deliberate cross-repo reach; omit relative_path */
{ "name_path_pattern": "Foo" }
```

## Known limitation — generated clients are invisible

If the workspace sets `ignore_all_files_in_gitignore: true` and your generated API client is
gitignored, **Serena cannot see it.** Symbol searches for generated hooks or types return nothing
even though the code exists on disk.

This is the one case where an empty result does not mean "absent from the scope you searched" —
the files are filtered out before the search rather than rejected by it. Use the committed API spec
instead, and read generated files with the built-in file tool if you must inspect the output.

> Disabling `ignore_all_files_in_gitignore` looks like the obvious fix and is not: it also exposes
> every `.env` file across every repo in the workspace to symbol search and file reads.
