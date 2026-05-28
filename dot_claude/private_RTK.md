# RTK - Rust Token Killer

**Usage**: Token-optimized CLI proxy (60-90% savings on dev operations)

## Meta Commands (always use rtk directly)

```bash
rtk gain              # Show token savings analytics
rtk gain --history    # Show command usage history with savings
rtk discover          # Analyze Claude Code history for missed opportunities
rtk proxy <cmd>       # Execute raw command without filtering (for debugging)
```

## Installation Verification

```bash
rtk --version         # Should show: rtk X.Y.Z
rtk gain              # Should work (not "command not found")
which rtk             # Verify correct binary
```

⚠️ **Name collision**: If `rtk gain` fails, you may have reachingforthejack/rtk (Rust Type Kit) installed instead.

## Hook-Based Usage

All other commands are automatically rewritten by the Claude Code hook.
Example: `git status` → `rtk git status` (transparent, 0 tokens overhead)

Refer to CLAUDE.md for full command reference.

## When to bypass RTK (use `rtk proxy <cmd>`)

RTK reshapes output for token savings — that's a problem when another
tool will *parse* the output. The reshape strips diff headers, normalizes
whitespace, and truncates long sections, all of which break downstream
parsers. There's no auto-detection (verified 2026-05-21 — community
guidance is "use `rtk proxy` explicitly").

**Always use `rtk proxy` for these — output is parsed by another tool:**

| Command class | Why |
|---|---|
| `git diff` piped to `\| git apply`, `\| patch`, `> file.patch` | Unified-diff format must stay bit-exact; missing `diff --git`/`index`/`---`/`+++` headers cause `error: No valid patches in input` |
| `git format-patch` | Same — mbox + diff format breaks |
| `git apply --check` | Reads diff format strictly |
| `diff -u` / `diff -ru` piped to anything | Unified diff |
| `git log --format=...` with a custom format consumed downstream | Custom format gets normalized |
| `git show <sha>` if you need the diff body verbatim | Diff portion gets reshaped |
| `jq <expr>` if output is piped to another structured-data tool | JSON shape may be reformatted |
| `lsblk -J` / `lsblk -P` (JSON / pair output) | Same |
| `find -print0 \| xargs -0` | NUL-delimited stream — reshape can corrupt |
| Any `--porcelain` / `-z` / `--null` output | These formats are explicitly "machine-parseable" |

**Heuristic for agents:** if you're piping the command into a parser (`|
jq`, `| git apply`, `| patch`, `| awk`, `| python -c`, redirect into a
file that another tool will read structured) — prepend `rtk proxy`.

**Don't bypass for:** `git diff` displayed to the user, `git log` for
overview, `git status`, `cat`/`head`/`tail` for human consumption, any
output you read once and act on without re-parsing.
