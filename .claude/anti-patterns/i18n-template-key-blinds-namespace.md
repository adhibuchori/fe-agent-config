# One template key blinds the unused-key check for a whole namespace

**Applies to:** `scripts/check/i18n.ts` (`bun check:i18n`)
**Status:** Permanent (the checker cannot resolve a key built at run time)

## Symptom

Delete one component and `check:i18n` fails with a long list of unused keys, most of which have
nothing to do with the deleted component.

## Root cause

The checker cannot resolve a key built at run time, so it assumes the worst rather than report a
false positive. A template-literal call makes every key under its **static prefix** reachable, and
a call with no static prefix, or whose key is any other expression (`t(key)`), makes the **entire
namespace** reachable:

```ts
/* t(`errors.${code}`) blinds only <ns>.errors.*; t(`${key}.title`) and t(key) blind all of <ns>. */
const templatePattern = /\bt(?:[A-Z]\w*)?(?:\.(?:rich|raw))?\(\s*`([^`$]*)\$\{/g;
```

That is correct and deliberate. The consequence is the part to know:

**One ``t(`…`)`` call switches off dead-key detection for every key it could name, for as long as
that call exists** — the whole namespace when the key starts with the variable.

A component that renders ``t(`items.${index}.title`)`` keeps all of `items.*` exempt. Keys that
died long ago stay invisible. They do not become unused when that component is deleted; they become
**visible**.

## Why it is easy to misread

The failure arrives attached to the wrong change. Nothing in the output separates "this key died
just now" from "this key has been dead for months and the blanket just came off", so the natural
reading is that the deletion broke something, and the natural fix (restore the file) restores the
blindness.

## Fix

1. Before deleting a component that uses a template key, run the check on `HEAD` first, so a clean
   baseline and a failing run afterwards measure the revealed backlog.
2. Separate the two groups in the commit message. Keys orphaned **by** the change are yours; keys
   **revealed by** it are an older backlog, and quietly deleting translated copy that was written
   for planned UI is a real loss in every locale.
3. Recover wanted strings from git history. The checker has no allowlist, so the choice is binary:
   delete the keys, or keep the dead code that hides them.

## Scope

Every prefix a key is built under has no dead-key protection while that call exists, and a key
that starts with a variable takes the whole namespace with it. Prefer static keys (a lookup object
of `t('a')`, `t('b')`) where the set is known; otherwise keep a static prefix in front of the
variable.
