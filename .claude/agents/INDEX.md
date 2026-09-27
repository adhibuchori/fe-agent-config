# Agents Index

Subagents live in `.claude/agents/`, and that folder is the authoritative list. This table is where
people and commands read each one's scope in a line. Add a row when you add a file.

| Agent                   | Use it for                                     | Checks                                                                                           |
| ----------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `agents-reviewer`       | Changed components, hooks or lib code          | Logic-free components, hooks, styling, data layer, compiler, file length, Rules 30-34, JSDoc     |
| `agents-i18n-guard`     | A change to `src/messages/` or any `t()` call  | en↔id key parity, hardcoded strings, namespaced translators, locale navigation and formatting    |
| `agents-security-guard` | Config, route handlers, forms, rendered HTML   | Headers and CSP, secret and env exposure, XSS sinks, request trust, guard-file edits             |
| `agents-seo-validator`  | Metadata, public pages, robots, sitemap        | metadataBase, per-route metadata, canonical and hreflang, robots, sitemap, share images, JSON-LD |

Each one reads the uncommitted diff (`git diff` plus `git diff --staged`) and reports what it
finds; its instructions say to validate and flag, never to rewrite. No command calls them: ask for
one by name ("run agents-seo-validator"), or let Claude Code choose one whose description fits the
task. A subagent inherits the session's tools, so "reports only" is an instruction, not a
permission boundary.

Their human counterpart, for what no rule number covers, is `.claude/docs/code-review-checklist.md`.
