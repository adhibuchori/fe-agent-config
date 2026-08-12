<!-- Source of Truth: _workflow-source/ -->
<!-- Sync: bash scripts/sync-workflows.sh -->

| Category | Command             | When to Use                   | Example                              |
| -------- | ------------------- | ----------------------------- | ------------------------------------ |
| Planning | /plan               | Before every feature          | /plan add Posts collection           |
| Planning | /plan-fullstack     | Before fullstack feature      | /plan-fullstack add blog posts API   |
| Quality  | /review             | Before every commit           | /review                              |
| Quality  | /a11y-audit         | Before release                | /a11y-audit src/                     |
| Quality  | /check-fix          | Quick quality gate            | /check-fix                           |
| Design   | /impeccable         | UI design/critique/polish     | /impeccable audit src/components/    |
| Safety   | /checkpoint         | Before risky changes          | /checkpoint before schema refactor   |
| Session  | /checkpoint-summary | Every 90min / 10 tasks        | /checkpoint-summary cms-sprint       |
| Session  | /learn-session      | Capture durable learnings     | /learn-session                       |
| Release  | /create-pr          | Generate + create PR          | /create-pr                           |
| Release  | /resolve-pr-review  | Triage & apply PR review      | /resolve-pr-review 42                |
| Release  | /merge-pr           | Check readiness & merge PR    | /merge-pr 42                         |
| Workflow | /commit             | After work done               | /commit                              |
| Workflow | /review-soc         | SoC audit                     | /review-soc src/collections/Posts.ts |
| Release  | /promote            | Promote internal → dev → prod | /promote                             |
| Release  | /promote-dokploy    | Promote with CI down (no PR)  | /promote-dokploy                     |
| Release  | /branch-cleanup     | After a promotion lands       | /branch-cleanup                      |
