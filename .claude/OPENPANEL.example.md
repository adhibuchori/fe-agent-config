# Analytics — Read API Access

> **Template.** This documents a self-hosted analytics instance reached over its REST export API.
> Fill in every `<placeholder>`, rename to `ANALYTICS.md` (or your vendor's name), and import it
> from `CLAUDE.md`.
>
> Delete this file entirely if you have no analytics backend. An unfilled template is worse than an
> absent one — an agent will try to use it.

## Why a plain REST doc and not an MCP server

Worth recording, because it is the first question anyone asks.

If your self-hosted build ships no MCP endpoint, say so **and say how you know**. "Verified:
`/api/mcp`, `/api/sse`, `/api/v1/mcp` × GET/POST all return 404 from the app's own router" is a
finding. "There is no MCP endpoint" is a guess that someone will re-check in three months.

Third-party MCP bridges are a supply-chain decision, not a convenience decision. If you reject
them, write down that you did — otherwise the next person installs one.

## Base URL

```
<analytics-host>/api
```

Note whether the dashboard and the API sit behind different access controls. A dashboard behind
SSO whose `/api/*` deliberately bypasses it — because browser-side event tracking requires that —
is a security-relevant asymmetry worth one sentence here.

## Endpoints

| Endpoint             | Purpose                                            |
| -------------------- | -------------------------------------------------- |
| `GET /export/events` | Raw events — filtering, pagination                 |
| `GET /export/charts` | Aggregated time series — breakdown, segmentation   |

## Auth

Record the exact header shape. Guessing `Authorization: Bearer` when the service wants two custom
headers costs an hour.

```
<client-id-header>: <id>
<client-secret-header>: <secret>
```

Environment variables: `ANALYTICS_READ_CLIENT_ID`, `ANALYTICS_READ_CLIENT_SECRET`.

> **Client type matters.** A default per-project client is often write-only and will reject reads
> with a message that sounds like an auth failure but is not. If your vendor distinguishes read
> clients from write clients, say which one is needed and where to create it.

## Verified working example

Include one command that actually ran, with its actual response shape. This is the difference
between a doc that can be trusted and one that has to be re-derived.

```bash
curl -s \
  -H "<client-id-header>: $ANALYTICS_READ_CLIENT_ID" \
  -H "<client-secret-header>: $ANALYTICS_READ_CLIENT_SECRET" \
  "<analytics-host>/api/export/events?limit=2"
```

Returns `200` with `{"meta": {...}, "data": [...]}`. Omitting the headers returns `401`.
