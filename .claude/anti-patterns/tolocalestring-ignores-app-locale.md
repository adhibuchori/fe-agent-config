# `toLocaleString()` follows the runtime locale, not the app's

**Applies to:** Any number, date, or currency formatting in a next-intl app
**Status:** Permanent (correct JavaScript behaviour, wrong for an i18n app)

## Symptom

Nothing fails, which is why this survives review. Numbers render with the wrong separators for the
chosen locale: a visitor who switched the app to `id` still sees `1,250` instead of `1.250`,
because the formatting never consulted the app's locale.

It tends to appear in several places at once, because it is copied: every stat, count and total
written as `{value.toLocaleString()}`.

## Root cause

`Number.prototype.toLocaleString()` with no argument uses the **runtime's** locale: the browser's
language on the client, and the server's `LANG` / ICU default during SSR. next-intl's active locale
is a React context value, which a bare `toLocaleString()` cannot see.

Two consequences, the second the nastier one:

1. The number ignores the in-app language switch.
2. Server and client can disagree (SSR formats with the server default, the client re-formats with
   the browser's), which is a hydration mismatch that only some visitors hit.

## Fix

Use next-intl's formatter, which reads the active locale from context:

```tsx
import { useFormatter } from 'next-intl';

const format = useFormatter();
return <span>{format.number(total)}</span>;
```

Dates go through `format.dateTime(...)`, relative times through `format.relativeTime(...)`. Under
`AGENTS.md` Rule 32 the formatting call lives in the hook that feeds the component, not in the
component itself.

## How to catch it

```bash
grep -rnE 'toLocale(Date|Time)?String\(|Intl\.(NumberFormat|DateTimeFormat)\(' src --include='*.ts' --include='*.tsx'
```

`Intl.NumberFormat` constructed with an explicit locale from next-intl is fine; constructed without
one it has exactly the same defect.

## Scope

Every formatted number and date in the app. Revisit only if the app drops i18n.
