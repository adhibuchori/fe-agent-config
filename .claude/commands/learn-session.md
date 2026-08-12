---
description: Capture durable learnings from this session and route them where they will actually be read again.
---

<!-- Command: /learn-session -->
<!-- Source: _workflow-source/learn-session.md -->
<!-- Run at the end of a session that taught something reusable -->

# /learn-session — Capture What Was Learned

`/checkpoint-summary` records **what happened**; this records **what should be different next
time**. The two are separate on purpose and must not be merged.

## The failure this is designed to avoid

A sibling project accumulated 92 session logs and 13 feedback files. None of it is ever read
back: no index, nothing referenced from `CLAUDE.md`. Notes that nothing loads are worth exactly
zero, no matter how well written. So **writing the file is only half the command — registering it
in an INDEX is the other half, and a note without an index entry is not done.**

## Step 1: Decide Whether There Is Anything To Save

Durable means: still true next week, in a different task, for a different person.

Save:

- User preferences and working style, with the reasoning behind them
- A trap that cost real time, plus the signal that identifies it next time
- A canonical reference — exact path, exact value, exact command
- A correction the user had to make more than once

Do **not** save: one-off conversation context, task state, or anything the repo already records
(code structure, git history, `CLAUDE.md`, existing rules). Saving those adds context cost and
returns nothing.

**If nothing qualifies, write nothing and say so.** An empty result is a valid, common outcome.

## Step 2: Route Each Learning To Its Real Home

Dumping everything into one folder is what made the sibling project's notes unusable.

| What it is                      | Where it goes                                                                       |
| :------------------------------ | :---------------------------------------------------------------------------------- |
| Reproducible technical trap     | `.claude/anti-patterns/{slug}.md` + row in `.claude/anti-patterns/INDEX.md`         |
| User preference / working style | `.claude/session-feedback/YYYY-MM-DD-{topic}.md` + row in its `INDEX.md`            |
| Binding project rule            | Propose an `AGENTS.md` rule — **ask first**, it is in the `settings.json` deny list |
| Chronology of this session only | `/checkpoint-summary`, not here                                                     |

## Step 3: Check For Duplicates Before Writing

Read `.claude/session-feedback/INDEX.md` and `.claude/anti-patterns/INDEX.md` first.

- Same topic already recorded → **update that file**, do not create a second one.
- Same topic, same day → append to today's file.
- Genuinely new → create the file, then add its INDEX row in the same step.

Duplicates are how an index stops being trustworthy, and an index nobody trusts stops being read.

## Step 4: Write It

Keep entries short and testable. Prefer an exact path, command, or value over a description of
one. State the **why** — a rule whose reason is missing gets discarded the first time it is
inconvenient.

```markdown
# Session Feedback — YYYY-MM-DD

## Topic

<one line>

## Learnings

- **<claim in one line>** — why it matters + how to apply it next time.
  Exact paths/values where relevant.

## Files touched

- `<path>`
```

INDEX row format, matching the convention already used by `anti-patterns/INDEX.md`:

```markdown
- [Short title](YYYY-MM-DD-topic.md) — one-line hook
```

## Step 5: Confirm

Report the exact file paths written and the INDEX rows added. Do not commit unless asked.

If `.claude/session-feedback/INDEX.md` does not exist yet, create it with a one-line header
before adding the first row.
