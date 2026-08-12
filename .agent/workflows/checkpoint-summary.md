---
description: Generate a session summary of changes, decisions, and tasks for efficient handovers.
---

<!-- Command: /checkpoint-summary [domain] -->
<!-- Source: _workflow-source/checkpoint-summary.md -->
<!-- Run every 90min or every 10 tasks -->

# /checkpoint-summary — Session Summary

1. COLLECT: files modified, tasks completed, decisions made, issues encountered
2. ACTIVE SUMMARY (≤300 tokens): print for user to copy
   - Branch, what was done, key decisions, files changed, what's next
3. FULL LOG: save to .claude/session-logs/[YYYY-MM-DD]-[domain].md
4. PROPAGATE: offer to add new anti-patterns discovered to AGENTS.md
