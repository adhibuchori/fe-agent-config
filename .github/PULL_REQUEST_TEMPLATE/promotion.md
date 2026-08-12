## Promotion: dev → prod

<!-- Filled in from `git log origin/prod..origin/dev` — do not hand-edit the commit
     list without re-checking it against that range. -->

### Commits Being Promoted

<!-- List each commit: short SHA — subject line. -->

### Local Merge Verification

- [ ] Ran `git merge --no-commit --no-ff origin/dev` locally against `prod` before
      opening this PR
- Result: <!-- clean / conflicts found and how resolved / not run -->

## Expected Diff Noise

This PR's diff will look far larger than the commit list above — `strip-ai-on-pr.yml`
removes `.claude/`, `.agent/`, `AGENTS.md`, `CLAUDE.md`, `SSOT.md`, and related AI
config from `prod` on every merge, so those files reappear as "new" on every single
promotion. This is expected noise, not a sign of scope creep — do not treat a large
file count as a red flag on its own.

## Post-Merge Checks

<!-- This file is shared verbatim across all 10 <Project Name> FE repos on purpose,
     to avoid drift between near-identical copies — delete the lines below that
     don't apply to this repo's type (app / CMS / docs) before submitting. -->

- [ ] Production deployment succeeded
- [ ] (App/CMS repos) If this repo dispatches `app-deployed`: confirm the event fired
      and the paired docs repo picked it up
- [ ] (Docs repos) Deployment succeeded and the live site reflects the new content
- [ ] (CMS repos) Any pending schema migrations ran cleanly against the production database
