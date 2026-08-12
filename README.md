# fe-agent-config

A complete AI agent configuration layer for a **frontend** repository — rules, hooks, subagents,
slash commands, a CI quality gate, and a pipeline that strips the whole thing out of production
branches.

Not a guide about writing rules. The rules themselves, in the form that runs.

Its backend counterpart is [`be-agent-config`](https://github.com/adhibuchori/be-agent-config).

---

## What is actually in here

There are two ways to give an agent rules. One is prose it may or may not read. The other is a
guard that exits non-zero. This repo is mostly the second kind.

| Layer | Files | What it does |
| --- | --- | --- |
| **Router** | `CLAUDE.md` | What to read for which task. Kept short on purpose — it is loaded every session |
| **Guardrail** | `AGENTS.md` | Numbered, citable rules. A review can say "Rule 12" and mean something |
| **Contract** | `SSOT.md` | What the codebase *is*: layers, naming, API contract, environment |
| **Machine** | `.claude/`, `.mcp.json` | Hooks, subagents, anti-patterns, rule tiers, MCP servers |
| **Gate** | `.github/` | The definition of "passing", enforced on every pull request |

Concretely:

- **10 hooks.** `PreToolUse` guards that **block** the tool call (`exit 1`) — edits to generated
  output, unsafe shell, token leaks. `PostToolUse` hooks that format, lint, test, and check
  translation-key parity after the fact.
- **19 rule files in four tiers** — `common/` (language-agnostic) → `typescript/` → `react/` →
  `web/`. Adopt the tiers you need and delete the rest; each is self-contained.
- **4 subagents** — `sc-reviewer`, `sc-i18n-guard`, `sc-security-guard`, `sc-seo-validator`.
  Narrow scope each, so a review says one thing well rather than five things vaguely.
- **16 slash commands**, each maintained once in `_workflow-source/` and mirrored automatically
  into `.claude/commands/` and `.agent/workflows/`, with drift detection.
- **A quality gate** — format, lint, types, comment style, security audit, secret scan, tests with
  coverage, JSDoc presence, config drift, production build, source-map leak check.
- **An AI-config strip pipeline** that removes every file above from the production branch, so the
  deployed artifact carries no agent configuration.
- **5 anti-pattern entries** — real failures, each with the trigger keyword that should surface it.

---

## What is deliberately not in here

- **No application source.** No `src/`, no components, no API client, no lockfile.
- **No third-party skills.** Design and framework-health skills are documented in `SETUP.md` with
  their installers, not vendored — 200-odd files that go stale and are not ours to redistribute.
- **No secrets, and none required.** Every credential is an environment-variable reference.

---

## Start here

**[SETUP.md](SETUP.md)** — ordered by dependency, roughly an hour end to end. Fill placeholders,
wire hooks, run the gate, and only then touch the strip pipeline.

**[docs/RATIONALE.md](docs/RATIONALE.md)** — why the strange-looking parts are shaped that way.
Worth reading before you simplify anything. Several patterns here look like clutter and are load
bearing; the file names each one and what breaks when it is tidied.

---

## Two things to know before you clone

**The workflows arrive disarmed.** Every one of them triggers on `dev` or `prod`, and this repo has
only `main`. Nothing runs on push, and no secrets are needed. They wake up when you create those
branches in your own repo — which is the right order, since a gate has nothing to guard until then.

**Placeholders are named, never blank.** `<database-name>` rather than an empty string, so
`grep -rn '<[a-z-]*>'` gives you the complete to-do list.

---

## Adapting it

Take the tiers you need. `.claude/rules/common/` is language-agnostic and transfers as is.
`typescript/`, `react/`, and `web/` are progressively more specific — delete a tier outright rather
than half-editing it, since a rule file that contradicts your stack is worse than none.

The `sc-` prefix on subagents is just a namespace, so project agents sort together and never
collide with built-ins. Rename it to your own.

---

## License

MIT. See [LICENSE](LICENSE).
