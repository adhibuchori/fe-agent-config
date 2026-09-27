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

This PR's diff will look larger than the commit list above. `strip-ai-on-pr.yml` removes the AI
configuration from `prod` on every merge; the exact set is `STRIP_PATHS` in
`.github/scripts/strip-paths.sh`, and every path in it reappears as "new" on every single
promotion. This is expected noise, not scope creep.

`quality-gate.yaml` runs on this PR too. What it decides is not repeated here.

## Before Merging

- [ ] Production env audited against `.env.production.example` (the env step of `/promote`): no
      key missing, empty, a placeholder or a development value
- [ ] Sign-in, sessions or any other flow only a browser shows, if this promotion changes one,
      walked against `dev` with a test account in every locale

## Post-Merge Checks

<!-- Delete the lines below that don't apply to this repo before submitting. -->

- [ ] The deploy is confirmed on the platform: a green `ci-cd.yaml` run proves only that the
      webhook accepted it
- [ ] If this repo dispatches `app-deployed`: the event fired and the docs repo picked it up
