# Serena Error Log

> One entry per distinct failure. Before reusing a tool that has failed here, check for a matching
> entry and apply the recorded workaround — that is the whole point of the file. An empty log means
> nothing has failed yet, not that the file is unused.

## YYYY-MM-DD — [tool name]

**Error:** [exact error message]
**Parameters:** [exact params]
**Workaround:** [what was done instead]

## Known failures (Serena 1.x)

Recorded where the tool's own error names the missing field and not the wrong one.

**Editing tools take `name_path`, not `name_path_pattern`.** Only `find_symbol` (and
`safe_delete_symbol`) take `name_path_pattern`; `replace_symbol_body`, `insert_*_symbol` and rename
answer `name_path Field required`.

**`replace_content` and `replace_in_files` take `needle` and `repl`**, not `pattern`, `content` or
`replacement`. A rejected call applies nothing, so re-issue it with the keys renamed.

**`repl` is literal in regex mode.** `\n` in `repl` is written as a backslash and an `n`, and a
backreference such as `\1` is not interpolated: preview with `dry_run: true`, put real line breaks
in `repl`, and fall back to the Edit tool when a backreference is needed. After any regex
replacement, read the lines back before trusting `OK`.

**A literal needle goes stale after a format pass.** The formatter reflows signatures, so a
multi-line needle captured before `fl` no longer matches: re-read the file, or use `mode: "regex"`
with a wildcard across the part that moves.

**`\A.*\Z` overlaps itself.** A whole-file regex is refused as ambiguous: anchor on real text.

**No Serena tools in the session** (the server timed out or never started): say so, and fall back
to the built-in tools only after the user agrees.
