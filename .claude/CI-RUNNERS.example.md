# CI Runners — Two Pools Behind Repository Variables

> **List it in the CLAUDE.md "On-demand References" table; never `@`-import it.** An import loads
> the whole file into every session. This is a template: copy it to `.claude/CI-RUNNERS.md` and
> fill every `<placeholder>`. `/promote-deploy` below is this template's command; installed from the
> agent-config-kit plugins it is `/agent-deploy:promote-deploy`.

Every `runs-on:` resolves through repository variables, so no runner label is ever hard-coded and
moving a pool is a variable change, not a commit. Workflows run on pull request events only, with no
`push` trigger and no scheduled (cron) workflow, so every billed minute belongs to a pull request.

```yaml
runs-on: ${{ vars.CI_RUNNER_FAST || vars.CI_RUNNER || 'ubuntu-latest' }} # a person waits on it
runs-on: ${{ vars.CI_RUNNER || 'ubuntu-latest' }} # nobody waits on it
```

| Variable         | Holds                                | Unset means                             |
| ---------------- | ------------------------------------ | --------------------------------------- |
| `CI_RUNNER`      | `<default-runner-label>`, or nothing | every job falls through to the next one |
| `CI_RUNNER_FAST` | `<fast-runner-label>`, or nothing    | the fast jobs fall through to CI_RUNNER |

Read the combinations before changing either:

| `CI_RUNNER_FAST` | `CI_RUNNER` | Where the jobs run                                                 |
| ---------------- | ----------- | ------------------------------------------------------------------ |
| unset            | unset       | everything on `ubuntu-latest`                                      |
| unset            | set         | everything on `CI_RUNNER`; the fast marking is inert               |
| set              | unset       | fast jobs on `CI_RUNNER_FAST`, the rest on `ubuntu-latest` (split) |
| set              | set         | fast jobs on `CI_RUNNER_FAST`, the rest on `CI_RUNNER`             |

Set them with `gh variable set CI_RUNNER_FAST --body <label>`; remove one with
`gh variable delete <name>`. Both take effect on the next run.

## Which jobs are marked fast

| Pool                   | Jobs in this repo                                    | Why                                    |
| ---------------------- | ---------------------------------------------------- | -------------------------------------- |
| `CI_RUNNER_FAST` first | `<the pull-request quality gate>`, `<preview build>` | a person is waiting on the result      |
| `CI_RUNNER`            | `<bots, advisory checks, post-merge jobs>`           | nobody waits; sub-minute on any runner |

## The allocation rule

GitHub-hosted runners round each job up to a whole minute, and many third-party runners bill the
same way; check your provider's rule. A job that takes 22 seconds and one that takes 44 cost the
same minute, so a faster runner saves nothing on a sub-minute job: it pays only above the one-minute
floor. Place a job by **who waits for its result**, not by how heavy it looks.

## Before moving jobs onto a pool — test the budget

An organisation budget set to stop usage at its limit may block all Actions or only paid usage
above the free tier, and the settings page does not say which. Test with a throwaway workflow, not
with the variables; while `CI_RUNNER` is set, nothing lands on `ubuntu-latest` to be observed:

1. Add a `workflow_dispatch` workflow with `runs-on: ubuntu-latest` written literally and a single
   `echo ok` step. Run it.
2. Green means the pool is reachable. A job that dies in about three seconds with no log means the
   budget blocks it; the reason is in the check-run annotation, not the run log. Delete the file
   either way.
3. Only if green, change the variables.

## Escape hatches

| Situation                             | Action                                                    |
| ------------------------------------- | --------------------------------------------------------- |
| Third-party pool gone, split **off**  | `gh variable delete CI_RUNNER` → everything on GitHub     |
| Third-party pool gone, split **on**   | delete whichever variable holds the third-party label     |
| GitHub-hosted pool gone, split **on** | `gh variable set CI_RUNNER --body <third-party-label>`    |
| Both pools gone                       | `/promote-deploy`: local gates, direct deploy, no minutes |

The variable holding the unavailable pool's label is the one to remove.

## Two things deliberately not done

**No dependency caching while jobs stay under a minute.** A job already under sixty seconds still
bills one minute however fast it gets, so a cache adds invalidation surface for zero minutes saved.
Revisit when a job crosses the minute.

**No path filters on markdown.** The quality gate reads markdown (the AI-config check, the workflow
mirror check, rule citations), so a `paths-ignore` on `**.md` would silently disable real checks.
A workflow that does filter by path (a workflows linter that reads only `.github/`) must never be a
required check: a required check that never reports blocks the merge.

## Quota monitoring is already native

GitHub's budgets email at 75%, 90% and 100% and can stop paid usage on their own. A scheduled
workflow that watches the quota duplicates that and spends the quota it guards; the gap worth
closing is the alert recipient list, which is a settings change. A third-party runner without a
usage API can be measured from the GitHub jobs API: sum `ceil(duration / 60)` over jobs whose
`runner_name` starts with the provider's prefix.

Every job also sets `timeout-minutes`: a hung job otherwise bills until the platform's own limit.

Splitting the pools buys headroom and removes the dependence on one vendor; it does not fix a quota
problem. Pruning jobs nobody reads does.
