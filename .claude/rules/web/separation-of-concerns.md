---
paths:
  - 'src/components/**'
  - 'src/hooks/**'
  - 'src/lib/**'
  - 'src/types/**'
---

# SOC — Separation of Concerns

A component renders. Behaviour and state live in a custom hook; derivation lives in a pure
function. Enforced by the `no-restricted-imports` overrides in `oxlint.json`, which block
everywhere, and by `bun run check:soc`, which joins pre-commit and the quality gate the moment the
repo reads clean. A repo still carrying findings runs it before every commit that touches
components and clears them by category, never by exemption. The layer map is `SSOT.md` §4.1; the
numbered rules are `AGENTS.md` Rules 6, 7, 14 and 32.

A layer rule that nothing reads is a convention. Without the `import` plugin loaded, oxlint cannot
see a single arrow in the layer map, and a review that runs only when someone remembers to type
`/review` misses every commit in between. That is why each rule below names what enforces it.

## What a component file may contain

- Props and their types.
- Calls to custom hooks — one hook per concern, each returning a view model that is ready to render.
- JSX, including `.map()` whose callback returns JSX.
- Class composition through `cn()` / `cva()`.
- A comparison or ternary that **selects** among values the hook already provided.

## What it may not contain

- **S1** `useState`, `useEffect`, `useLayoutEffect`, `useReducer`, `useMemo`, `useCallback` — not one. A boolean goes through `useFlag()` / `useDisclosure()`; a form value through a named form hook; an effect through a named hook. React Compiler is active, so a memo is usually deletable rather than movable.
- **S2** A `useRef` that is not passed to a JSX `ref=` in the same file. A ref binding a node is presentation and stays; a ref used for timing or as a latest-value box is bookkeeping, which is behaviour.
- **S3** A function declaration other than the component. A helper beside the component is logic in the wrong layer; a `Lib:` docblock on it gives that away.
- **S4** `new Date`, `Date.now`, `toLocaleDateString`, `toLocaleTimeString`, or a `timeZone:` option. Dates and their time zone are formatted in one module, not in each component that shows one.
- **S5** `.filter` / `.reduce` / `.sort` / `.toSorted` / `.flatMap` / `.some` / `.every` / `.find`, and any `.map` whose callback returns data rather than JSX. Mapping to **render** stays; reshaping **moves**.
- **S6** `window` / `document` / `navigator` / `localStorage` / `sessionStorage`, a timer, or an observer.
- **S7** `await`. A component that awaits is a component making its own request.
- **S8** A condition over more than one domain field (`status === 'pending' && !submitted`). These break silently and cannot be tested without rendering.
- **S9** A `.ts` module under `src/components/` that reaches across a layer. Colocating an icon or variant map beside its single consumer is file-organization rule 9 and is correct; importing the store from there is not, and `no-restricted-imports` refuses it.
- **S10** A handler with a block body. `close(); signOut.open();` is a sequence, and a sequence is one named action the hook exposes — `onSignOut={menu.requestSignOut}`. `onClick={flag.on}` forwards a single call and stays; the brace is where a second statement goes, so the brace is the signal.
- **S11** A domain value compared against a bare string: `status === 'published'`. Compare against its constant, `status === POST_STATUS.published`. "Domain" is read off the type: a value whose declared type is a string-literal union exported from `src/types/`. The constant lives in `src/lib/constants/<domain>/` and is declared `as const satisfies LiteralMap<Union>`, which makes it exhaustive and keeps each key equal to its value, so a member added to or renamed in the union breaks the build instead of leaving copies behind. A presentation prop (`layout === 'grid'`, `variant === 'compact'`) is not a domain type and stays literal. `check:soc` reads this through the TypeScript checker, not the text, because the literal alone cannot tell a prop from a status.

## Where each thing goes

| Leaving the component                                         | Destination                                                                       |
| ------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| State, effects, timers, browser APIs, async                   | a named hook in `src/hooks/`, mirroring the component's folder                    |
| Pure derivation, parsing, formatting, sorting                 | `src/lib/` — where the hook calls it                                              |
| A server DTO the UI was naming                                | a hand-written view model in `src/types/`, mapped in the hook that owns the fetch |
| A value two files compare against                             | its constants home, never a second copy                                           |
| A member of a `src/types/` union a component compares against | a `LiteralMap` constant in `src/lib/constants/<domain>/` — S11                    |

## Whose data it is

What the server records — what was paid, what is owed, what was granted — is read from the server
on every screen that shows it, never mirrored into a store or browser storage. A device copy is a
second answer to a question that already has one: it is empty on a second browser, it survives a
row the server has deleted, and it hydrates a render later than the screen reads it, so the screen
shows "nothing yet" for data that exists. Persisted state is for what only this device knows — a
collapsed rail, a draft, a chosen theme.

Never solve a layer violation by re-exporting (`AGENTS.md` Rule 34). A barrel that forwards another
module's exports adds a name without moving the dependency, and the import it was hiding is still
there.

## Keys and routes

A message key or a route is an identifier. Never assemble one from a domain value
(`t(`role${role}`)`): map it through an exhaustive `Record<Domain, Key>` instead, such as a
`role-labels.ts` beside the role constants. `check:i18n` reads literal keys statically, so a key
built from a value is a key it cannot see, and an unused one stops being detectable.

## Exemptions

`scripts/check/soc.allow.json` — `{ path, check, reason }`. The reason is mandatory, and an entry
that matches nothing fails the check too, so the file cannot become a record of things that used to
be true. "Pre-existing" is not a reason.
