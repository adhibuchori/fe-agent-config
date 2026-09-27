#!/usr/bin/env bash
# Usage: trigger-deploy.sh [ref]   (default: refs/heads/prod)
# Requires: DEPLOY_WEBHOOK_URL — the deploy platform's git-source deploy webhook.

set -euo pipefail

REF="${1:-refs/heads/prod}"
TIMEOUT=60

# Long enough to outlast a 2-4 min build, which refuses connections while it runs.
# Widening this needs a matching raise to the caller's timeout-minutes (ci-cd: 12m).
BACKOFF=(30 90 180)
ATTEMPTS=$(( ${#BACKOFF[@]} + 1 ))

if [ -z "${DEPLOY_WEBHOOK_URL:-}" ]; then
  echo "::error::DEPLOY_WEBHOOK_URL is not set; refusing to silently skip the deploy."
  exit 1
fi

body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT

for attempt in $(seq 1 "$ATTEMPTS"); do
  # A git-source webhook reads the branch from a GitHub push payload; without the header
  # and ref it can answer with a 3xx that deploys nothing.
  code="$(
    curl -sS -o "$body_file" -w '%{http_code}' \
      --max-time "$TIMEOUT" \
      -X POST "$DEPLOY_WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -H "x-github-event: push" \
      -d "{\"ref\":\"${REF}\",\"commits\":[]}"
  )" || code="000"

  echo "attempt ${attempt}/${ATTEMPTS}: HTTP ${code} $(cat "$body_file")"

  if [ "$code" = "200" ]; then
    echo "Deploy accepted by the deploy platform."
    exit 0
  fi

  # 3xx is the platform declining on purpose. curl's --fail flags ignore 3xx, so it must
  # be caught here or a declined deploy passes as success. Retrying cannot help.
  if [ "$code" != "000" ] && [ "$code" -lt 500 ]; then
    echo "::error::The deploy platform declined the deploy (HTTP ${code}): $(cat "$body_file")"
    exit 1
  fi

  # 000 or 5xx: usually the box busy building something else. Worth another try.
  if [ "$attempt" -lt "$ATTEMPTS" ]; then
    backoff="${BACKOFF[$((attempt - 1))]}"
    echo "Deploy platform unreachable; retrying in ${backoff}s."
    sleep "$backoff"
  fi
done

echo "::error::The deploy platform did not accept the deploy after ${ATTEMPTS} attempts."
exit 1
