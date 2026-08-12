<!-- Agents live in .claude/agents/ — authoritative list: ls .claude/agents/ -->
<!-- Manual invoke only — no auto-trigger. Call explicitly via the Task tool. -->

| Category | Agent                   | Use For                              | Validates / Does                                                |
| -------- | ----------------------- | ------------------------------------ | --------------------------------------------------------------- |
| Custom   | `agents-reviewer`       | Reviewing a modified component       | SoC, className vs style, line count ≤150, JSDoc, React Compiler |
| Custom   | `agents-seo-validator`  | Reviewing metadata or content change | metadataBase, OG, Twitter Card, JSON-LD, robots.txt             |
| Custom   | `agents-i18n-guard`     | Reviewing messages/ or t() calls     | en↔id key parity, hardcoded string detection                    |
| Custom   | `agents-security-guard` | Reviewing before commit / config     | CSP integrity, secret hygiene, XSS dangerouslySetInnerHTML      |
