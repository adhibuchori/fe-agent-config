# Postgres — MCP Access for Debugging

> **List it in the CLAUDE.md "On-demand References" table; never `@`-import it.** An import loads
> the whole file into every session. This is a template: copy it to `.claude/DATABASE.md` and fill
> every `<placeholder>` before the `db-dev` / `db-prod` MCP servers in `.mcp.json` will connect. A
> project with no database deletes both servers from `.mcp.json` and skips this file.
>
> This file is **operational rules, not neutral reference.** It is the only place that says which
> production operations are allowed, so treat an edit to it the way you would treat an edit to a
> firewall rule.

Access is through the `db-dev` and `db-prod` MCP servers
([Postgres MCP Pro](https://github.com/crystaldba/postgres-mcp)), pinned in `.mcp.json`.

## Topology

|             | Instance name     | Port                 | Identifier           |
| ----------- | ----------------- | -------------------- | -------------------- |
| Development | `<dev-instance>`  | **`<dev-db-port>`**  | `<dev-instance-id>`  |
| Production  | `<prod-instance>` | **`<prod-db-port>`** | `<prod-instance-id>` |

If both instances hold the same database names and differ only by port, say so here. That single
sentence is what stops someone reading a table name and assuming they are on dev.

| Database          | Owner role     | Extensions            | Used by repo |
| ----------------- | -------------- | --------------------- | ------------ |
| `<database-name>` | `<owner-role>` | `<e.g. vector, none>` | `<repo>`     |

When more than one repo uses a database with different roles (a writer and a reader, say), name
both and say which is which; that distinction is easy to get backwards from inside one repo.

## Tunnel must be up first

Reach Postgres through a tunnel on `127.0.0.1`, never through the host's public address. The MCP
server reads its connection URI **at startup**, so the tunnel has to be running **before** the
agent session opens:

```bash
ssh -L <dev-db-port>:127.0.0.1:<dev-db-port> \
    -L <prod-db-port>:127.0.0.1:<prod-db-port> \
    <ssh-host-alias> -N
```

The forward makes each remote port answer on localhost, so a GUI client and `psql` use the same
addresses the app does:

| Target        | Address with the tunnel up | Never use                      |
| ------------- | -------------------------- | ------------------------------ |
| Postgres dev  | `127.0.0.1:<dev-db-port>`  | `<public-host>:<dev-db-port>`  |
| Postgres prod | `127.0.0.1:<prod-db-port>` | `<public-host>:<prod-db-port>` |

A tunnel does not survive a network change: the SSH session dies with the old route and does not
reconnect. Restart it after switching networks; `ECONNREFUSED 127.0.0.1:<port>` from the app is
that, not a broken database. If the database runs in a container, a published port can bypass the
host firewall; see `.claude/OPERATIONS.md` § Container firewall trap.

## Choosing a database

Each MCP server connects to **one** database, fixed by `DB_DEV_URI` / `DB_PROD_URI` in your shell
profile and read at startup. Changing the database means editing the variable and **restarting the
session**; the server does not reread its environment while running.

```
postgresql://<mcp-role>:<password>@127.0.0.1:<dev-db-port>/<database-name>
```

## The role the agent connects as

Create a dedicated role. Do **not** reuse the provisioning superuser, however convenient.

Grant it what debugging needs: `SELECT` on the application schema, read access to the migration
bookkeeping schema, and statistics reads (`pg_read_all_stats`) for the database-health tools. Set
`ALTER DEFAULT PRIVILEGES` under each owner role so tables created by future migrations are
reachable without re-granting.

What it must **not** be able to do: drop databases, manage roles, run DDL, or anything else that
needs superuser. Migrations run as the owner role, by a person, never through this role.

## Rules for the production server

Both servers ship with `--access-mode=restricted`: read-only transactions and bounded execution
time. The server name, which appears in every tool call, is the other half of the distinction:

- `mcp__db-dev__*` — free to use. To let the agent write to dev, change `db-dev` alone to
  `--access-mode=unrestricted` and grant the dev role write access on the application schema; the
  access mode alone adds no privilege the role lacks.
- `mcp__db-prod__*` — stays restricted. `mcp__db-prod__execute_sql` is also an **`ask`** rule in
  `.claude/settings.json`, so every query prompts first. Never add it to `permissions.allow`.
  `.claude/hooks/db-guard.sh` also checks each call: one read-only statement passes, anything else
  waits for the user's `unlock db` (`docs/unlock.md`). While the server is restricted that unlock
  opens nothing; it matters only in a repo that deliberately gives `db-prod` write access for
  incidents, where it becomes the gate.

`bypassPermissions` mode skips `ask` rules, which is why restricted mode, not the prompt, is what
holds production read-only. MCP permissions live in `.claude/settings.json`; `.mcp.json` has no
permission field Claude Code reads.

- `explain_query` and `analyze_query_indexes` also run the SQL they are handed: `EXPLAIN ANALYZE` of
  a write, or a stacked statement, is a real run. A repo that makes `db-prod` writable for incidents
  widens `dbWriteGuard.toolPattern` in `.claude/agent-config.json` to those tools too, so `db-guard`
  judges them like `execute_sql`.
- A function of the app's own that writes reads like a query (`SELECT archive_old_rows()`), so no
  guard can tell it apart. Call one only while `unlock db` is open; otherwise hand the statement to
  the user.
- Write down the backup schedule and how many backups are kept, beside the topology above, so
  "check the latest backup" has something to check against.

A production write happens outside MCP, by a person, as the owner role, and only after confirming
the latest backup actually exists (through the backup tool or the deploy platform), rather than
assuming the schedule ran.

## Available tools

`list_schemas` · `list_objects` · `get_object_details` · `explain_query` (supports hypothetical
index simulation) · `get_top_queries` (requires `pg_stat_statements`) · `analyze_workload_indexes` ·
`analyze_query_indexes` · `analyze_db_health` (cache hit, vacuum, connections, replication, sequence
limits) · `execute_sql`.
