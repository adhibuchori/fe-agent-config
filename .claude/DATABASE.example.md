# Postgres — MCP Access for Debugging

> **Template.** Fill in every `<placeholder>` before the `db-dev` / `db-prod` MCP servers in
> `.mcp.json` will connect. Then rename this file to `DATABASE.md` and import it from `CLAUDE.md`
> with a single `@.claude/DATABASE.md` line.
>
> This file is **operational rules, not neutral reference.** It is the only place that says which
> production operations are allowed, so treat edits to it the way you would treat edits to a
> firewall rule.

## Topology

|             | Instance name    | Port                | Identifier         |
| ----------- | ---------------- | ------------------- | ------------------ |
| Development | `<dev-instance>` | **`<dev-db-port>`** | `<dev-instance-id>` |
| Production  | `<prod-instance>` | **`<prod-db-port>`** | `<prod-instance-id>` |

If both instances hold the same database names and differ only by port, say so explicitly. That
single sentence is what stops someone reading a table name and assuming they are on dev.

| Database          | Owner role      | Used by repo |
| ----------------- | --------------- | ------------ |
| `<database-name>` | `<owner-role>`  | `<repo>`     |

## Tunnel must be up first

If the ports are open only on the host and not publicly, the MCP server reads its connection URI
**at startup** — so the tunnel has to be running **before** the agent session opens, not after.

```bash
ssh -L <dev-db-port>:127.0.0.1:<dev-db-port> \
    -L <prod-db-port>:127.0.0.1:<prod-db-port> \
    <user>@<vps-host> -N
```

## Choosing a database

Each MCP server connects to **one** database, fixed by an environment variable read at startup.
Changing the database means editing the variable and **restarting the session** — the server does
not reread its environment while running.

```
postgresql://<mcp-role>:<password>@localhost:<dev-db-port>/<database-name>
```

## The role the agent connects as

Create a dedicated role. Do **not** reuse the provisioning superuser, however convenient.

Grant it what debugging actually needs — `SELECT` on the application schema, read access to the
migration schema, and statistics reads if your tooling has a database-health check. Set
`ALTER DEFAULT PRIVILEGES` under each owner role so tables created by future migrations are
reachable without re-granting.

What it must **not** be able to do: drop databases, manage roles, or anything else requiring
superuser. Then the worst mistake is recoverable from the most recent backup — which is only true
if the backup exists, so verify that rather than assuming the schedule ran.

## Rules for the production server

Both servers are technically capable of writing. The only thing separating them is **the server
name, which appears in every tool call** — so make the distinction explicit here:

- `mcp__db-dev__*` — free to use. Dev exists to be experimented on.
- `mcp__db-prod__*` — read and diagnostic tools may be pre-approved. **`execute_sql` must not
  be**, so every write against production still raises a permission prompt.

> Do not add `execute_sql` to the production server's always-allow list. That confirmation prompt
> is the last safeguard before production data changes, and it is the kind of thing that gets
> removed on a busy day and never restored.

Before writing anything to production, confirm the latest backup actually exists.

## Maintenance note

If this file is duplicated across repos, they must stay byte-identical. Bring the file to your
formatter's fixpoint **first**, then propagate — otherwise the first repo that formats markdown
silently breaks the invariant for all the others.

```bash
shasum */*/.claude/DATABASE.md | awk '{print $1}' | sort -u | wc -l   # must print 1
```
