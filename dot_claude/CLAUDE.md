# Claude Instructions (Global)

## Dotfiles = chezmoi · source: `~/.local/share/chezmoi/` · public repo NullSense/dotfiles
Files under `~/.config/`, `~/.zshrc`, `~/.gitconfig` are TARGETS. Editing a target without
mirroring to source = silent data loss (next `chezmoi apply`/`update` overwrites it).

- **Never edit a target without mirroring to source in the same response** — either edit the
  source then `chezmoi apply <target>` (preferred), or edit the target then `chezmoi re-add <target>`.
- Path map: `dot_<n>`→`~/.<n>` · `dot_config/<x>`→`~/.config/<x>` · `private_<n>`→0600 ·
  `executable_<n>`→+x · `*.tmpl`→Go-template · `symlink_<n>`→symlink.
- `chezmoi apply` auto-commits AND pushes to the **public** repo — treat applied changes as
  immediately public; never say "local/not pushed". It also bundles unrelated drift.
- **Policy (2026-07-03): commit drift as you go.** Keep source synced — `re-add` modified targets
  (target→source, captures live state) and commit + push, don't let drift accumulate. Still never
  blind-`apply` over an `MM` target (that clobbers live target edits); resolve `MM` via `re-add`,
  not `apply`. Only pause for secrets in the diff (trufflehog gates the push regardless).
- Never restore files marked `D` (intentionally migrated). Untracked source = unbacked work.
- Commands: `chezmoi status|diff|apply [p]|re-add [p]|edit [p]|cd|git -- <cmd>`.

## Git
Commit finished, verified work without being asked; for chezmoi source, commit + push (autopush
expected). Pause first ONLY if it would bundle unrelated drift, include secrets, rewrite pushed
history, or land on a protected branch with no feature branch.

## Keybindings
Before binding any shortcut (Hyprland/app/shell), grep the config for the exact modifier+key and
confirm it's free; also scan `hyprctl binds` live. If taken, don't clobber — pick a free mnemonic
and tell the user. Hyprland binds: `dot_config/hypr/bindings.conf`.
Taken (non-exhaustive): SUPER+ALT+ C=Capture · D=Dictation · V=Voice menu · R=Recording · G=Grab.

## Testing
Fix a bug → write a regression test immediately (TDD preferred).

## Library docs → Context7 (never web search)
Resolve the ID first, then fetch a narrow topic (1–2k tokens; 5k+ for overviews). Reuse resolved
IDs in-session. Check the version against project deps.

## Research before answering (services, libraries, APIs, tools) — never from memory
For any question about a third-party service/library/API/tool — even well-known ones — search until
confident, THEN answer with the LATEST data. Don't answer from training memory alone.
1. **Service/product** (apps, SaaS, hardware, OS features) → the service's **official docs** first.
2. Official docs missing/thin on the answer → **exa** web search for current real-world fixes/issues.
3. **Dev / libraries** → **Context7 + GitHub + Hugging Face** MCPs/searches (resolve the lib, read
   current docs + issues + model cards); see Library docs → Context7 above for the Context7 flow.

## Structured memory → `~/.claude/memory/`
`general.md` (cross-project conventions) · `tools/*.md` · `domain/*.md`. Write new cross-project
conventions there, not into this file. Keep this file to top-level preferences only.

@RTK.md


<!-- headroom:rtk-instructions -->
# RTK (Rust Token Killer) - Token-Optimized Commands

When running shell commands, **always prefix with `rtk`**. This reduces context
usage by 60-90% with zero behavior change. If rtk has no filter for a command,
it passes through unchanged — so it is always safe to use.

## Key Commands
```bash
# Git (59-80% savings)
rtk git status          rtk git diff            rtk git log

# Files & Search (60-75% savings)
rtk ls <path>           rtk read <file>         rtk grep <pattern>
rtk find <pattern>      rtk diff <file>

# Test (90-99% savings) — shows failures only
rtk pytest tests/       rtk cargo test          rtk test <cmd>

# Build & Lint (80-90% savings) — shows errors only
rtk tsc                 rtk lint                rtk cargo build
rtk prettier --check    rtk mypy                rtk ruff check

# Analysis (70-90% savings)
rtk err <cmd>           rtk log <file>          rtk json <file>
rtk summary <cmd>       rtk deps                rtk env

# GitHub (26-87% savings)
rtk gh pr view <n>      rtk gh run list         rtk gh issue list

# Infrastructure (85% savings)
rtk docker ps           rtk kubectl get         rtk docker logs <c>

# Package managers (70-90% savings)
rtk pip list            rtk pnpm install        rtk npm run <script>
```

## Rules
- In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
- For debugging, use raw command without rtk prefix
- `rtk proxy <cmd>` runs command without filtering but tracks usage
<!-- /headroom:rtk-instructions -->
