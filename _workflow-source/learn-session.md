---
description: Captures durable learnings from this session and writes each one into the check, rule, reference or anti-pattern that will load again. Edits files under .claude/ (and scripts/check/ for a new check); does not commit unless asked.
---

<!-- Command: /learn-session -->
<!-- Source: _workflow-source/learn-session.md -->
<!-- Run at the end of a session that taught something reusable -->

# /learn-session — Capture What Was Learned

`/checkpoint-summary` records **what happened**; this records **what should be different next
time**. The two are separate on purpose.

## The failure this is designed to avoid

Dated feedback files and session logs pile up where nothing reads them: half their entries are
superseded by later decisions, other repos never see them, and none of them load unless a session
goes looking. A learning only changes behaviour when it lands in a file that loads at the moment it
matters. **So there are no feedback or log files: every learning is written into a check, a rule, a
reference or an anti-pattern — or it is not written.**

## Step 1: Decide whether there is anything to save

Durable means: still true next week, in a different task, for a different session.

Save:

- A user preference or working style, with the reason behind it
- A trap that cost real time, plus the signal that identifies it next time
- A canonical fact: an exact path, value or command
- A correction the user had to make more than once

Do **not** save: one-off context, task state, or anything the repo already records (code, git
history, an existing rule). **If nothing qualifies, write nothing and say so.**

## Step 2: Route each learning to where it will load

Mechanisms first; a sentence is for what no mechanism can enforce. Rules that only grow while the
same corrections recur are the sign this order was skipped.

1. **Anything a check, hook or test can hold** → build that first: a script under
   `scripts/check/`, a hook rule with a probe of each kind in `scripts/check/hook-probes.tsv`, or a
   failing test.
2. **How the user wants work done, in any task** → one line in
   `.claude/rules/common/working-agreements.md`. It loads in every session and stays under 5 KB.
3. **A convention for one kind of file** → the path-scoped rule under `.claude/rules/` whose
   `paths:` match those files; create one only if none fits.
4. **A reproducible technical trap** → `.claude/anti-patterns/{slug}.md` plus a row in
   `.claude/anti-patterns/INDEX.md`.
5. **An operational fact (deploys, CI, MCP, bots)** → `.claude/OPERATIONS.md`.
6. **A binding, numbered project rule** → propose an `AGENTS.md` rule, appended and never
   renumbered; a repo without `AGENTS.md` gets one only when a rule needs a number. **Ask
   first.**
7. **Chronology of this session only** → `/checkpoint-summary`, not here.

## Step 3: Check before writing

- Read the destination first. The same learning already there → sharpen that line, never add a
  second one. A learning that contradicts an existing line → replace the line and say so.
- `working-agreements.md` stays one line per agreement and under 5 KB. Over budget means an older
  line is merged, moved to a path-scoped rule, or dropped.
- A command changes in `_workflow-source/` only, then `bash scripts/sync/workflows.sh` rewrites
  its mirrors; a new command also gets its `_workflow-source/INDEX.md` row.
- A new or changed skill, command, subagent or hook passes `bash scripts/check/skills.sh --staged`.

## Step 4: Write it

One line per learning: the rule, then the reason in a clause. Prefer an exact path, command or
value over a description of one. A rule without its reason gets discarded the first time it is
inconvenient; a reason without a rule gets re-argued.

## Step 5: Confirm

Report each file written and the line added or changed. Do not commit unless asked.
