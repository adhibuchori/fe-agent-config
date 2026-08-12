---
description: Run TypeScript check, linting, and formatting, then apply fixes if possible.
---

<!-- Command: /check-fix -->
<!-- Source: _workflow-source/check-fix.md -->

# /check-fix — Quality Check & Fix

This workflow ensures the codebase meets quality standards by running type checks, linting, and formatting, with automatic fixes where possible.

1. **TypeScript Check**: `bun type-check`
   - **Verification**: Must finish with exit code 0.
   - **Action**: If it fails, report the type errors and fix them manually.

2. **Lint & Format Check**: `bun fl`
   - **Verification**: Must finish with exit code 0.
   - **Action**: If it fails due to formatting or fixable lint issues, proceed to the fix step.
   - **Note**: `bun fl` runs oxfmt (format) + oxlint (lint) in one pass.

3. **Auto-Fix**: `bun fl`
   - **Action**: Re-run `bun fl` — oxlint applies auto-fixes on re-run where possible.
   - **If still failing**: Fix remaining issues manually. Never use `// oxlint-disable` — resolve the root cause (AGENTS.md Rule 28).

4. **Final Verification**: Run `bun type-check` and `bun fl` again.
   - **Goal**: Both must pass (exit code 0) for a clean state.

Output: Final status (PASS/FAIL) with a summary of fixed and remaining issues.
