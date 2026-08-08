# Claude Instructions (Global)

## Dotfiles = chezmoi · source: `~/.local/share/chezmoi/` · public repo NullSense/dotfiles
Home files like `~/.zshrc`, `~/.config/**`, `~/.gitconfig` are chezmoi TARGETS rendered from SOURCE
files under `~/.local/share/chezmoi/`. Source is authoritative — a bare `chezmoi apply` regenerates
targets from source, so a target edited in place gets silently reverted.

**Canonical workflow — ONE rule: edit SOURCE, then apply that ONE target.**
1. `chezmoi source-path <target>` → open that source file (they're normal files: `dot_zshrc`,
   `dot_config/foo.tmpl`, …). Edit with your normal Edit/Write tools. For a `*.tmpl`, edit the
   `.tmpl`, never the rendered target.
2. `chezmoi apply <target>` — targeted. Avoid bare `chezmoi apply` (it reconciles the whole tree).
3. Commit + push deliberately: `chezmoi git -- commit -am "…"` then `chezmoi git -- push`.
   **autoPush is OFF** — nothing is public until you push; a push IS immediately public (repo is
   public; `private_*` is a permission marker, not encryption). trufflehog gates the push.

- Path map: `dot_<n>`→`~/.<n>` · `dot_config/<x>`→`~/.config/<x>` · `private_<n>`→0600 ·
  `executable_<n>`→+x · `*.tmpl`→Go-template · `symlink_<n>`→symlink.
- Humans get a live loop: `chezmoi edit <target>` (auto-applies on exit) or `chezmoi edit --watch
  <target>` (applies on every save). Agents: use step 1–2 above (your tools edit files, not $EDITOR).
- Capturing an edit made OUTSIDE chezmoi (target changed directly): `chezmoi re-add <target>`
  (target→source). This is the exception — prefer editing source. Never blind-`apply` over an `MM`
  target; inspect `chezmoi status`/`diff` first. Never restore `D` files (intentionally migrated).
- Works in the agent sandbox: source-tree secrets (`SECRETS.md`, `private_*`) are masked with empty
  regular files so the tree-walk survives (fixed 2026-07-14; was `/dev/null`, which crashed every
  chezmoi command → hand-cp workarounds). Targeted apply is the safe path there.
- Commands: `chezmoi status|diff|apply <p>|re-add <p>|edit <p>|source-path <p>|cd|git -- <cmd>`.

## Git
Commit finished, verified work without being asked. For chezmoi source, `chezmoi git -- commit`
then `chezmoi git -- push` (autoPush is OFF — push is a deliberate step, not automatic). Pause
before pushing ONLY if it would bundle unrelated drift, include secrets, rewrite pushed history,
or land on a protected branch with no feature branch.

## Keybindings
Before binding any shortcut (Hyprland/app/shell), grep the config for the exact modifier+key and
confirm it's free; also scan `hyprctl binds` live. If taken, don't clobber — pick a free mnemonic
and tell the user. Hyprland binds: `dot_config/hypr/bindings.conf`.
Taken (non-exhaustive): SUPER+ALT+ C=Capture · D=Dictation · V=Voice menu · R=Recording · G=Grab.

## Testing
Fix a bug → write a regression test immediately (TDD preferred).

## Documentation and web research — never answer third-party facts from memory
- **Known libraries, SDKs, CLIs, and developer tools → Context7 MCP first.** Resolve the library ID,
  verify it against the project-pinned version, then fetch a narrow topic (1–2k tokens; 5k+ for
  overviews). Reuse resolved IDs in-session.
- **Whenever a web search is needed → Exa first.** Use regular web search only when Exa is
  unavailable or still has no relevant result after a sensible reformulation. Fetching an already
  known authoritative URL directly is not a web search.
- **Services/products** (apps, SaaS, hardware, OS features) → use current official documentation as
  evidence; use Exa to discover the right official page and then current real-world fixes/issues.
- **Libraries/models** → after Context7, use official versioned docs, GitHub, and Hugging Face model
  cards/issues as appropriate. Never rely on training memory for a current claim.

## Memory
- Required behavior and durable rules belong in this file or the closest project `AGENTS.md` /
  `CLAUDE.md`; native memory is a recall aid, never the sole authority.
- Curated cross-agent notes live under `~/.claude/memory/`: start with `MEMORY.md`, then read only
  the relevant `tools/*.md` or `domain/*.md`. Add durable cross-project findings there rather than
  bloating this top-level guidance.
- Codex native memories (`~/.codex/memories/`) and Claude-mem are generated state. Let their owning
  agent manage them; do not hand-edit their databases or generated files.

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
# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.
