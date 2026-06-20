# RTK — Rust Token Killer

Token-optimized CLI proxy (60–90% savings). A Claude Code hook auto-rewrites commands
(`git status` → `rtk git status`, 0 overhead). Run meta-commands directly:
`rtk gain [--history]` · `rtk discover` · `rtk proxy <cmd>` (raw/unfiltered).

Sanity: `rtk --version` and `rtk gain` must work. If `rtk gain` fails you have the wrong binary
(reachingforthejack/rtk = Rust Type Kit) — check `which rtk`.

## Bypass with `rtk proxy <cmd>` when output is PARSED by another tool
RTK reshapes output (strips diff headers, normalizes whitespace, truncates) — fine for humans,
breaks parsers; there's no auto-detection.

**Heuristic: if you pipe into a parser (`| jq`, `| git apply`, `| patch`, `| awk`, `| python -c`)
or redirect to a file another tool reads → prepend `rtk proxy`.** Covers: unified diffs fed to
apply/patch (`git diff|format-patch|apply --check|show`, `diff -u`); `--porcelain`/`-z`/`--null`,
JSON/pair output (`lsblk -J`); NUL streams (`find -print0 | xargs -0`); custom `git log --format`
consumed downstream.

Don't bypass for human-facing output (`git diff|log|status` shown to the user, `cat`/`head`/`tail`).
