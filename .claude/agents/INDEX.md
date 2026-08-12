<!-- Agents live in .claude/agents/ — authoritative list: ls .claude/agents/ -->
<!-- Manual invoke only — no auto-trigger. Call explicitly via the Task tool. -->

| Category  | Agent             | Use For                              | Validates / Does                                                |
| --------- | ----------------- | ------------------------------------ | --------------------------------------------------------------- |
| SC Custom | sc-reviewer       | Reviewing a modified component       | SoC, className vs style, line count ≤150, JSDoc, React Compiler |
| SC Custom | sc-seo-validator  | Reviewing metadata or content change | metadataBase, OG, Twitter Card, JSON-LD, robots.txt             |
| SC Custom | sc-i18n-guard     | Reviewing messages/ or t() calls     | en↔id key parity, hardcoded string detection                    |
| SC Custom | sc-security-guard | Reviewing before commit / config     | CSP integrity, secret hygiene, XSS dangerouslySetInnerHTML      |
