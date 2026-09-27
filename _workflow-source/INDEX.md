<!-- Source of Truth: _workflow-source/ -->
<!-- Sync: bash scripts/sync/workflows.sh (copies these into .claude/commands/ and .agent/workflows/) -->

In the order work flows: plan, build, review, commit, pull request, release.

| Stage        | Command             | When to Use                                               | Example                                  |
| ------------ | ------------------- | --------------------------------------------------------- | ---------------------------------------- |
| Plan         | /plan               | Before every feature: scope, tasks and risks              | /plan add a settings page                |
| Plan         | /plan-fullstack     | A feature that also changes the backend                   | /plan-fullstack add blog posts API       |
| Build        | /rca                | A bug whose cause is not known yet: reproduce, then fix   | /rca form submits twice on slow networks |
| Build        | /checkpoint         | Before a risky change: a local safety commit              | /checkpoint before a folder move         |
| Build        | /check-fix          | The gates fail: fix what they report until all pass       | /check-fix                               |
| Review       | /review             | Before every commit; reads and reports                    | /review                                  |
| Review       | /review-soc         | A screen that grew logic: move it out of the components   | /review-soc src/components/              |
| Review       | /a11y-audit         | Before a release: ARIA, contrast and focus in `.tsx`      | /a11y-audit src/                         |
| Commit       | /commit             | After the work is done: gates, then a drafted message     | /commit                                  |
| Commit       | /ship               | Review, fix, commit and push the work branch              | /ship                                    |
| Pull request | /create-pr          | Draft and open the pull request into dev                  | /create-pr                               |
| Pull request | /resolve-pr-review  | Triage review comments, apply them, reply on each thread  | /resolve-pr-review 42                    |
| Pull request | /merge-pr           | Check readiness, then merge with a merge commit           | /merge-pr 42                             |
| Release      | /promote            | Promote the work branch through dev into prod, by PRs     | /promote                                 |
| Release      | /promote-deploy     | Promote with CI down, without pull requests               | /promote-deploy                          |
| Release      | /branch-cleanup     | After a promotion lands: delete the merged branches       | /branch-cleanup                          |
| Session      | /checkpoint-summary | A handover, every 90 minutes or 10 tasks                  | /checkpoint-summary auth-sprint          |
| Session      | /learn-session      | Write what the session taught where it will load again    | /learn-session                           |
