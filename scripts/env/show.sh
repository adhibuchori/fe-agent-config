#!/usr/bin/env bash
# Lists the keys of a .env file with every secret value masked, then the keys that differ from its
# template (.env.<target>.example). The one way the agent reads a real .env* file: the hooks refuse
# every other shell read of one. Exit 0; 1 when the template has keys the file lacks; 2 on a bad
# argument. Usage: bash scripts/env/show.sh <file>. See docs/unlock.md.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
command -v python3 >/dev/null 2>&1 || {
  echo "show.sh: python3 is required." >&2
  exit 2
}
# -I: no PYTHON* variable, user site or current folder decides what python3 imports.
exec python3 -I "$here/envfile.py" show "$@"
