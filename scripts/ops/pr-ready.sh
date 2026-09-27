#!/usr/bin/env bash
# Says whether a pull request can be merged, in one read: its checks, GitHub's mergeability, the
# review threads nobody resolved, and whether its head is the branch its base expects. Reads only;
# it never merges, comments or pushes. /promote and /merge-pr run it before a merge instead of
# polling each part by hand.
#
#   bash scripts/ops/pr-ready.sh [--allow-skipped] <pr-number>
#
# Exit 0: ready. 1: something blocks the merge, named in the table. 2: the PR, or a part the table
# marks UNREAD, could not be read; nothing blocks as far as it could see.
#
# Checks. Only a success passes. A skipped or neutral check proves nothing, so the checks row names
# each one and blocks; --allow-skipped accepts them once the user has confirmed each is expected
# (a job that skips itself by design). A failed, cancelled, timed-out, stale or unknown result
# blocks, and so does one still queued, running or pending. No passing check at all blocks, flag
# or not.
#
# Branch flow. Default: any branch other than the repository's default branch may merge into the
# default branch; a PR into any other base is not judged by its head. PR_READY_FLOW replaces that:
# space-separated <base>=<head> pairs, where a head ending in * is a prefix ("prod=dev" makes a PR
# into prod come from dev). A base not listed takes any head.
# Needs gh (authenticated) and python3.
set -uo pipefail

PR="" ALLOW_SKIPPED=0
for arg in "$@"; do
  case "$arg" in
  --allow-skipped) ALLOW_SKIPPED=1 ;;
  *) [[ -z "$PR" ]] && PR="$arg" || PR="usage" ;;
  esac
done
[[ "$PR" =~ ^[0-9]+$ ]] || { echo "usage: bash scripts/ops/pr-ready.sh [--allow-skipped] <pr-number>" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "gh is not installed" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is not installed" >&2; exit 2; }

VIEW="$(gh pr view "$PR" --json number,title,state,headRefName,baseRefName,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup 2>/dev/null)" ||
  { echo "gh could not read PR #$PR from this repo" >&2; exit 2; }
REPO="$(gh repo view --json nameWithOwner,defaultBranchRef 2>/dev/null)" || REPO=""
SLUG="$(python3 -c 'import json,sys
try: print(json.loads(sys.argv[1])["nameWithOwner"])
except Exception: pass' "$REPO")"
DEFAULT_BRANCH="$(python3 -c 'import json,sys
try: print(json.loads(sys.argv[1])["defaultBranchRef"]["name"])
except Exception: pass' "$REPO")"
# Empty when the lookup fails, which the table reports as UNREAD: a failed read is never
# "0 unresolved", and a GraphQL error body is kept whole so it can be recognised.
THREADS=""
if [[ -n "$SLUG" ]]; then
  # shellcheck disable=SC2016 # $owner, $repo and $n are GraphQL variables, not shell ones
  THREADS="$(gh api graphql -F n="$PR" -f owner="${SLUG%%/*}" -f repo="${SLUG#*/}" -f query='
    query($owner: String!, $repo: String!, $n: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $n) {
          reviewThreads(first: 100) {
            pageInfo { hasNextPage }
            nodes { isResolved isOutdated comments(first: 1) { nodes { author { login } path } } }
          }
        }
      }
    }' 2>/dev/null)" || THREADS=""
fi

PR_READY_FLOW="${PR_READY_FLOW:-}" DEFAULT_BRANCH="$DEFAULT_BRANCH" ALLOW_SKIPPED="$ALLOW_SKIPPED" \
  python3 - "$VIEW" "$THREADS" <<'PY'
import json, os, sys

try:
    pr = json.loads(sys.argv[1])
except ValueError:
    print("gh returned something other than JSON for this PR", file=sys.stderr)
    sys.exit(2)
try:
    threads = json.loads(sys.argv[2]) if sys.argv[2] else None
except ValueError:
    threads = None
rows, blocked, unread = [], False, False


def row(what, ok, detail):
    global blocked
    blocked = blocked or not ok
    rows.append((what, "ok" if ok else "BLOCKS", detail))


def not_read(what, detail):
    global unread
    unread = True
    rows.append((what, "UNREAD", detail))


def head_matches(head, expected):
    return head.startswith(expected[:-1]) if expected.endswith("*") else head == expected


custom = os.environ["PR_READY_FLOW"].strip()
default_branch = os.environ["DEFAULT_BRANCH"].strip()
flow = dict(pair.split("=", 1) for pair in custom.split() if "=" in pair)
row("state", pr["state"] == "OPEN", pr["state"].lower())
base, head = pr["baseRefName"], pr["headRefName"]
if custom:
    expected = flow.get(base)
    head_ok = expected is None or head_matches(head, expected)
    row("head", head_ok, f"{head} into {base}" + ("" if head_ok else f"; {base} takes {expected} (PR_READY_FLOW)"))
elif not default_branch:
    not_read("head", f"{head} into {base}; the default branch could not be read, so the flow was not checked")
elif base == default_branch:
    row("head", head != base, f"{head} into {base}" + ("" if head != base else "; a branch cannot merge into itself"))
else:
    row("head", True, f"{head} into {base}; not the default branch ({default_branch}), so any head "
        "(set PR_READY_FLOW to check it)")


def outcome(check):
    """(verdict, GitHub's word): only SUCCESS passes, and anything unrecognised fails closed."""
    if check.get("__typename") == "StatusContext" or ("state" in check and "status" not in check):
        state = (check.get("state") or "").upper()
        return {"SUCCESS": "passed", "PENDING": "running", "EXPECTED": "running"}.get(state, "failed"), state or "NO STATE"
    status = (check.get("status") or "").upper()
    if status != "COMPLETED":
        return "running", status or "NO STATUS"
    conclusion = (check.get("conclusion") or "").upper()
    return {"SUCCESS": "passed", "SKIPPED": "skipped", "NEUTRAL": "skipped"}.get(conclusion, "failed"), conclusion or "NO CONCLUSION"


checks = pr.get("statusCheckRollup") or []
allow_skipped = os.environ["ALLOW_SKIPPED"] == "1"
by = {"passed": [], "failed": [], "running": [], "skipped": []}
for c in checks:
    verdict, word = outcome(c)
    by[verdict].append(f"{c.get('name') or c.get('context') or '?'} ({word.lower().replace('_', ' ')})")
names = lambda found: ", ".join(sorted(set(found)))
if not checks:
    row("checks", False, "none ran: a skip marker, a conflict, or a gate that skipped this branch")
else:
    detail = f"{len(checks)} checks, {len(by['passed'])} passed"
    for verdict in ("failed", "running"):
        if by[verdict]:
            detail += f"; {verdict}: {names(by[verdict])}"
    if by["skipped"]:
        detail += f"; skipped or neutral, not a pass: {names(by['skipped'])}" + (
            " (accepted: --allow-skipped)" if allow_skipped else " (--allow-skipped accepts them)")
    if not by["passed"]:
        detail += "; no check passed"
    ok = by["passed"] and not by["failed"] and not by["running"] and (allow_skipped or not by["skipped"])
    row("checks", bool(ok), detail)

mergeable = (pr.get("mergeable") or "UNKNOWN")
row("mergeable", mergeable == "MERGEABLE", f"{mergeable.lower()}, {(pr.get('mergeStateStatus') or 'UNKNOWN').lower()}")
if pr.get("reviewDecision"):
    row("review", pr["reviewDecision"] != "CHANGES_REQUESTED", pr["reviewDecision"].lower().replace("_", " "))

# A body with "errors" (rate limit, unknown repo) is unread even when it carries partial data.
readable = isinstance(threads, dict) and not threads.get("errors")
review = (((threads.get("data") or {}).get("repository") or {}).get("pullRequest") or {}).get("reviewThreads") if readable else None
if not isinstance(review, dict):
    not_read("threads", "could not read the review threads; check them on the PR page")
else:
    nodes = review.get("nodes") or []
    open_threads = [t for t in nodes if not t["isResolved"] and not t["isOutdated"]]
    where = sorted({(t["comments"]["nodes"] or [{}])[0].get("path") or "?" for t in open_threads})
    more = bool((review.get("pageInfo") or {}).get("hasNextPage"))
    if open_threads:
        row("threads", False, f"{len(open_threads)}{'+' if more else ''} unresolved: {', '.join(where[:5])}")
    elif more:
        not_read("threads", f"first {len(nodes)} threads resolved, more exist; check the rest on the PR page")
    else:
        row("threads", True, "0 unresolved")

print(f"PR #{pr['number']} {pr['title']}")
width = max(len(r[0]) for r in rows)
for what, verdict, detail in rows:
    print(f"  {what.ljust(width)}  {verdict.ljust(6)}  {detail}")
sys.exit(1 if blocked else 2 if unread else 0)
PY
