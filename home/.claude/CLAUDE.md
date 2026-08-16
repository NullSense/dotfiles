# Claude Instructions (Global)

## Dotfiles = plain Git + direct symlinks · repo: `~/.dotfiles/` · public NullSense/dotfiles
Tracked home files live under `~/.dotfiles/home/` using their literal paths. Each live target is an
individual symlink into that tree, so editing `~/.zshrc` or `~/.config/foo` directly edits the
Git-tracked file. There is no render/apply/re-add layer and no encoded filename vocabulary.

**Canonical workflow:** edit the live home path, inspect `git -C ~/.dotfiles diff`, then commit and
push deliberately. `~/.dotfiles/install.sh --check` verifies every tracked target; `--install`
repairs links and preserves conflicting files under `~/.local/state/dotfiles-backups/`.

- Never put plaintext credentials in this public repository. Use Infisical, Agent Vault, systemd
  encrypted credentials, or ignored local state.
- MCP inventory lives at `~/.dotfiles/mcp/servers.yaml`; run `mcp-sync` after editing it.
- New dotfiles go under the literal `home/` path, then run `~/.dotfiles/install.sh --install`.
- Repository-only documentation and bootstrap tools stay outside `home/` and are not linked.

## Git
Commit finished, verified work without being asked. For dotfiles, commit from `~/.dotfiles` and
push deliberately; a push publishes immediately to a public repository. Pause
before pushing ONLY if it would bundle unrelated drift, include secrets, rewrite pushed history,
or land on a protected branch with no feature branch.

## Keybindings
Before binding any shortcut (Hyprland/app/shell), grep the config for the exact modifier+key and
confirm it's free; also scan `hyprctl binds` live. If taken, don't clobber — pick a free mnemonic
and tell the user. Hyprland binds: `~/.config/hypr/bindings.conf`.
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
