> Fired by hand before `/promote`: "run `.claude/docs/pre-promote-audit.md`". Loaded on demand,
> never automatically.

# Pre-Promote Quality Audit

An investigation of what this branch would ship to `prod`, measured against the **baseline** at
the end of this file. `/promote` already refuses a red CI, so this audit reads what a green gate
does not say: **drift** from the baseline, **risk** the promoted diff adds, and which known **gap**
the diff lands on.

The audit reports and stops. Every command below writes to `$TMPDIR` or nowhere, so it is safe in
a checkout other sessions share. Read counts unfiltered: an output wrapper that summarises output
turns a count into an estimate.

## Step 1 — Pin the range

```bash
git fetch -q origin prod
git rev-parse --short HEAD origin/prod
git rev-list --count origin/prod..HEAD
git diff --name-only origin/prod...HEAD
git status --porcelain | wc -l
```

Done when the report names both SHAs, the commit count, the changed files, and the number of
uncommitted files. The repo-wide numbers in Step 2 read the working tree: when it is dirty, say
that they include work the promotion does not carry.

## Step 2 — Measure drift

```bash
bash scripts/check/gates.sh            # every gate, read-only; prints "Logs: <dir>"
bun audit
./node_modules/.bin/oxlint -c oxlint.json --ignore-path=.oxlintignore -f unix > "$TMPDIR/oxlint.txt"
git shortlog -sne --since=90.days --no-merges HEAD
```

Then, with `<dir>` from the gates run:

```bash
python3 - "$TMPDIR/oxlint.txt" "<dir>/coverage/coverage-final.json" <<'PY'
import json, re, subprocess, sys
from collections import Counter

lint_path, cov_path = sys.argv[1:3]
files = subprocess.run(['git', 'ls-files', 'src'], capture_output=True, text=True).stdout.split()
ts = [f for f in files if f.endswith(('.ts', '.tsx'))]
tests = [f for f in ts if re.search(r'\.test\.tsx?$', f)]
source = [f for f in ts if f not in tests and not f.startswith('src/testing/')]
loc = lambda fs: sum(sum(1 for _ in open(f, errors='ignore')) for f in fs)
print(f'source: {len(source)} files, {loc(source)} LOC | tests: {len(tests)} files, {loc(tests)} LOC')
print('component test files:', sum(f.startswith('src/testing/components/') for f in tests))
diags = [l.strip() for l in open(lint_path) if re.match(r'\S+:\d+:\d+:', l)]
shipped = [l for l in diags if l.startswith('src/') and not l.startswith('src/testing/')]
print(f'oxlint: {len(diags)} diagnostics, {len(shipped)} in shipped source')
print('by rule:', Counter(re.search(r'\[([^\]]+)\]$', l).group(1) for l in diags).most_common())
cov = json.load(open(cov_path))
for key, name in (('s', 'statements'), ('b', 'branches'), ('f', 'functions')):
    hits = [c for v in cov.values() for c in (sum(v[key].values(), []) if key == 'b' else v[key].values())]
    print(f'{name}: {sum(1 for c in hits if c)}/{len(hits)}')
print('coverage files:', len(cov))
PY
```

A **regression** is any baseline row that moved the wrong way: a red gate, more diagnostics, a
covered count below its total, a vulnerability, a new dead-code finding.

In a dirty tree, attribute each red gate before counting it: when the files its log names appear in
`git status --porcelain`, the failure belongs to uncommitted work. Report those under their own
heading, apart from regressions in the commits being promoted.

Done when every row of the baseline table has a value measured in this run beside it.

## Step 3 — Read the risk in the diff

`no-explicit-any` and `react/no-danger` are lint errors, so the two ways around them are the
comments that switch a rule off. List every one at `HEAD` and compare with the baseline sites by
file and rule; line numbers drift, so match on those two.

```bash
git grep -nE 'dangerouslySetInnerHTML=|(eslint|oxlint)-disable' HEAD -- src ':!src/testing'
git diff origin/prod...HEAD -- package.json
```

- **New disable comment**: report the rule it switches off and the reason written beside it. No
  reason is a finding.
- **New raw HTML sink**: trace its value to the sanitiser the baseline names, or to an escaping
  formatter with XSS cases in its test. A value that reaches the sink any other way is a finding.
- **Dependency change**: name each added or bumped package. `bun audit` covers its CVEs; its
  weight in the bundle is unmeasured (see the gap register).
- **Module shape**, a judgement call: for each new file under `src/hooks` or `src/lib`, say whether
  its callers get more than they pass in (deep) or a thin pass-through (shallow). Report it as an
  observation, never a regression.

Done when every site the grep prints is either in the baseline list or reported, and every
package change is named.

## Step 4 — Check the gap register

A gap is something this repo does not have yet. For each row, confirm it is still open, then check
whether the changed files from Step 1 touch the paths where it bites. A touched gap turns into a
manual check the user runs before promoting, locally with `bun dev`, with a test account where a
flow needs one.

| Gap                                    | Open while                                                        | Bites when the diff touches                             | Ask the user for                                                                     |
| -------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| No end-to-end tests                    | `package.json` has no `@playwright/test` or `cypress`             | `src/lib/api/`, `src/proxy.ts`, `<your critical flows>` | A smoke test of each touched flow                                                    |
| No frontend error monitoring           | `package.json` has no error-tracking SDK (`AGENTS.md` § G)        | Error handling, error boundaries, new async paths       | Watching the service log after deploy, since a client error in `prod` reaches no one |
| Components outside the coverage policy | `vitest.config.ts` coverage `include` lacks `src/components`      | Components whose change is more than markup             | Nothing to run; name the components in the report                                    |
| No performance budget                  | No web-vitals, bundle analyzer or size check in `package.json`/CI | New dependencies, images, new client components         | A look at the page weight of the touched screens                                     |
| One human reviewer                     | `git shortlog` from Step 2 shows one person                       | Every promotion                                         | Nothing to run; state that review was AI-only                                        |

Done when every row says open or closed, and every open row says touched or untouched. A row that
turns out closed is a baseline update to propose.

## Step 5 — Report

```markdown
## Pre-promote audit: <HEAD sha> → prod <sha> (<n> commits, <m> files, <k> uncommitted)

Verdict: <n> regressions · <n> new risks · <n> gaps touched

### Baseline vs now
| Metric | Baseline | Now | Δ |

### Regressions
### New risks in the diff        (file:line, what, why it matters)
### Gaps this promotion touches  (the manual check each needs)
### Not verified                 (every step skipped or failed, and why)
```

The report ends the audit; fixing is a separate request. When the user accepts the new numbers,
offer to update the baseline below and write it only on their yes, with the date and SHA.

## Baseline

Not measured yet. The first run fills every row, on the user's yes, with the date and the SHA it
was measured on; until then every finding is reported as new.

| Metric                                     | Baseline |
| ------------------------------------------ | -------- |
| Source files / LOC (`src`, tests excluded) | —        |
| Test files / LOC                           | —        |
| Component test files                       | —        |
| Gates (`scripts/check/gates.sh`)           | —        |
| `tsc` errors                               | —        |
| oxlint diagnostics / in shipped source     | —        |
| oxlint by rule                             | —        |
| knip                                       | —        |
| `bun audit`                                | —        |
| Coverage (hooks, lib, store, i18n, proxy)  | —        |
| Human committers, last 90 days             | —        |

Raw HTML sinks, each with the sanitiser that feeds it: none recorded.

Disable comments in shipped source, each with its rule: none recorded.
