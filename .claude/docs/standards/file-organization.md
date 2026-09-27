> Rationale and worked examples behind `.claude/rules/web/file-organization.md`, which holds the binding rules. Loaded on demand, never automatically.

# ORG — File Organization Standard

A file's folder says which feature it belongs to, and the same feature is called the same thing
in every layer that touches it.

Enforced by `bun run check:hooks`, which runs in pre-commit and in
`.github/scripts/quality-gate.sh`. It blocks. There are no warning-only rules here.

## Why this exists

A hooks folder created to hold three files keeps growing, and nothing goes wrong along the way:
no review catches it, because no rule ever said what belonged there. The folder is a suggestion,
and a suggestion cannot refuse a file. The same absence produces flat hook folders where nothing in
a filename says which feature a hook serves, so "what does this hook belong to?" means opening it.

## The shared rule

**The folder path of a file equals the folder path of the feature it serves.** The vocabulary comes
from `src/components/`, which already names every feature in the product. Do not invent a parallel
taxonomy — a second set of names is a second thing to learn and a second thing to get wrong.

Directories are kebab-case (`SSOT.md` §4.2). Files keep their layer's convention: hooks camelCase,
components kebab-case.

## Hook folders

**1. Nothing sits loose in `src/hooks/`.** Every hook is in a feature folder, and there is no
`index.ts` at the root either: hooks are documented without one (`AGENTS.md` § L), and a barrel is
a re-export (Rule 34). (HOOK-1)

**2. The folder mirrors `src/components/`.** A hook consumed by `components/screens/projects/`
lives in `hooks/projects/`. Where components nest under an app namespace, hooks nest the same way:
`components/<ns>/projects/` pairs with `hooks/<ns>/projects/`. (HOOK-2)

**3. Three folders are not features, and are named for what they are:**

| Folder    | Holds                                                                |
| --------- | -------------------------------------------------------------------- |
| `api/`    | Service hooks — TanStack Query wrappers over the generated client    |
| `shared/` | Hooks used by more than one feature, owned by none of them           |
| `ui/`     | Hooks belonging to a primitive in `components/ui/`, not to a feature |

A hook goes in `shared/` when it carries no domain vocabulary of its own, or when it has
consumers in two or more feature folders. `useEscapeKey` qualifies on the first test and
`usePasswordGenerator` on the second. Looking generic is not the test — `useTaskFilter` looks
generic and belongs to tasks.

**4. The test moves with the hook.** `src/testing/hooks/` mirrors `src/hooks/` exactly. This is not
tidiness: nothing locates a test except its mirrored path, so a test left behind does not fail — it
stops running, silently, and the next person to edit that hook gets a green light from a test that
never executed. (HOOK-3)

**5. Hook filenames are globally unique.** A docs generator that keys on `path.basename(filePath)`,
not the full path, makes two hooks with the same name in different folders collide in the published
reference, and one of them silently wins. (HOOK-4)

**6. Imports inside `src/hooks/` are absolute.** Use `@/hooks/shared/useFlag`, never `./useFlag`. A
relative import is correct only while both files sit in the same folder, and it breaks the moment
either one is reclassified — which is exactly what this standard asks you to do when a hook's
ownership changes.

### Worked examples

|     |                                                                                     |
| --- | ----------------------------------------------------------------------------------- |
| ✅  | `hooks/projects/useProjectScope.ts` ← `components/screens/projects/project-list.tsx` |
|     | Folder matches the consuming feature. Debugging goes one way, then straight back.   |
| ✅  | `hooks/shared/useEscapeKey.ts`                                                      |
|     | No domain vocabulary of its own, and consumers in several features.                 |
| ❌  | `hooks/useProjectScope.ts`                                                          |
|     | Loose at the root. This is how a folder becomes a pile.                             |
| ❌  | `hooks/projects/useProjectScope.ts` + `src/testing/hooks/useProjectScope.test.ts`   |
|     | Test left at the old path. It stops running and nothing says so.                    |

## Feature folders

**7. A feature folder is named after its route segment.** `components/auth/forgot-password/`
answers to `app/[locale]/(auth)/forgot-password/`. Not after the screen file it holds
(`forgot-screen/`), and not after a shorter word someone preferred. The router already named every
feature in the product; that is the vocabulary, and it is the same one the hook folders above draw
on.

A feature whose route sits outside its group still gets a folder — a `security-setup/` feature
reached at `app/[locale]/security-setup/`, deliberately outside `(auth)` to avoid a redirect loop,
is still a feature. The folder is justified by the feature, not by the route group.

**8. No component sits loose in the feature root.** `components/auth/` holds folders only. A file
directly under it is a file nobody classified.

**9. `shared/` means shared between siblings, and nothing else.** A part goes in
`<feature-root>/shared/` when two or more sibling features import it. One consumer means it lives
in that consumer's folder, even when it looks reusable — a `captcha-widget.tsx` used only by login
stays in `login/` until a second caller appears.

**10. `shell/` is not `shared/`.** Layout chrome — navbar, brand panel, illustration — is consumed
by `layout.tsx` and by zero features, so `shared/` would be a lie about it. Layout files sitting
beside a form button is how a `shared/` folder becomes a junk drawer.

**11. A part used from OUTSIDE the feature root does not belong to that root at all.** It moves to
the repo's cross-cutting home, `src/components/shared/<system>/` unless `SSOT.md` §4.3 names
another, never to `<feature-root>/shared/`. This is the rule that is easiest to get wrong, because
`shared/` sounds like it should absorb anything with several callers.

Named for the system it implements (`shared/modal/`, `shared/credentials/`), not for a category
(`shared/misc/`). Note `shared/` is not `ui/`: `ui/` is primitives, `shared/` is composed systems.

**12. Imports inside a feature root are absolute** — `@/components/auth/shared/auth-link`, never
`../shared/auth-link`. Same reason as rule 6, but sharper here: a relative import that escapes the
folder (`../../ui/form-input`) breaks on any change of depth, and it breaks at **build** time rather
than at move time. Convert to absolute BEFORE splitting a folder, as its own commit; then the split
is a pure rename and the diff is reviewable.

### Worked examples

|     |                                                                                           |
| --- | ----------------------------------------------------------------------------------------- |
| ✅  | `auth/verify-otp/{verify-otp-screen,otp-field-row,resend-timer}.tsx`                      |
|     | One folder answers `(auth)/verify-otp/`. The whole flow is three files and they are here. |
| ✅  | `auth/shared/auth-form-header.tsx`                                                        |
|     | Imported by several sibling screens. Belongs to no one feature, so it belongs to shared.  |
| ✅  | `shared/credentials/password-field.tsx`                                                   |
|     | Called from auth, account and settings. Left `auth/` because it was never an auth part.   |
| ❌  | `auth/shared/auth-error-modal.tsx`                                                        |
|     | Three of its callers are in `settings/security/`. `shared/modal/` is where it belongs.    |
| ❌  | `auth/two-factor-invite.tsx`                                                              |
|     | Named for two-factor, imported only by security-setup. Name the folder by the consumer.   |

## Screen folders

**13. A screen lives inside the folder that holds its parts.** `screens/projects/projects-screen.tsx`,
never `screens/projects-screen.tsx` sitting beside `screens/projects/`. A screen file loose at the
root of a directory whose every sibling is a folder is the exact shape this section exists to
prevent: the parts are grouped, and the one file that composes them is somewhere else.

**14. Only the screen moves in. The parts stay where they are.** Do not pull a parts folder inside a
screen folder to make the tree look tidier — that is how a shared folder acquires an owner it does
not have. What changes is the screen's own import: `./projects/project-header` becomes
`./project-header` for its own folder, and `../tasks/task-card` for anyone else's.

**15. A parts folder used by two or more screens stands on its own.** An `item-filter/` folder with
no screen of its own is not an oversight: it is the filter UI that two screens both compose. Naming
it after either consumer would be false, and moving it inside one would break the other. This is
rule 11 seen from the screen side — a part with callers outside the folder does not belong to that
folder.

**16. Several screens of one domain may share one folder.** `screens/billing/` holds
`checkout-screen`, `invoice-screen` and `billing-history-screen` beside the parts all three compose.
The folder follows the domain, not the file count: three folders holding one screen each, with the
parts stranded in a fourth, reads worse than one honest folder.

The mirrored test moves in the same commit, for the reason spelled out in rule 4 — a test left
behind stops running instead of failing.

### Worked examples

|     |                                                                                          |
| --- | ---------------------------------------------------------------------------------------- |
| ✅  | `screens/dashboard/{dashboard-screen,summary-card,activity-card}.tsx`                    |
|     | The screen and everything it composes, in one place. Debugging starts and ends here.     |
| ✅  | `screens/item-filter/`                                                                   |
|     | No screen of its own. Composed by two screens, so it belongs to neither.                 |
| ✅  | `screens/billing/{checkout,invoice,billing-history}-screen.tsx`                          |
|     | One domain, three screens, one set of parts. The folder is named for the domain.         |
| ❌  | `screens/projects-screen.tsx` beside `screens/projects/`                                 |
|     | The split this section exists to prevent.                                                |
| ❌  | `screens/projects/tasks/task-card.tsx`                                                   |
|     | Pulled inside projects to tidy the tree. `tasks-screen` imports it too and now reaches in. |
