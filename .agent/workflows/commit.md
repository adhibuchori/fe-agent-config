---
description: Run the quality gates, inspect the staged changes, and draft a commit message in this repo's format. Drafts only; does not commit.
---

<!-- Command: /commit -->
<!-- Source: _workflow-source/commit.md -->

# /commit — Quality Gate & Commit Message Generator

1. **Quality Gate**: run `/check-fix` first. Do not proceed from a broken state.

2. **Inspect**: `git diff --staged` and `git status`, read whole (with RTK installed,
   `rtk proxy git diff --staged` and `rtk proxy git status`: its rewrite condenses both).
   - **Never commit**: a real `.env*` file (the `.env.*.example` templates are fine), or a hand
     edit under `src/lib/api/generated/`.
   - `.claude/settings.json` goes in a commit of its own, together with the hooks it wires, never
     swept into another change.

3. **Stage explicitly** by name, and commit by pathspec (`git commit -- <paths>`). Never
   `git add -A` or `git add .`: staging everything is `/ship`'s alone, because only `/ship` runs
   the guards that make it safe.

4. **Draft the message** in CLAUDE.md § Commit Format:

   ```
   type(scope): subject — max 50 characters

   [Optional body explaining the why, wrapped at 72 characters]
   ```

   - **Types**: `feat` · `fix` · `refactor` · `chore` · `docs` · `style` · `perf` · `test`
   - **Scope**: the area touched, e.g. `nav`, `auth`, `i18n`, `ui`, `api`, `hooks`, `lib`
   - **Subject**: imperative mood, lowercase, no trailing period
   - **Body (optional)**: after a blank line, the why and the what, for someone reading `git log`
     months from now
   - Add whatever attribution trailer your harness or team requires; never hard-code a model name.
   - Example:

     ```
     feat(nav): add mobile drawer navigation

     Implement the mobile menu drawer to improve mobile responsiveness.
     This includes transitions and close-on-click outside behaviors.
     ```

Output the drafted message. Do not run the commit itself.
