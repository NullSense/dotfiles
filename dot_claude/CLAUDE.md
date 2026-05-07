# Claude Instructions (Global)

## ⚠️ Dotfiles are managed by chezmoi — DO NOT edit `~/.config/...` directly

This machine uses **chezmoi**. Source-of-truth is `~/.local/share/chezmoi/`
(itself a git repo, remote `github.com:NullSense/dotfiles`). Live config files
under `~/.config/...`, `~/.zshrc`, `~/.gitconfig`, etc. are TARGETS that chezmoi
writes to; they are not authoritative.

**The silent-data-loss trap**: if you edit `~/.config/foo/bar` directly without
telling chezmoi, the next `chezmoi apply` (run by you, the user, another agent,
or `chezmoi update` on a different machine) will overwrite your edit with the
stale source version. The work disappears with no warning.

### Rules — non-negotiable

1. **Never edit a target file directly without immediately mirroring to source.**
   When you edit `~/.config/hypr/foo.conf`, in the same response either:
   - Edit the chezmoi source file `~/.local/share/chezmoi/dot_config/hypr/foo.conf`
     and run `chezmoi apply ~/.config/hypr/foo.conf` to push to target. ← preferred
   - Or, after editing the target, run `chezmoi re-add ~/.config/hypr/foo.conf`
     to capture the live edit back into source.

2. **Path mapping** (chezmoi source → target):
   - `dot_<name>` → `~/.<name>` (e.g. `dot_zshrc` → `~/.zshrc`)
   - `dot_config/<x>` → `~/.config/<x>`
   - `private_<name>` → `~/.<name>` with `0600` perms
   - `executable_<name>` → file with `+x`
   - `*.tmpl` → rendered through chezmoi's template engine (Go templates)
   - `symlink_<name>` → symlink whose target is the file's contents

3. **Before committing, always check `chezmoi status`**. Lines like `MM` mean
   both source AND target diverged from the last apply — running `chezmoi apply`
   blindly there destroys the target's edits. If you see drift you didn't
   create, surface it to the user before resolving.

4. **The chezmoi source repo is itself a git repo.** After source edits, commit
   in `~/.local/share/chezmoi/` (or via `chezmoi git -- commit`). Untracked
   files in source = unbacked work, ask before ending session.

5. **Never bring back files chezmoi has marked deleted** (`D` in status). They
   were intentionally migrated away.

### Quick reference

```
chezmoi status              # see drift (must be clean before apply)
chezmoi diff                # what apply WOULD overwrite (read first!)
chezmoi apply [path]        # source → target
chezmoi re-add [path]       # target → source (capture live edit)
chezmoi edit [path]         # edit source, auto-applies on save
chezmoi cd                  # cd into source repo for git ops
chezmoi git -- <gitcmd>     # run git in source repo without cd
```

If unsure which side has the right content, **ask the user**. The cost of asking
is one prompt; the cost of overwriting their work is permanent.

## Testing
- Fix bugs → immediately write unit tests (TDD preferred)
- Long-standing bug fixes MUST include regression tests to prevent recurrence

## Documentation
- Always use Context7 for library docs (not web search)
- Prefer narrow topics: "persist middleware" not "state management"
- Use 1000-2000 tokens for focused queries, 5000+ for comprehensive overviews

## Context7 Strategy
- Resolve library ID first with `resolve-library-id`
- Then fetch docs with narrow, specific topic
- Reuse resolved library IDs within same session
- Always check version compatibility with project dependencies

## Structured memory directory

Cross-project knowledge lives in `~/.claude/memory/`:
- `general.md` — cross-project conventions (style, defaults, workflow preferences)
- `tools/*.md` — per-tool learnings (git.md, docker.md, cargo.md, pnpm.md, etc.)
- `domain/*.md` — per-domain patterns (rust.md, typescript.md, search.md, etc.)

When you learn a cross-project convention, write it to the appropriate file here
instead of expanding this CLAUDE.md. Keep this file focused on top-level
preferences only — concise indexes age better than sprawling ones.
