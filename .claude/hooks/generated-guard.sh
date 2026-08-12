#!/usr/bin/env bash
# Blocks writes to orval-generated files and the BE contract.

FILE="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"

if [[ -z "$FILE" ]]; then
  exit 0
fi

# Block writes to generated API directory
if [[ "$FILE" == *src/lib/api/generated/* ]]; then
  echo "[generated-guard] BLOCKED: $FILE is orval-generated and read-only. Run 'bun generate:api' to regenerate." >&2
  exit 1
fi

# Block writes to the openapi contract. Both extensions are matched: orval reads openapi.json
# here, and matching .yaml too keeps the guard correct if the contract format ever changes.
if [[ "$FILE" =~ (^|/)openapi\.(json|yaml|yml)$ ]]; then
  echo "[generated-guard] BLOCKED: $FILE is the BE contract and must not be modified from the FE." >&2
  exit 1
fi

exit 0
