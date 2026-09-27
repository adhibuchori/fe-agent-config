#!/usr/bin/env bash
# Sets one key of a .env file to the value on stdin, while the user has unlocked env
# (scripts/ops/unlock.sh env). Keeps every other line, comment and quoting style; backs the old
# file up to .claude/state/env-backups/ (0600); logs the key name, never the value, to
# .claude/state/env-audit.log; prints the new value masked. Refuses templates (*.example): edit
# those directly. Exit 0 when set, 2 when refused.
# Usage: printf '%s' "$VALUE" | bash scripts/env/set.sh <file> <KEY>. See docs/unlock.md.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
command -v python3 >/dev/null 2>&1 || {
  echo "set.sh: python3 is required." >&2
  exit 2
}
# -I: no PYTHON* variable, user site or current folder decides what python3 imports.
exec python3 -I "$here/envfile.py" set "$@"
