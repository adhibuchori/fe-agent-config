#!/usr/bin/env bash
# Scans skills, slash commands, subagents and hooks with NVIDIA SkillSpector, pinned to one commit.
# A skill, command or hook runs with the agent's permissions, so a prompt-injection line or an
# exfiltrating shell step in one is a supply-chain risk like any other dependency.
#
# Triage: fix the cause, or record a narrow suppression (finding id + file + matched text + reason)
# in .skillspector-baseline.yaml; a third-party skill tree is accepted whole by its sha256 in the
# baseline's `vendored` list, and any upgrade changes the hash and fails until it is triaged again.
# A file SkillSpector inspected only in part fails too, unless the baseline's `partial` list names
# that exact target, file and reason code.
# Review every diff to the baseline by hand: it is the list of findings this gate ignores.
#
# Privacy: --static (the default, and what CI runs) is local. --llm sends the full text of every
# scanned file to an LLM provider (SKILLSPECTOR_PROVIDER, default claude_cli: your local `claude`
# login). Do not use --llm on content you may not share with that provider.
set -uo pipefail

PINNED_VERSION="2.11.2"
PINNED_REF="69dcdfb74487d361ba4c811d088cfdea2ff3a9dc"
INSTALL="uv tool install --python 3.12 \"git+https://github.com/NVIDIA/skillspector.git@${PINNED_REF}\""

usage() {
  cat <<'EOF'
Usage: bash scripts/check/skills.sh [--static|--llm] [--staged|--changed <base-ref>]

  --static         Pattern, AST, YARA and supply-chain analysis only, all local (default; what CI runs).
  --llm            Adds semantic analysis. Sends the scanned files' full text to an LLM provider:
                   SKILLSPECTOR_PROVIDER, or the local `claude` login when unset.
  --staged         Scan only the targets touched by the git index (pre-commit).
  --changed <ref>  Scan only the targets touched between <ref> and HEAD (CI).

Fails on any finding of MEDIUM or above that .skillspector-baseline.yaml does not suppress,
on any target SkillSpector could not inspect, and on any file it inspected only in part that
the baseline's `partial` list does not name (target + file + reason code). Reports land in
.skillspector/ (gitignored).
EOF
}

MODE="static"
SCOPE="all"
BASE_REF=""
while [ $# -gt 0 ]; do
  case "$1" in
  --static) MODE="static" ;;
  --llm) MODE="llm" ;;
  --staged) SCOPE="staged" ;;
  --changed)
    SCOPE="changed"
    BASE_REF="${2:-}"
    [ -n "$BASE_REF" ] || { echo "skills: --changed needs a base ref" >&2; exit 2; }
    shift
    ;;
  -h | --help) usage; exit 0 ;;
  *) echo "skills: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 2
BASELINE=".skillspector-baseline.yaml"
OUT_DIR="${SKILLSPECTOR_OUT:-.skillspector}"

# ── Target discovery ────────────────────────────────────────────────────────────────────────
# SkillSpector refuses symlinks, so a .claude/skills/<name> link is scanned at its real home in
# .agents/skills/, one skill per scan: --baseline is refused with -r. Commands are scanned at
# _workflow-source/, which is what the mirrors copy.
TARGETS=""
add_target() {
  case $'\n'"$TARGETS"$'\n' in *$'\n'"$1"$'\n'*) return ;; esac
  TARGETS="${TARGETS}${TARGETS:+$'\n'}$1"
}

is_command_without_source() {
  local rel="${1#.claude/commands/}"
  [ ! -f "_workflow-source/$rel" ]
}

add_path() {
  local p="$1" name
  case "$p" in
  "$BASELINE" | scripts/check/skills.sh) SCOPE="all" ;;
  .agents/skills/*/*)
    name="${p#.agents/skills/}"; name="${name%%/*}"
    [ -f ".agents/skills/$name/SKILL.md" ] && add_target "dir:.agents/skills/$name"
    ;;
  .claude/skills/*/*)
    name="${p#.claude/skills/}"; name="${name%%/*}"
    [ ! -L ".claude/skills/$name" ] && [ -f ".claude/skills/$name/SKILL.md" ] && add_target "dir:.claude/skills/$name"
    ;;
  _workflow-source/*.md)
    [ "$(basename "$p")" != "INDEX.md" ] && [ -f "$p" ] && add_target "file:$p"
    ;;
  .claude/commands/*.md)
    [ "$(basename "$p")" != "INDEX.md" ] && [ -f "$p" ] && is_command_without_source "$p" && add_target "file:$p"
    ;;
  .claude/agents/*.md)
    [ "$(basename "$p")" != "INDEX.md" ] && [ -f "$p" ] && add_target "file:$p"
    ;;
  .claude/hooks/*)
    [ -d .claude/hooks ] && add_target "dir:.claude/hooks"
    ;;
  esac
}

discover_all() {
  local d f
  if [ -d .agents/skills ]; then
    for d in .agents/skills/*/; do
      [ -f "${d}SKILL.md" ] && add_target "dir:${d%/}"
    done
  fi
  if [ -d .claude/skills ]; then
    for d in .claude/skills/*; do
      [ -L "$d" ] && continue
      [ -f "$d/SKILL.md" ] && add_target "dir:$d"
    done
  fi
  while IFS= read -r f; do add_path "$f"; done < <(
    find _workflow-source .claude/commands .claude/agents -name '*.md' -type f 2>/dev/null | sort
  )
  [ -d .claude/hooks ] && add_target "dir:.claude/hooks"
}

# A diff that cannot be read (no git work tree, an unknown base ref) is an error, never an empty scope.
case "$SCOPE" in
staged)
  CHANGED="$(git diff --cached --name-only --diff-filter=ACMR)" ||
    { echo "::error::skills: could not read the staged files" >&2; exit 2; }
  ;;
changed)
  CHANGED="$(git diff --name-only --diff-filter=ACMR "$BASE_REF"...HEAD)" ||
    { echo "::error::skills: could not diff $BASE_REF...HEAD" >&2; exit 2; }
  ;;
*) CHANGED="" ;;
esac
if grep -qxF "$BASELINE" <<<"$CHANGED"; then
  echo "::warning file=$BASELINE::this change edits the suppressions it is judged by; review that diff by hand"
fi
if [ "$SCOPE" != "all" ]; then
  while IFS= read -r f; do [ -n "$f" ] && add_path "$f"; done <<<"$CHANGED"
fi
[ "$SCOPE" = "all" ] && { TARGETS=""; discover_all; }

if [ -z "$TARGETS" ]; then
  echo "skills: no skill, command, agent or hook in scope - nothing to scan"
  exit 0
fi

# ── Tool ────────────────────────────────────────────────────────────────────────────────────
if ! command -v skillspector >/dev/null 2>&1; then
  echo "::error::skillspector is not installed. Install the pinned build: $INSTALL" >&2
  exit 1
fi
installed="$(env -u PYTHONPATH skillspector --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
if [ "$installed" != "$PINNED_VERSION" ]; then
  echo "::error::skillspector ${installed:-unknown} found, ${PINNED_VERSION} required: $INSTALL --force" >&2
  exit 1
fi

# ── Scan ────────────────────────────────────────────────────────────────────────────────────
rm -rf "$OUT_DIR" && mkdir -p "$OUT_DIR"
BASE_ARGS=(-f json)
[ -f "$BASELINE" ] && BASE_ARGS+=(--baseline "$BASELINE")
if [ "$MODE" = "static" ]; then
  BASE_ARGS+=(--no-llm)
else
  export SKILLSPECTOR_PROVIDER="${SKILLSPECTOR_PROVIDER:-claude_cli}"
  echo "skills: --llm sends the scanned files to provider '${SKILLSPECTOR_PROVIDER}'" >&2
fi

errors=0
n=0
while IFS= read -r t; do
  path="${t#*:}"
  n=$((n + 1))
  report="$OUT_DIR/$(printf '%03d' "$n")-$(printf '%s' "$path" | tr '/.' '__').json"
  printf '%s\t%s\n' "$path" "$report" >>"$OUT_DIR/index.tsv"
  env -u PYTHONPATH skillspector scan "$path" "${BASE_ARGS[@]}" -o "$report" </dev/null >"$report.log" 2>&1
  code=$?
  if [ "$code" -gt 1 ] || [ ! -s "$report" ]; then
    echo "::error::skillspector could not scan $path (exit $code) - see $report.log" >&2
    errors=$((errors + 1))
  fi
done <<<"$TARGETS"

# ── Gate ────────────────────────────────────────────────────────────────────────────────────
# SkillSpector's own interpreter ships PyYAML, which the vendored acceptance list needs.
GATE_PY="$(sed -n '1s/^#!//p' "$(readlink -f "$(command -v skillspector)" 2>/dev/null)" 2>/dev/null)"
[ -x "$GATE_PY" ] || GATE_PY="python3"
"$GATE_PY" - "$OUT_DIR/index.tsv" "$MODE" "$errors" "$BASELINE" <<'PY'
import hashlib, json, os, subprocess, sys

index, mode, errors, baseline_path = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
GATE = {"MEDIUM", "HIGH", "CRITICAL"}
ORDER = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3}
failures, rows, accepted = [], [], []

vendored, partial_ok, partial_used, scanned = {}, {}, set(), set()
if os.path.isfile(baseline_path):
    try:
        import yaml
    except ImportError:
        sys.exit(f"skills: PyYAML is needed to read {baseline_path}; install the pinned SkillSpector build")

    loaded = yaml.safe_load(open(baseline_path)) or {}
    for entry in loaded.get("vendored") or []:
        vendored.setdefault(entry["target"], {})[entry["sha256"]] = entry["reason"]
    # One entry per partly inspected file: target, path (as the report names it), reason_code and a
    # reason. No wildcards: a new file, target or reason code fails until it is triaged.
    for entry in loaded.get("partial") or []:
        key = (entry.get("target"), entry.get("path"), entry.get("reason_code"))
        if not all(isinstance(k, str) and k for k in key) or not str(entry.get("reason") or "").strip():
            sys.exit(f"skills: {baseline_path}: every `partial` entry needs target, path, reason_code and reason")
        partial_ok[key] = entry["reason"]


def tree_sha256(target: str) -> str:
    """Hash of every git-visible regular file under target: path, NUL, sha256 of its bytes."""
    listed = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", target],
        capture_output=True,
        check=True,
    ).stdout.split(b"\0")
    digest = hashlib.sha256()
    for rel in sorted(f for f in listed if f):
        if os.path.islink(rel) or not os.path.isfile(rel):
            continue
        with open(rel, "rb") as fh:
            digest.update(rel + b"\0" + hashlib.sha256(fh.read()).digest())
    return digest.hexdigest()


def evaluate(label: str, report: dict) -> None:
    scanned.add(label)
    issues = report.get("issues") or []
    gating = [i for i in issues if i.get("severity") in GATE]
    comp = report.get("analysis_completeness") or {}
    ledger = comp.get("ledger_exceptions") or []
    fatal = [e for e in ledger if e.get("fatal")]
    analyzers = comp.get("analyzer_statuses") or []
    incomplete = (
        report.get("execution_successful") is False
        or (comp.get("entirely_uninspected_files") or 0) > 0
        or bool(fatal)
        or bool(comp.get("scope_exclusions"))
        or any((a.get("failed") or 0) > 0 or (a.get("unaccounted") or 0) > 0 for a in analyzers)
        # Reported as not complete with no ledger entry saying why: nothing to triage, so it fails.
        or (comp.get("status", "complete") != "complete" and not ledger)
    )
    for e in ledger:
        if e.get("fatal"):
            continue
        key = (label, e.get("path"), e.get("reason_code"))
        if key in partial_ok:
            partial_used.add(key)
        else:
            failures.append(
                f"PARTIAL  {label}: {e.get('path')} inspected only in part ({e.get('reason_code')}: "
                f"{e.get('message')}); fix the cause, or add a `partial` entry with this target, path, "
                "reason_code and a reason to .skillspector-baseline.yaml"
            )
    meta = report.get("metadata") or {}
    llm_missing = mode == "llm" and not meta.get("llm_available")
    risk = report.get("risk_assessment") or {}
    counts = {s: sum(1 for i in issues if i.get("severity") == s) for s in ORDER}
    note = ""
    if gating and label in vendored:
        tree = tree_sha256(label)
        if tree in vendored[label]:
            note = "vendored"
            accepted.append(f"{label}: {len(gating)} finding(s) — {vendored[label][tree]}")
            gating = []
        else:
            failures.append(
                f"CHANGED  {label}: vendored tree is now sha256 {tree}; triage the findings below, "
                "then record that hash in .skillspector-baseline.yaml"
            )
    rows.append((label, risk.get("score", "-"), counts, report.get("suppressed_count", 0), note))
    for i in sorted(gating, key=lambda i: ORDER[i["severity"]]):
        loc = i.get("location") or {}
        failures.append(
            f"{i['severity']:<8} {i.get('id')} {i.get('category')} — {label}: "
            f"{loc.get('file')}:{loc.get('start_line')} — {i.get('explanation') or i.get('finding')}"
        )
    if incomplete:
        failures.append(f"INCOMPLETE {label}: SkillSpector did not finish inspecting this target")
    if llm_missing:
        failures.append(f"NO-LLM   {label}: --llm was requested but no provider answered")


with open(index) as fh:
    for line in fh:
        path, report_path = line.rstrip("\n").split("\t")
        try:
            data = json.load(open(report_path))
        except (OSError, ValueError):
            failures.append(f"UNREAD   {path}: its report {report_path} could not be read")
            continue
        evaluate(path, data)

print(f"\n{'target':<58} {'score':>5}  C  H  M  L  suppressed")
for label, score, c, sup, note in rows:
    print(f"{label[:58]:<58} {score!s:>5}  {c['CRITICAL']}  {c['HIGH']}  {c['MEDIUM']}  {c['LOW']}  {sup:<10} {note}")

if accepted:
    print(f"\n{len(accepted)} vendored target(s) accepted at their recorded tree hash:")
    for a in accepted:
        print(f"  {a}")
if partial_used:
    print(f"\n{len(partial_used)} partly inspected file(s) allowed by the baseline:")
    for key in sorted(partial_used):
        print(f"  {key[0]}: {key[1]} ({key[2]}) — {partial_ok[key]}")
stale = sorted(k for k in partial_ok if k[0] in scanned and k not in partial_used)
for key in stale:
    print(f"::warning file={baseline_path}::`partial` entry {key[0]}: {key[1]} ({key[2]}) matched nothing; remove it")
if failures or errors:
    print(f"\n{len(failures)} blocking finding(s), {errors} scan error(s):")
    for f in failures:
        print(f"  {f}")
    print("\nFix the cause, or add a narrow rule with a reason to .skillspector-baseline.yaml.")
    sys.exit(1)
print(f"\nskills clean: {len(rows)} target(s), mode={mode}, nothing at MEDIUM or above unsuppressed")
PY
