# `wc -l` disagrees with the `max-lines` gate, and only the gate decides

**Applies to:** Any file under `oxlint.json`'s
`"max-lines": ["warn", { "max": 150, "skipBlankLines": true, "skipComments": true }]` (`AGENTS.md`
Rule 27)
**Status:** Permanent (the flags are deliberate, so the mismatch is a property, not a bug)

## Symptom

A review or an audit lists files "over the 150-line limit", while `bun run fl` has never warned
about any of them. Files get split to fix a violation that no gate reported.

Both numbers are correct. They count different things.

## Root cause

`skipBlankLines` and `skipComments` make the rule count **code** lines only. A codebase that writes
its reasoning in comments above short functions carries a large gap between the two numbers, so two
files with the same `wc -l` can get opposite verdicts from the rule.

The error runs one way: `wc -l` over-reports. It never hides a real breach; it invents work that no
gate asked for.

## Fix

Ask the gate, which is the only thing that decides:

```bash
bun run fl 2>&1 | grep max-lines        # ✅ the actual gate
find src -name '*.tsx' | xargs wc -l    # ❌ counts blanks and comments
```

The gate names every breaching file with the counted number (`File has too many lines (186)`) and
says nothing about the rest. Use that number.

## What not to do

- **Do not split a file because `wc -l` says so.** The split may be fine on its own merits, but a
  report that calls it "resolving a violation" describes one that never existed.
- **Do not change the config to make the two agree.** A file is hard to read because of how much
  code it holds; dropping `skipComments` would penalise exactly the comments the repo asks for.

## Scope

Bites hardest when a length audit is delegated: `wc -l` is the obvious tool for an agent asked to
check file sizes, and it is the wrong one. If the two flags are ever removed, the counts converge
and this entry can go.
