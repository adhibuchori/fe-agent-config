---
description: Summarises the session for a handover — what was done, what is pending, what comes next. Prints the summary; optionally writes a gitignored local log under .claude/session-logs/.
---

<!-- Command: /checkpoint-summary [domain] -->
<!-- Source: _workflow-source/checkpoint-summary.md -->
<!-- Run every 90 minutes or every 10 tasks -->

# /checkpoint-summary — Session Summary

Records **what happened**. For **what should change next time**, use `/learn-session` instead.

1. **Collect:** files modified, tasks completed, decisions made, problems hit.
2. **Active summary** (at most 300 tokens), printed for the user: branch, what was done, key
   decisions, files changed, what is next.
3. **Full log** (optional): save it to `.claude/session-logs/[YYYY-MM-DD]-[domain].md`. That folder
   is gitignored: a local handoff only, never committed.
4. **Hand off:** note anything a fresh session would need in order to continue.
5. **Propagate:** anything durable goes through `/learn-session` into a check, a rule,
   `.claude/OPERATIONS.md` or `.claude/anti-patterns/`, never into the log.
