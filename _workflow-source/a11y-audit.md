---
description: Comprehensive accessibility audit for .tsx files to identify ARIA, contrast, and focus issues.
---

<!-- Command: /a11y-audit [path] -->
<!-- Source: _workflow-source/a11y-audit.md -->
<!-- Run before release -->

# /a11y-audit — Accessibility Audit

Scan all .tsx files in [path] for:

- Missing aria-label or aria-labelledby on interactive elements
- Missing alt text on images
- Missing focus styles (outline: none without replacement)
- Color contrast issues (flag for manual check)
- Keyboard trap risks
- Missing ARIA roles on custom components

Output per finding: CRITICAL / WARN / INFO with file:line.
