# Session Feedback — YYYY-MM-DD

> **This is a worked example, not real feedback.** It shows the shape an entry should take.
> Delete it once you have written one of your own.

## Topic

Scope discipline, and the standard of evidence expected before a plan is presented.

## Learnings

- **Deliver the ask, not the ambitious version of it.** Asked how to give a second tool access to
  the project rules, the first proposal included restructuring two rule documents. The eventual
  solution touched **zero** existing files. Next time: solve the stated problem first, and if a
  larger refactor genuinely helps, name it as a separate option rather than folding it into the
  plan.

- **Do not claim a design is "optimal" without evidence.** Asked directly how that could be known,
  it could not be — the plan rested on an unverified assumption about which directory the tool
  reads. State confidence honestly and name the weakest link.

- **Verify the load-bearing assumption before writing the plan around it.** Everything hinged on
  the tool reading a rules directory at all. Confirming that with a dummy rule took two minutes,
  and it also corrected the directory name. A cheap check first would have avoided a plan written
  on a guess.

- **When copying an existing pattern, check the pattern actually works.** A new sync script was
  modelled on an older one that had already drifted, because the older one's orphan detection only
  looked in one direction. The new script gained a `--check` mode specifically to cover that gap.

## Files touched

- `<path>`
- `<path>`

---

## Why this directory exists, and why it sits where it does

Entries here are **behavioural**, not technical: how the user wants work done, and why. That is why
`CLAUDE.md` points to this index next to the Behavioral Protocol rather than in the Context Loading
Strategy table — it is not context about the code.

Two rules keep it useful rather than growing into noise:

1. **One file per topic, not per session.** Update the existing file when the same theme recurs.
   Ten near-duplicate entries are read as zero.
2. **Record the reasoning, not just the correction.** "Be less verbose" ages badly. "Long preambles
   buried the one number the user needed" tells the next session what to actually do.
